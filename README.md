# 🚚 Freight Payment Escrow Smart Contract

A trustless escrow system for freight shipping payments built on Stacks blockchain using Clarity smart contracts. Shippers deposit payments, carriers get paid automatically once delivery is confirmed by GPS/IoT oracles or authorized parties.

## ✨ Features

- 💰 **Automated Escrow** - Secure payment holding until delivery confirmation
- 📍 **GPS/IoT Oracle Integration** - Support for third-party delivery verification
- 🔒 **Multi-Party Authorization** - Shippers, carriers, or oracles can confirm delivery
- ⚖️ **Dispute Resolution** - Built-in dispute handling mechanism
- ⏱️ **Timeout Protection** - Automatic refunds if delivery exceeds estimated time
- ⭐ **Carrier Ratings** - Track carrier performance and reliability
- 💵 **Platform Fees** - Configurable fee structure (default 2%)

## 🏗️ Architecture

### Contract Status Flow
```
Created → Assigned → In Transit → Delivered → Completed
                          ↓
                      Disputed → Resolved
                          ↓
                     Cancelled (Refund)
```

## 📋 Contract Functions

### 🆕 Creating Shipments

**`create-shipment`**
```clarity
(create-shipment 
  (payment-amount uint)
  (pickup-location (string-ascii 100))
  (delivery-location (string-ascii 100))
  (estimated-delivery-blocks uint)
  (gps-oracle (optional principal))
)
```
Creates a new shipment with escrowed payment (includes 2% platform fee).

### 🚛 Carrier Operations

**`accept-shipment`**
```clarity
(accept-shipment (shipment-id uint))
```
Carrier accepts the shipment assignment.

**`start-transit`**
```clarity
(start-transit (shipment-id uint))
```
Marks shipment as in transit (only assigned carrier).

### ✅ Delivery Confirmation

**`confirm-delivery`**
```clarity
(confirm-delivery (shipment-id uint) (gps-data (optional (string-ascii 100))))
```
Confirms delivery and automatically releases payment. Can be called by:
- Shipper
- Carrier
- Authorized GPS/IoT Oracle

### ⚠️ Dispute Management

**`raise-dispute`**
```clarity
(raise-dispute (shipment-id uint) (reason (string-ascii 200)))
```
Either shipper or carrier can raise a dispute.

**`resolve-dispute`** (Admin only)
```clarity
(resolve-dispute (shipment-id uint) (release-to-carrier bool))
```
Contract owner resolves disputes and directs payment.

### 🔙 Cancellation & Refunds

**`cancel-shipment`**
```clarity
(cancel-shipment (shipment-id uint))
```
Shipper can cancel before carrier accepts (full refund).

**`claim-timeout-refund`**
```clarity
(claim-timeout-refund (shipment-id uint))
```
Shipper claims refund if delivery timeout exceeded (144 blocks after estimated delivery).

### 📊 Read-Only Functions

- `get-shipment` - Get shipment details
- `get-carrier-rating` - View carrier performance metrics
- `get-shipment-confirmation` - Check delivery confirmation data
- `is-authorized-oracle` - Verify oracle authorization
- `calculate-platform-fee` - Calculate fee for amount
- `get-platform-fee-percentage` - Current fee percentage
- `get-dispute-timeout` - Current dispute timeout blocks

### 🔧 Admin Functions

**`add-authorized-oracle`** / **`remove-authorized-oracle`**
```clarity
(add-authorized-oracle (oracle principal))
```
Manage GPS/IoT oracle authorizations.

**`set-platform-fee`**
```clarity
(set-platform-fee (new-fee-percentage uint))
```
Update platform fee (max 10%).

**`set-dispute-timeout`**
```clarity
(set-dispute-timeout (new-timeout uint))
```
Adjust timeout period for refund claims.

## 🚀 Getting Started

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation

1. Clone the repository
```bash
git clone <your-repo-url>
cd Freight-Payment-Escrow-Smart-Contract
```

2. Check contract validity
```bash
clarinet check
```

3. Run tests
```bash
clarinet test
```

### Deployment

1. Configure your deployment settings in `Clarinet.toml`
2. Deploy to testnet:
```bash
clarinet deploy --testnet
```

## 💡 Usage Example

### Creating a Shipment (Shipper)
```bash
clarinet console
>> (contract-call? .Freight-Payment-Escrow-Smart-Contract create-shipment 
    u1000000 
    "New York Warehouse" 
    "Los Angeles Hub" 
    u1000 
    none)
```

### Accepting Shipment (Carrier)
```bash
>> (contract-call? .Freight-Payment-Escrow-Smart-Contract accept-shipment u1)
```

### Starting Transit (Carrier)
```bash
>> (contract-call? .Freight-Payment-Escrow-Smart-Contract start-transit u1)
```

### Confirming Delivery (Any Authorized Party)
```bash
>> (contract-call? .Freight-Payment-Escrow-Smart-Contract confirm-delivery 
    u1 
    (some "GPS:34.0522,-118.2437"))
```

## 🔐 Security Features

- ✅ Owner-only admin functions
- ✅ Role-based access control (shipper/carrier/oracle)
- ✅ Status validation for state transitions
- ✅ Automatic payment release only after confirmation
- ✅ Timeout protection with refund mechanism
- ✅ Dispute resolution system

## 📈 Carrier Rating System

The contract tracks carrier performance:
- **Total Deliveries** - Number of completed shipments
- **Successful Deliveries** - Successfully delivered without disputes
- **Rating Sum** - Aggregate rating (for future enhancement)

## 🤝 Integration with GPS/IoT Oracles

1. Deploy GPS/IoT oracle service
2. Authorize oracle via `add-authorized-oracle`
3. Oracle principal provided during shipment creation
4. Oracle can call `confirm-delivery` with GPS data

## 📝 Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner only operation |
| u101 | Shipment not found |
| u102 | Unauthorized caller |
| u103 | Already exists |
| u104 | Invalid status transition |
| u105 | Insufficient payment |
| u106 | Already confirmed |
| u107 | Timeout not reached |
| u108 | Invalid amount |
| u109 | Carrier not assigned |
| u110 | Dispute active |

## 🛣️ Roadmap

- [ ] Multi-signature confirmation requirements
- [ ] Partial payment milestones
- [ ] Insurance pool integration
- [ ] Advanced carrier reputation algorithm
- [ ] Mobile app integration
- [ ] Real-time GPS tracking integration

## 📄 License

MIT

## 🙋 Support

For issues and questions, please open an issue on GitHub.

---

Built with ❤️ on Stacks Blockchain
