import Foundation
import Combine
import CryptoKit

// MARK: - Multi-Coin Wallet Service
@MainActor
class MultiCoinWalletService: ObservableObject {
    static let shared = MultiCoinWalletService()
    
    @Published var wallets: [MultiCoinWallet] = []
    @Published var selectedWallet: MultiCoinWallet?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var coinServices: [CoinType: any CoinServiceProtocol] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var balanceCache: [CoinType: WalletBalance] = [:]
    private let balanceCacheTTL: TimeInterval = 15
    
    private init() {
        setupCoinServices()
        loadWallets()
    }
    
    // MARK: - Wallet Management
    func createWallet(name: String, mnemonic: String, completion: @escaping (Bool) -> Void) {
        isLoading = true
        errorMessage = nil
        
        Task {
            var addresses: [String: String] = [:]
            var success = true
            
            // Derive addresses for all supported coins
            for coinType in CoinType.allCases {
                if let service = coinServices[coinType] {
                    let (derived, address) = await service.deriveAddress(from: mnemonic)
                    if derived, let address = address {
                        addresses[coinType.rawValue] = address
                    } else {
                        success = false
                    }
                }
            }
            
            if success {
                let wallet = MultiCoinWallet(
                    name: name,
                    mnemonic: mnemonic,
                    addresses: addresses,
                    createdAt: Date()
                )
                
                wallets.append(wallet)
                selectedWallet = wallet
                saveWallets()
                
                await MainActor.run {
                    self.isLoading = false
                    completion(true)
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to create wallet"
                    completion(false)
                }
            }
        }
    }
    
    func importWallet(from backup: WalletBackup, completion: @escaping (Bool) -> Void) {
        isLoading = true
        errorMessage = nil
        
        // Validate backup
        guard validateBackup(backup) else {
            isLoading = false
            errorMessage = "Invalid wallet backup"
            completion(false)
            return
        }
        
        // Create wallet from backup
        let wallet = MultiCoinWallet(
            name: backup.name,
            mnemonic: backup.mnemonic,
            addresses: backup.addresses,
            createdAt: backup.createdAt
        )
        
        wallets.append(wallet)
        selectedWallet = wallet
        saveWallets()
        
        isLoading = false
        completion(true)
    }
    
    func exportWallet(_ wallet: MultiCoinWallet) -> WalletBackup? {
        return WalletBackup(
            name: wallet.name,
            mnemonic: wallet.mnemonic,
            addresses: wallet.addresses,
            createdAt: wallet.createdAt
        )
    }
    
    func deleteWallet(_ wallet: MultiCoinWallet) {
        if let index = wallets.firstIndex(where: { $0.id == wallet.id }) {
            wallets.remove(at: index)
            
            if selectedWallet?.id == wallet.id {
                selectedWallet = wallets.first
            }
            
            saveWallets()
        }
    }
    
    // MARK: - Balance Management
    func refreshBalances(for wallet: MultiCoinWallet, completion: @escaping ([WalletBalance]) -> Void) {
        Task {
            let entries = wallet.addresses.compactMap { (key, value) -> (CoinType, String)? in
                guard let coinType = CoinType(rawValue: key),
                      coinServices[coinType] != nil else { return nil }
                return (coinType, value)
            }
            
            guard !entries.isEmpty else {
                await MainActor.run { completion([]) }
                return
            }
            
            let now = Date()
            let cachedBalances = entries.compactMap { (coinType, _) -> WalletBalance? in
                if let cached = balanceCache[coinType],
                   now.timeIntervalSince(cached.lastUpdated) < balanceCacheTTL {
                    return cached
                }
                return nil
            }
            
            if !cachedBalances.isEmpty {
                await MainActor.run {
                    completion(cachedBalances.sorted { $0.coinType.rawValue < $1.coinType.rawValue })
                }
            }
            
            var freshBalances: [WalletBalance] = []
            
            await withTaskGroup(of: (CoinType, WalletBalance?).self) { group in
                for (coinType, address) in entries {
                    let service = coinServices[coinType]
                    group.addTask {
                        guard let service = service else { return (coinType, nil) }
                        let balance = await service.getBalance(address: address)
                        return (coinType, balance)
                    }
                }
                
                for await (coinType, balance) in group {
                    if let balance = balance {
                        freshBalances.append(balance)
                        await MainActor.run {
                            self.balanceCache[coinType] = balance
                        }
                    }
                }
            }
            
            if !freshBalances.isEmpty {
                await MainActor.run {
                    completion(freshBalances.sorted { $0.coinType.rawValue < $1.coinType.rawValue })
                }
            }
        }
    }
    
    // MARK: - Send Transaction
    func sendTransaction(
        from wallet: MultiCoinWallet,
        to address: String,
        amount: Double,
        coinType: CoinType,
        priority: SendTransactionRequest.TransactionPriority,
        completion: @escaping (SendTransactionResponse) -> Void
    ) {
        guard let fromAddress = wallet.addresses[coinType.rawValue],
              let service = coinServices[coinType] else {
            completion(SendTransactionResponse(success: false, txid: nil, error: "Invalid wallet or service", fee: nil, confirmations: nil))
            return
        }
        
        let request = SendTransactionRequest(
            fromAddress: fromAddress,
            toAddress: address,
            amount: amount,
            fee: nil,
            priority: priority,
            coinType: coinType
        )
        
        Task {
            let response = await service.sendTransaction(request: request)
            await MainActor.run {
                completion(response)
            }
        }
    }
    
    // MARK: - Transaction History
    func getTransactionHistory(
        for wallet: MultiCoinWallet,
        coinType: CoinType,
        completion: @escaping ([WalletTransaction]) -> Void
    ) {
        guard let address = wallet.addresses[coinType.rawValue],
              let service = coinServices[coinType] else {
            completion([])
            return
        }
        
        Task {
            let transactions = await service.getTransactionHistory(address: address)
            await MainActor.run {
                completion(transactions)
            }
        }
    }
    
    // MARK: - Network Status
    func checkNetworkStatus(completion: @escaping ([CoinType: Bool]) -> Void) {
        Task {
            var status: [CoinType: Bool] = [:]
            
            for coinType in CoinType.allCases {
                if let service = coinServices[coinType] {
                    let isConnected = await service.checkNetworkStatus()
                    status[coinType] = isConnected
                }
            }
            
            await MainActor.run {
                completion(status)
            }
        }
    }
    
    // MARK: - Fee Estimation
    func estimateFee(
        for coinType: CoinType,
        priority: SendTransactionRequest.TransactionPriority,
        completion: @escaping (Double) -> Void
    ) {
        guard let service = coinServices[coinType] else {
            completion(0.0)
            return
        }
        
        Task {
            let fee = await service.estimateFee(priority: priority)
            await MainActor.run {
                completion(fee)
            }
        }
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
    
    // MARK: - Message Signing
    func signMessage(_ message: String, mnemonic: String, coinType: CoinType) -> String? {
        // In a real implementation, this would use proper cryptographic signing
        // For now, we'll return a mock signature
        let data = (message + mnemonic).data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Private Methods
    private func setupCoinServices() {
        coinServices[.telestai] = TelestaiCoinServiceAdapter()
    }
    
    private func loadWallets() {
        if let data = UserDefaults.standard.data(forKey: "MultiCoinWallets"),
           let wallets = try? JSONDecoder().decode([MultiCoinWallet].self, from: data) {
            self.wallets = wallets
            self.selectedWallet = wallets.first
        }
    }
    
    private func saveWallets() {
        if let data = try? JSONEncoder().encode(wallets) {
            UserDefaults.standard.set(data, forKey: "MultiCoinWallets")
        }
    }
    
    private func validateBackup(_ backup: WalletBackup) -> Bool {
        // Basic validation - check if required fields are present
        return !backup.name.isEmpty && !backup.mnemonic.isEmpty && !backup.addresses.isEmpty
    }
    
    // MARK: - Cleanup
    func clear() async {
        for service in coinServices.values {
            await service.clear()
        }
        cancellables.removeAll()
    }
}

// MARK: - Multi-Coin Wallet Model
struct MultiCoinWallet: Codable, Identifiable {
    var id = UUID()
    let name: String
    let mnemonic: String
    let addresses: [String: String] // coinType -> address
    let createdAt: Date
    
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    var totalAddresses: Int {
        return addresses.count
    }
    
    func getAddress(for coinType: CoinType) -> String? {
        return addresses[coinType.rawValue]
    }
}

// MARK: - Wallet Backup Model
struct WalletBackup: Codable {
    let name: String
    let mnemonic: String
    let addresses: [String: String]
    let createdAt: Date
    
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
} 