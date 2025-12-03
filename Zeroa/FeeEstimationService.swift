import Foundation

/// Fee priority levels for transaction fees
enum FeePriority: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// Service for estimating transaction fees dynamically
class FeeEstimationService {
    static let shared = FeeEstimationService()
    
    private init() {}
    
    /// Estimate fee based on transaction size (automatically calculated)
    /// - Parameter transactionSizeBytes: Size of the transaction in bytes
    /// - Returns: Estimated fee in TLS
    func estimateFee(transactionSizeBytes: Int) async -> Double {
        // Get fee rate from network (satoshis per byte)
        let feeRatePerByte = await getFeeRate()
        
        // Calculate fee: size * rate / 100000000 (convert satoshis to TLS)
        // Note: TLS uses same decimal places as Bitcoin (8 decimals)
        let fee = Double(transactionSizeBytes) * feeRatePerByte / 100000000.0
        
        // Ensure minimum fee meets network relay requirements
        // Telestai minimum relay fee is typically higher than Bitcoin
        // Use 0.0001 TLS (10000 satoshis) as minimum to ensure transactions are relayed
        let minimumFee = 0.0001 // 0.0001 TLS minimum (10000 satoshis)
        return max(fee, minimumFee)
    }
    
    /// Get fee rate (satoshis per byte) - automatically calculated
    /// - Returns: Fee rate in satoshis per byte
    private func getFeeRate() async -> Double {
        // Try to get fee rate from RPC first
        if let networkFeeRate = await getNetworkFeeRate() {
            return networkFeeRate
        }
        
        // Fallback to default rate (medium priority - balanced)
        // 20 satoshis per byte ensures transactions are relayed quickly
        return 20.0
    }
    
    /// Get fee rate from network via RPC
    private func getNetworkFeeRate() async -> Double? {
        // Try to get minimum relay fee from getnetworkinfo
        do {
            let response = try await TLSRPCClient.shared.callRPC(method: "getnetworkinfo", params: [])
            if let result = response.result,
               let networkInfo = result.value as? [String: Any],
               let minRelayFee = networkInfo["relayfee"] as? Double {
                // minRelayFee is in TLS (already converted)
                // Convert to satoshis per byte (approximate)
                // For a typical 250-byte transaction, ensure we meet minimum
                let minRelayFeeSatoshis = minRelayFee * 100000000.0
                let minRatePerByte = max(minRelayFeeSatoshis / 250.0, 10.0) // At least 10 sat/byte
                
                // Use 2x multiplier to ensure fast confirmation (equivalent to medium priority)
                return minRatePerByte * 2.0
            }
        } catch {
            print("⚠️ FeeEstimationService: Could not get network fee rate: \(error.localizedDescription)")
        }
        
        // Fallback to default rate
        return nil
    }
    
    /// Convert priority to block target
    private func priorityToBlocks(_ priority: FeePriority) -> Int {
        switch priority {
        case .low: return 6 // ~1 hour
        case .medium: return 3 // ~30 minutes
        case .high: return 1 // ~10 minutes
        }
    }
    
    /// Calculate transaction size in bytes
    /// - Parameters:
    ///   - inputCount: Number of transaction inputs
    ///   - outputCount: Number of transaction outputs
    /// - Returns: Estimated transaction size in bytes
    func estimateTransactionSize(inputCount: Int, outputCount: Int) -> Int {
        // Base transaction size: version (4) + locktime (4) + input count (1-9) + output count (1-9)
        let baseSize = 10
        
        // Each input: prevout (36) + script length (1) + script (107 for P2PKH) + sequence (4)
        let inputSize = 36 + 1 + 107 + 4 // ~148 bytes per input
        
        // Each output: value (8) + script length (1) + script (25 for P2PKH)
        let outputSize = 8 + 1 + 25 // ~34 bytes per output
        
        let totalSize = baseSize + (inputCount * inputSize) + (outputCount * outputSize)
        
        return totalSize
    }
}


