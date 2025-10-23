;; title: Freight-Payment-Escrow-Smart-Contract

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-insufficient-payment (err u105))
(define-constant err-already-confirmed (err u106))
(define-constant err-timeout-not-reached (err u107))
(define-constant err-invalid-amount (err u108))
(define-constant err-carrier-not-assigned (err u109))
(define-constant err-dispute-active (err u110))

(define-constant status-created u1)
(define-constant status-assigned u2)
(define-constant status-in-transit u3)
(define-constant status-delivered u4)
(define-constant status-completed u5)
(define-constant status-disputed u6)
(define-constant status-cancelled u7)

(define-data-var shipment-nonce uint u0)
(define-data-var platform-fee-percentage uint u2)
(define-data-var dispute-timeout-blocks uint u144)

(define-map shipments
  uint
  {
    shipper: principal,
    carrier: (optional principal),
    payment-amount: uint,
    platform-fee: uint,
    status: uint,
    created-at: uint,
    pickup-location: (string-ascii 100),
    delivery-location: (string-ascii 100),
    estimated-delivery-block: uint,
    delivery-confirmed-at: (optional uint),
    gps-oracle: (optional principal),
    dispute-reason: (optional (string-ascii 200))
  }
)

(define-map carrier-ratings
  principal
  {
    total-deliveries: uint,
    successful-deliveries: uint,
    rating-sum: uint
  }
)

(define-map shipment-confirmations
  uint
  {
    confirmed-by: principal,
    confirmation-block: uint,
    gps-data: (optional (string-ascii 100))
  }
)

(define-map authorized-oracles principal bool)

(define-read-only (get-shipment (shipment-id uint))
  (map-get? shipments shipment-id)
)

(define-read-only (get-carrier-rating (carrier principal))
  (default-to 
    {total-deliveries: u0, successful-deliveries: u0, rating-sum: u0}
    (map-get? carrier-ratings carrier)
  )
)

(define-read-only (get-shipment-confirmation (shipment-id uint))
  (map-get? shipment-confirmations shipment-id)
)

(define-read-only (is-authorized-oracle (oracle principal))
  (default-to false (map-get? authorized-oracles oracle))
)

(define-read-only (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) u100)
)

(define-read-only (get-platform-fee-percentage)
  (ok (var-get platform-fee-percentage))
)

(define-read-only (get-dispute-timeout)
  (ok (var-get dispute-timeout-blocks))
)

(define-public (create-shipment 
  (payment-amount uint)
  (pickup-location (string-ascii 100))
  (delivery-location (string-ascii 100))
  (estimated-delivery-blocks uint)
  (gps-oracle (optional principal))
)
  (let
    (
      (shipment-id (+ (var-get shipment-nonce) u1))
      (platform-fee (calculate-platform-fee payment-amount))
      (total-payment (+ payment-amount platform-fee))
      (estimated-block (+ stacks-block-height estimated-delivery-blocks))
    )
    (asserts! (> payment-amount u0) err-invalid-amount)
    (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
    (map-set shipments shipment-id {
      shipper: tx-sender,
      carrier: none,
      payment-amount: payment-amount,
      platform-fee: platform-fee,
      status: status-created,
      created-at: stacks-block-height,
      pickup-location: pickup-location,
      delivery-location: delivery-location,
      estimated-delivery-block: estimated-block,
      delivery-confirmed-at: none,
      gps-oracle: gps-oracle,
      dispute-reason: none
    })
    (var-set shipment-nonce shipment-id)
    (ok shipment-id)
  )
)

(define-public (accept-shipment (shipment-id uint))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
    )
    (asserts! (is-eq (get status shipment) status-created) err-invalid-status)
    (map-set shipments shipment-id (merge shipment {
      carrier: (some tx-sender),
      status: status-assigned
    }))
    (ok true)
  )
)

(define-public (start-transit (shipment-id uint))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
    )
    (asserts! (is-eq (some tx-sender) (get carrier shipment)) err-unauthorized)
    (asserts! (is-eq (get status shipment) status-assigned) err-invalid-status)
    (map-set shipments shipment-id (merge shipment {
      status: status-in-transit
    }))
    (ok true)
  )
)

(define-public (confirm-delivery (shipment-id uint) (gps-data (optional (string-ascii 100))))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
      (caller-is-shipper (is-eq tx-sender (get shipper shipment)))
      (caller-is-carrier (is-eq (some tx-sender) (get carrier shipment)))
      (caller-is-oracle (and 
        (is-some (get gps-oracle shipment))
        (is-eq (some tx-sender) (get gps-oracle shipment))
        (is-authorized-oracle tx-sender)
      ))
    )
    (asserts! (is-eq (get status shipment) status-in-transit) err-invalid-status)
    (asserts! (or caller-is-shipper (or caller-is-carrier caller-is-oracle)) err-unauthorized)
    (map-set shipment-confirmations shipment-id {
      confirmed-by: tx-sender,
      confirmation-block: stacks-block-height,
      gps-data: gps-data
    })
    (map-set shipments shipment-id (merge shipment {
      status: status-delivered,
      delivery-confirmed-at: (some stacks-block-height)
    }))
    (try! (release-payment shipment-id))
    (ok true)
  )
)

(define-private (release-payment (shipment-id uint))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
      (carrier (unwrap! (get carrier shipment) err-carrier-not-assigned))
      (payment (get payment-amount shipment))
      (fee (get platform-fee shipment))
    )
    (try! (as-contract (stx-transfer? payment tx-sender carrier)))
    (try! (as-contract (stx-transfer? fee tx-sender contract-owner)))
    (map-set shipments shipment-id (merge shipment {
      status: status-completed
    }))
    (update-carrier-rating carrier true)
    (ok true)
  )
)

(define-private (update-carrier-rating (carrier principal) (successful bool))
  (let
    (
      (current-rating (get-carrier-rating carrier))
      (new-total (+ (get total-deliveries current-rating) u1))
      (new-successful (if successful 
        (+ (get successful-deliveries current-rating) u1)
        (get successful-deliveries current-rating)
      ))
    )
    (map-set carrier-ratings carrier {
      total-deliveries: new-total,
      successful-deliveries: new-successful,
      rating-sum: (get rating-sum current-rating)
    })
  )
)

(define-public (raise-dispute (shipment-id uint) (reason (string-ascii 200)))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
      (caller-is-shipper (is-eq tx-sender (get shipper shipment)))
      (caller-is-carrier (is-eq (some tx-sender) (get carrier shipment)))
    )
    (asserts! (or caller-is-shipper caller-is-carrier) err-unauthorized)
    (asserts! (or 
      (is-eq (get status shipment) status-in-transit)
      (is-eq (get status shipment) status-assigned)
    ) err-invalid-status)
    (map-set shipments shipment-id (merge shipment {
      status: status-disputed,
      dispute-reason: (some reason)
    }))
    (ok true)
  )
)

(define-public (resolve-dispute (shipment-id uint) (release-to-carrier bool))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
      (carrier (unwrap! (get carrier shipment) err-carrier-not-assigned))
      (payment (get payment-amount shipment))
      (fee (get platform-fee shipment))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status shipment) status-disputed) err-invalid-status)
    (if release-to-carrier
      (begin
        (try! (as-contract (stx-transfer? payment tx-sender carrier)))
        (try! (as-contract (stx-transfer? fee tx-sender contract-owner)))
        (update-carrier-rating carrier true)
        (map-set shipments shipment-id (merge shipment {status: status-completed}))
      )
      (begin
        (try! (as-contract (stx-transfer? (+ payment fee) tx-sender (get shipper shipment))))
        (update-carrier-rating carrier false)
        (map-set shipments shipment-id (merge shipment {status: status-cancelled}))
      )
    )
    (ok true)
  )
)

(define-public (cancel-shipment (shipment-id uint))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
      (payment (get payment-amount shipment))
      (fee (get platform-fee shipment))
    )
    (asserts! (is-eq tx-sender (get shipper shipment)) err-unauthorized)
    (asserts! (is-eq (get status shipment) status-created) err-invalid-status)
    (try! (as-contract (stx-transfer? (+ payment fee) tx-sender (get shipper shipment))))
    (map-set shipments shipment-id (merge shipment {
      status: status-cancelled
    }))
    (ok true)
  )
)

(define-public (claim-timeout-refund (shipment-id uint))
  (let
    (
      (shipment (unwrap! (map-get? shipments shipment-id) err-not-found))
      (payment (get payment-amount shipment))
      (fee (get platform-fee shipment))
      (timeout-block (+ (get estimated-delivery-block shipment) (var-get dispute-timeout-blocks)))
    )
    (asserts! (is-eq tx-sender (get shipper shipment)) err-unauthorized)
    (asserts! (is-eq (get status shipment) status-in-transit) err-invalid-status)
    (asserts! (>= stacks-block-height timeout-block) err-timeout-not-reached)
    (try! (as-contract (stx-transfer? (+ payment fee) tx-sender (get shipper shipment))))
    (map-set shipments shipment-id (merge shipment {
      status: status-cancelled
    }))
    (ok true)
  )
)

(define-public (add-authorized-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-oracles oracle true))
  )
)

(define-public (remove-authorized-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-oracles oracle))
  )
)

(define-public (set-platform-fee (new-fee-percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee-percentage u10) err-invalid-amount)
    (ok (var-set platform-fee-percentage new-fee-percentage))
  )
)

(define-public (set-dispute-timeout (new-timeout uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set dispute-timeout-blocks new-timeout))
  )
)
