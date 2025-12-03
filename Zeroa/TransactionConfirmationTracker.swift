import Foundation

/// Tracks transaction confirmations and status
class TransactionConfirmationTracker {
    static let shared = TransactionConfirmationTracker()
    
    private init() {}
    
    /// Track a transaction and monitor its confirmations
    /// - Parameters:
    ///   - txid: Transaction ID
    ///   - completion: Called when transaction is confirmed (or fails)
    func trackTransaction(txid: String, completion: @escaping (Int, Bool) -> Void) {
        Task {
            var confirmations = 0
            var maxAttempts = 60 // Check for up to 1 hour (60 * 1 minute)
            var attempts = 0
            
            while attempts < maxAttempts {
                do {
                    // Get transaction info from RPC
                    let response = try await TLSRPCClient.shared.callRPC(
                        method: "gettransaction",
                        params: [AnyCodable(txid)]
                    )
                    
                    if let result = response.result,
                       let txDict = result.value as? [String: Any],
                       let confs = txDict["confirmations"] as? Int {
                        confirmations = confs
                        
                        if confs >= 1 {
                            // Transaction confirmed
                            await MainActor.run {
                                completion(confs, true)
                            }
                            return
                        }
                    }
                    
                    // Wait 1 minute before checking again
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                    attempts += 1
                } catch {
                    print("⚠️ TransactionConfirmationTracker: Error checking transaction: \(error.localizedDescription)")
                    // Continue checking despite errors
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    attempts += 1
                }
            }
            
            // Timeout - transaction may still be pending
            await MainActor.run {
                completion(confirmations, false)
            }
        }
    }
    
    /// Get current confirmation count for a transaction
    func getConfirmations(txid: String) async -> Int {
        do {
            let response = try await TLSRPCClient.shared.callRPC(
                method: "gettransaction",
                params: [AnyCodable(txid)]
            )
            
            if let result = response.result,
               let txDict = result.value as? [String: Any],
               let confs = txDict["confirmations"] as? Int {
                return confs
            }
        } catch {
            print("⚠️ TransactionConfirmationTracker: Error getting confirmations: \(error.localizedDescription)")
        }
        
        return 0
    }
}


