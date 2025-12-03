import Foundation
import Combine
import CryptoKit
import UIKit

// MARK: - Multi-Coin Transaction Service
@MainActor
class MultiCoinTransactionService: ObservableObject {
    static let shared = MultiCoinTransactionService()
    
    @Published var isConnected = false
    @Published var currentBalances: [CoinType: Double] = [:]
    @Published var recentTransactions: [CoinType: [WalletTransaction]] = [:]
    @Published var pendingTransactions: [String: PendingTransaction] = [:]
    @Published var lastBlockHeights: [CoinType: Int] = [:]
    
    private let walletService = WalletService.shared
    private let walletStore = MultiCoinWalletService.shared
    private var cancellables = Set<AnyCancellable>()
    private var balanceCache: [CoinType: (value: Double, updatedAt: Date)] = [:]
    private let balanceCacheTTL: TimeInterval = 15
    
    // Coin services
    private let coinServices: [CoinType: CoinServiceProtocol] = [
        .telestai: TelestaiCoinServiceAdapter()
    ]
    
    var supportedCoins: [CoinType] {
        coinServices.keys.sorted { $0.rawValue < $1.rawValue }
    }
    
    // TLS service for messaging
    private let tlsService = TLSBlockchainService.shared
    
    init() {
        setupServices()
        startMonitoring()
    }
    
    // MARK: - Service Setup
    private func setupServices() {
        for (coinType, service) in coinServices {
            Task {
                await service.initialize()
                await checkConnection(for: coinType)
            }
        }
    }
    
    private func startMonitoring() {
        // Monitor all coins every 30 seconds
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshAllBalances()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Connection Management
    func checkConnection(for coinType: CoinType) async {
        guard let service = coinServices[coinType] else { return }
        
        let isConnected = await service.checkNetworkStatus()
        await MainActor.run {
            self.isConnected = isConnected
        }
        
        if isConnected {
            await loadBalance(for: coinType)
            await loadTransactionHistory(for: coinType)
        }
    }
    
    // MARK: - Balance Management
    func loadBalance(for coinType: CoinType) async -> Double? {
        guard let address = resolvedAddress(for: coinType),
              let service = coinServices[coinType] else {
            return nil
        }
        
        let balance = await service.getBalance(address: address)
        await MainActor.run {
            self.currentBalances[coinType] = balance.total
        }
        return balance.total
    }
    
    func refreshAllBalances() async {
        let coins = supportedCoins
        let now = Date()
        
        for coin in coins {
            if let cached = balanceCache[coin],
               now.timeIntervalSince(cached.updatedAt) < balanceCacheTTL {
                currentBalances[coin] = cached.value
            }
        }
        
        await withTaskGroup(of: (CoinType, Double?).self) { group in
            for coin in coins {
                group.addTask { [weak self] in
                    guard let self = self else { return (coin, nil) }
                    let value = await self.loadBalance(for: coin)
                    return (coin, value)
                }
            }
            
            for await (coin, value) in group {
                if let value = value {
                    currentBalances[coin] = value
                    balanceCache[coin] = (value, Date())
                }
            }
        }
    }
    
    func getBalance(for coinType: CoinType) -> Double {
        return currentBalances[coinType] ?? 0.0
    }
    
    // MARK: - Transaction History
    func loadTransactionHistory(for coinType: CoinType) async {
        guard let service = coinServices[coinType],
              let address = resolvedAddress(for: coinType) else { return }
        
        let transactions = await service.getTransactionHistory(address: address)
        await MainActor.run {
            self.recentTransactions[coinType] = transactions
        }
    }
    
    func getTransactionHistory(for coinType: CoinType) -> [WalletTransaction] {
        return recentTransactions[coinType] ?? []
    }
    
    // MARK: - Send Transaction
    func sendTransaction(
        coinType: CoinType,
        toAddress: String,
        amount: Double,
        priority: SendTransactionRequest.TransactionPriority = .medium,
        message: String? = nil
    ) async -> SendTransactionResponse {
        guard let service = coinServices[coinType],
              let fromAddress = resolvedAddress(for: coinType) else {
            return SendTransactionResponse(
                success: false,
                txid: nil,
                error: "Service not available or no wallet address",
                fee: nil,
                confirmations: nil
            )
        }
        
        // Validate address
        guard validateAddress(toAddress, for: coinType) else {
            return SendTransactionResponse(
                success: false,
                txid: nil,
                error: "Invalid address format",
                fee: nil,
                confirmations: nil
            )
        }
        
        // Estimate fee
        let estimatedFee = await estimateFee(for: coinType, priority: priority)
        
        let request = SendTransactionRequest(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            fee: estimatedFee,
            priority: priority,
            coinType: coinType
        )
        
        // Send transaction
        guard coinType == .telestai else {
            return SendTransactionResponse(
                success: false,
                txid: nil,
                error: "Only Telestai transactions are currently supported",
                fee: nil,
                confirmations: nil
            )
        }
        
        let response = await service.sendTransaction(request: request)
        
        await MainActor.run {
            if response.success {
                // Add to pending transactions
                let pendingTx = PendingTransaction(
                    txid: response.txid ?? "",
                    coinType: coinType,
                    amount: amount,
                    toAddress: toAddress,
                    timestamp: Date(),
                    status: .pending
                )
                self.pendingTransactions[response.txid ?? ""] = pendingTx
            }
        }
        
        // Refresh balance and transaction history
        await loadBalance(for: coinType)
        await loadTransactionHistory(for: coinType)
        
        return response
    }
    
    // MARK: - TLS Messaging Support
    func sendTLSMessage(
        toAddress: String,
        message: String,
        amount: Double = 0.0,
        // messageType: TLSMessage.TLSMessageType = .text // Type moved to inactive
    ) async -> TLSPaymentResponse {
        return await tlsService.sendPayment(
            toAddress: toAddress,
            amount: amount,
            message: message,
            // messageType: messageType.rawValue // Type moved to inactive
        )
    }
    
    // MARK: - Fee Estimation
    func estimateFee(for coinType: CoinType, priority: SendTransactionRequest.TransactionPriority) async -> Double {
        guard let service = coinServices[coinType] else { return 0.0 }
        
        return await service.estimateFee(priority: priority)
    }
    
    // MARK: - Address Validation
    func validateAddress(_ address: String, for coinType: CoinType) -> Bool {
        // Basic validation - in real implementation, use proper address validation libraries
        switch coinType {
        case .telestai:
            // Telestai address validation
            return address.count >= 26 && address.count <= 35 && 
                   (address.hasPrefix("T") || address.hasPrefix("t"))
        case .bitcoin:
            // Bitcoin address validation (basic)
            return address.count >= 26 && address.count <= 35 && 
                   (address.hasPrefix("1") || address.hasPrefix("3") || address.hasPrefix("bc1"))
        case .flux:
            // Flux address validation
            return address.count >= 26 && address.count <= 35
        case .litecoin:
            // Litecoin address validation
            return address.count >= 26 && address.count <= 35 && 
                   (address.hasPrefix("L") || address.hasPrefix("3") || address.hasPrefix("ltc1"))
        case .kaspa:
            // Kaspa address validation
            return address.count >= 26 && address.count <= 35 && address.hasPrefix("kaspa")
        case .usdt:
            // USDT address validation (uses Bitcoin-style addresses)
            return address.count >= 26 && address.count <= 35 && 
                   (address.hasPrefix("1") || address.hasPrefix("3") || address.hasPrefix("bc1"))
        case .usdc:
            // USDC address validation (uses Bitcoin-style addresses)
            return address.count >= 26 && address.count <= 35 && 
                   (address.hasPrefix("1") || address.hasPrefix("3") || address.hasPrefix("bc1"))
        }
    }
    
    // MARK: - Transaction Monitoring
    func monitorTransaction(txid: String, coinType: CoinType) {
        // In a real implementation, this would monitor transaction confirmation
        // For now, we'll simulate monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if var pendingTx = self?.pendingTransactions[txid] {
                pendingTx.status = .confirmed
                self?.pendingTransactions[txid] = pendingTx
            }
        }
    }
    
    // MARK: - QR Code Generation
    func generateQRCodeData(for address: String) -> Data? {
        // In a real implementation, use a QR code generation library
        // For now, create a simple placeholder
        let size = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.systemGray.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image?.pngData()
    }
    
    // MARK: - Price Data
    func getCurrentPrice(for coinType: CoinType) -> Double {
        // Mock prices - in real implementation, get from price service
        switch coinType {
        case .telestai: return 0.85
        case .bitcoin: return 45000.0
        case .flux: return 0.85
        case .litecoin: return 120.0
        case .kaspa: return 0.12
        case .usdt: return 1.0
        case .usdc: return 1.0
        }
    }
    
    // MARK: - Utility Methods
    func formatAmount(_ amount: Double, for coinType: CoinType) -> String {
        return String(format: "%.8f", amount)
    }
    
    func formatUSD(_ amount: Double, for coinType: CoinType) -> String {
        let usdAmount = amount * getCurrentPrice(for: coinType)
        return String(format: "$%.2f", usdAmount)
    }
    
    func clear() {
        currentBalances.removeAll()
        recentTransactions.removeAll()
        pendingTransactions.removeAll()
        lastBlockHeights.removeAll()
    }

    private func resolvedAddress(for coinType: CoinType) -> String? {
        if let wallet = walletStore.selectedWallet,
           let address = wallet.getAddress(for: coinType) {
            return address
        }
        
        if coinType == .telestai {
            return walletService.loadAddress()
        }
        
        return nil
    }
}

// MARK: - Pending Transaction Model
struct PendingTransaction: Identifiable, Codable {
    var id = UUID()
    let txid: String
    let coinType: CoinType
    let amount: Double
    let toAddress: String
    let timestamp: Date
    var status: TransactionStatus
    
    enum TransactionStatus: String, Codable {
        case pending = "pending"
        case confirmed = "confirmed"
        case failed = "failed"
    }
}

// MARK: - Transaction Summary
struct TransactionSummary {
    let totalTransactions: Int
    let totalVolume: Double
    let averageTransactionSize: Double
    let mostActiveCoin: CoinType?
    
    init(transactions: [WalletTransaction]) {
        self.totalTransactions = transactions.count
        self.totalVolume = transactions.reduce(0) { $0 + abs($1.amount) }
        self.averageTransactionSize = totalTransactions > 0 ? totalVolume / Double(totalTransactions) : 0
        
        // Find most active coin
        let coinCounts = Dictionary(grouping: transactions, by: { $0.coinType })
            .mapValues { $0.count }
        self.mostActiveCoin = coinCounts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Transaction Analytics
extension MultiCoinTransactionService {
    func getTransactionSummary() -> TransactionSummary {
        let allTransactions = supportedCoins.flatMap { coinType in
            getTransactionHistory(for: coinType)
        }
        return TransactionSummary(transactions: allTransactions)
    }
    
    func getCoinTransactionSummary(for coinType: CoinType) -> TransactionSummary {
        let transactions = getTransactionHistory(for: coinType)
        return TransactionSummary(transactions: transactions)
    }
    
    func getRecentActivity(limit: Int = 10) -> [WalletTransaction] {
        let allTransactions = supportedCoins.flatMap { coinType in
            getTransactionHistory(for: coinType)
        }
        return allTransactions
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }
} 