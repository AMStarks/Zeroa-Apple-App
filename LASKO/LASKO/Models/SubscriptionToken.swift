import Foundation

struct SubscriptionToken: Codable {
    let txid: String
    let signature: String?
    let userAddress: String
    let timestamp: Int64
    let expiresAt: Int64
    let subscriptionAddress: String
    let amount: Double
    
    init(txid: String, signature: String?, userAddress: String, timestamp: Int64, expiresAt: Int64, subscriptionAddress: String, amount: Double) {
        self.txid = txid
        self.signature = signature
        self.userAddress = userAddress
        self.timestamp = timestamp
        self.expiresAt = expiresAt
        self.subscriptionAddress = subscriptionAddress
        self.amount = amount
    }
    
    var isExpired: Bool {
        return Int64(Date().timeIntervalSince1970 * 1000) > expiresAt
    }
    
    var isValid: Bool {
        return !txid.isEmpty && !userAddress.isEmpty && !isExpired
    }
}

