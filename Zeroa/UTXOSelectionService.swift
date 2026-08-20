import Foundation

/// Service for intelligent UTXO selection algorithms
class UTXOSelectionService {
    static let shared = UTXOSelectionService()
    
    private init() {}
    
    /// Select UTXOs using Branch and Bound algorithm (finds exact match when possible)
    /// - Parameters:
    ///   - utxos: Available UTXOs
    ///   - targetAmount: Target amount needed (including fees)
    /// - Returns: Selected UTXOs and change amount
    func selectUTXOs(utxos: [UTXO], targetAmount: Double) -> (selected: [UTXO], change: Double) {
        // Sort UTXOs by amount (ascending for BnB)
        let sorted = utxos.sorted { $0.amount < $1.amount }
        
        // Try Branch and Bound for exact match
        if let exactMatch = branchAndBound(utxos: sorted, target: targetAmount) {
            let total = exactMatch.reduce(0.0) { $0 + $1.amount }
            return (exactMatch, total - targetAmount)
        }
        
        // Fallback to largest-first greedy if no exact match
        return greedyLargestFirst(utxos: sorted, target: targetAmount)
    }
    
    /// Branch and Bound algorithm - finds exact match to minimize change
    private func branchAndBound(utxos: [UTXO], target: Double) -> [UTXO]? {
        var bestSolution: [UTXO]? = nil
        var bestWaste: Double = Double.infinity
        
        func backtrack(index: Int, current: [UTXO], currentSum: Double) {
            // Prune if we've exceeded target by too much
            if currentSum > target + 0.001 { // Allow small tolerance
                return
            }
            
            // Check if this is an exact match or very close
            let waste = currentSum - target
            if waste >= 0 && waste < bestWaste {
                bestWaste = waste
                bestSolution = current
                
                // Exact match found
                if waste < 0.00001 {
                    return
                }
            }
            
            // Prune if we can't improve
            if currentSum + remainingSum(from: index, in: utxos) < target {
                return
            }
            
            // Try including this UTXO
            if index < utxos.count {
                backtrack(index: index + 1, current: current + [utxos[index]], currentSum: currentSum + utxos[index].amount)
                // Try excluding this UTXO
                backtrack(index: index + 1, current: current, currentSum: currentSum)
            }
        }
        
        backtrack(index: 0, current: [], currentSum: 0.0)
        return bestSolution
    }
    
    /// Calculate remaining sum from index
    private func remainingSum(from index: Int, in utxos: [UTXO]) -> Double {
        guard index < utxos.count else { return 0 }
        return utxos[index..<utxos.count].reduce(0.0) { $0 + $1.amount }
    }
    
    /// Greedy algorithm - largest first (fallback)
    private func greedyLargestFirst(utxos: [UTXO], target: Double) -> ([UTXO], Double) {
        let sorted = utxos.sorted { $0.amount > $1.amount }
        var selected: [UTXO] = []
        var total: Double = 0.0
        
        for utxo in sorted {
            selected.append(utxo)
            total += utxo.amount
            if total >= target {
                break
            }
        }
        
        return (selected, total - target)
    }
    
    /// Check if change output would be dust
    /// - Parameter amount: Change amount
    /// - Returns: True if amount is considered dust
    func isDust(_ amount: Double) -> Bool {
        // Dust threshold: 0.00001 TLS (equivalent to 546 satoshis in Bitcoin)
        return amount < 0.00001
    }
    
    /// Warn about dust accumulation
    func checkDustAccumulation(utxos: [UTXO]) -> (hasDust: Bool, dustCount: Int, dustTotal: Double) {
        let dustUTXOs = utxos.filter { isDust($0.amount) }
        let dustTotal = dustUTXOs.reduce(0.0) { $0 + $1.amount }
        return (dustUTXOs.count > 0, dustUTXOs.count, dustTotal)
    }
}

