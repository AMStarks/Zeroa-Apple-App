import Foundation

/// Manages address derivation and rotation for privacy
class AddressManager {
    static let shared = AddressManager()
    private let keychain = KeychainService.shared
    
    // BIP44 path structure: m/44'/coin'/account'/change/index
    // For receiving addresses: change = 0
    // For change addresses: change = 1
    private let coinType: UInt32 = 10117 // Telestai coin type
    
    private struct AddressPath: Hashable {
        let change: UInt32 // 0 receive, 1 change
        let index: UInt32
    }
    
    private var receiveAddressCache: [UInt32: String] = [:]
    private var changeAddressCache: [UInt32: String] = [:]
    private var addressPathCache: [String: AddressPath] = [:]
    private var activeReceivePaths = Set<AddressPath>()
    private var activeChangePaths = Set<AddressPath>()
    private var maxDerivedReceiveIndex: UInt32 = 0
    private var maxDerivedChangeIndex: UInt32 = 0
    
    private init() {
        maxDerivedReceiveIndex = getCurrentReceiveIndex()
        maxDerivedChangeIndex = getCurrentChangeIndex()
    }
    
    /// Get the current receive address index (exposed for external use)
    func getCurrentReceiveIndex() -> UInt32 {
        if let indexStr = keychain.read(key: "address_receive_index"),
           let index = UInt32(indexStr) {
            return index
        }
        return 0 // Start at index 0
    }
    
    /// Get the current change address index (exposed for external use)
    func getCurrentChangeIndex() -> UInt32 {
        if let indexStr = keychain.read(key: "address_change_index"),
           let index = UInt32(indexStr) {
            return index
        }
        return 0 // Start at index 0
    }
    
    /// Save the receive address index
    private func saveReceiveIndex(_ index: UInt32) {
        _ = keychain.save(key: "address_receive_index", value: String(index))
    }
    
    /// Save the change address index
    private func saveChangeIndex(_ index: UInt32) {
        _ = keychain.save(key: "address_change_index", value: String(index))
    }
    
    /// Get the next receive address (for receiving payments)
    /// This implements address rotation for privacy
    func getNextReceiveAddress() -> String? {
        guard let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false) else {
            return WalletService.shared.loadAddress() // Fallback to current address
        }
        
        let currentIndex = getCurrentReceiveIndex()
        let nextIndex = currentIndex + 1
        
        // Derive address at next index
        if let address = deriveAddress(index: nextIndex, change: 0, mnemonic: mnemonic) {
            saveReceiveIndex(nextIndex)
            
            // Import address to RPC wallet so UTXOs are visible
            Task {
                do {
                    try await importAddressToRPC(address)
                    print("✅ AddressManager: Imported address \(address) to RPC wallet")
                } catch {
                    print("⚠️ AddressManager: Failed to import address to RPC: \(error.localizedDescription)")
                }
            }
            
            return address
        }
        
        return WalletService.shared.loadAddress() // Fallback
    }
    
    /// Import address to RPC wallet for UTXO tracking
    private func importAddressToRPC(_ address: String) async throws {
        // Use RPC importaddress method
        let response = try await TLSRPCClient.shared.callRPC(
            method: "importaddress",
            params: [
                AnyCodable(address),
                AnyCodable(""), // Label (empty)
                AnyCodable(false) // Rescan (false = don't rescan, just import)
            ]
        )
        
        if let error = response.error {
            print("⚠️ AddressManager: RPC importaddress error: \(error.message)")
            // Don't throw - address import failure shouldn't block address generation
        }
    }
    
    /// Get the next change address (for change outputs)
    func getNextChangeAddress() -> String? {
        guard let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false) else {
            return WalletService.shared.loadAddress() // Fallback to current address
        }
        
        let currentIndex = getCurrentChangeIndex()
        let nextIndex = currentIndex + 1
        
        // Derive address at next index with change = 1
        if let address = deriveAddress(index: nextIndex, change: 1, mnemonic: mnemonic) {
            saveChangeIndex(nextIndex)
            
            // Import change address to RPC wallet
            Task {
                do {
                    try await importAddressToRPC(address)
                    print("✅ AddressManager: Imported change address \(address) to RPC wallet")
                } catch {
                    print("⚠️ AddressManager: Failed to import change address to RPC: \(error.localizedDescription)")
                }
            }
            
            return address
        }
        
        return WalletService.shared.loadAddress() // Fallback
    }
    
    /// Get the current receive address (don't increment)
    func getCurrentReceiveAddress() -> String? {
        guard let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false) else {
            return WalletService.shared.loadAddress()
        }
        
        let currentIndex = getCurrentReceiveIndex()
        return deriveAddress(index: currentIndex, change: 0, mnemonic: mnemonic) ?? WalletService.shared.loadAddress()
    }
    
    /// Derive address at specific index
    /// - Parameters:
    ///   - index: Address index
    ///   - change: Change value (0 for receive, 1 for change)
    ///   - mnemonic: Mnemonic phrase
    /// - Returns: Derived address
    func deriveAddress(index: UInt32, change: UInt32, mnemonic: String) -> String? {
        // Use WalletService's derivation method
        do {
            let wallet = try WalletService.shared.deriveWalletForPath(mnemonic: mnemonic, account: 0, change: change, index: index)
            let address = wallet.address
            recordDerivedAddress(address, change: change, index: index)
            return address
        } catch {
            print("❌ AddressManager: Failed to derive wallet for path: \(error)")
            return nil
        }
    }
    
    private func recordDerivedAddress(_ address: String?, change: UInt32, index: UInt32) {
        guard let address = address else { return }
        let path = AddressPath(change: change, index: index)
        addressPathCache[address] = path
        if change == 0 {
            receiveAddressCache[index] = address
            maxDerivedReceiveIndex = max(maxDerivedReceiveIndex, index)
        } else {
            changeAddressCache[index] = address
            maxDerivedChangeIndex = max(maxDerivedChangeIndex, index)
        }
    }
    
    private func ensureCacheCovers(change: UInt32, upTo targetIndex: UInt32, mnemonic: String) {
        if change == 0 {
            if targetIndex <= maxDerivedReceiveIndex { return }
            var index = maxDerivedReceiveIndex
            while index <= targetIndex {
                _ = deriveAddress(index: index, change: change, mnemonic: mnemonic)
                if index == targetIndex { break }
                index += 1
            }
        } else {
            if targetIndex <= maxDerivedChangeIndex { return }
            var index = maxDerivedChangeIndex
            while index <= targetIndex {
                _ = deriveAddress(index: index, change: change, mnemonic: mnemonic)
                if index == targetIndex { break }
                index += 1
            }
        }
    }
    
    private func findPath(for address: String, mnemonic: String, maxScanDepth: UInt32 = 4000) -> AddressPath? {
        if let cached = addressPathCache[address] {
            return cached
        }
        
        for change in UInt32(0)...UInt32(1) {
            var index: UInt32 = 0
            while index <= maxScanDepth {
                ensureCacheCovers(change: change, upTo: index, mnemonic: mnemonic)
                if let cached = addressPathCache[address] {
                    return cached
                }
                index += 1
            }
        }
        
        return nil
    }
    
    private func handleDiscovered(path: AddressPath, address: String) {
        if path.change == 0 {
            activeReceivePaths.insert(path)
            if path.index > getCurrentReceiveIndex() {
                saveReceiveIndex(path.index)
            }
        } else {
            activeChangePaths.insert(path)
            if path.index > getCurrentChangeIndex() {
                saveChangeIndex(path.index)
            }
        }
        addressPathCache[address] = path
    }
    
    @discardableResult
    func ensureAddressTracked(_ address: String) -> Bool {
        if addressPathCache[address] != nil {
            return true
        }
        guard let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false) else {
            return false
        }
        if let path = findPath(for: address, mnemonic: mnemonic) {
            handleDiscovered(path: path, address: address)
            return true
        } else {
            print("⚠️ AddressManager: Unable to map address \(address) within scan depth")
            return false
        }
    }
    
    func ingestWalletTransactions(_ transactions: [RPCWalletTransaction]) {
        let addresses = Set(
            transactions
                .compactMap { $0.address?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        
        guard !addresses.isEmpty else { return }
        
        for address in addresses {
            _ = ensureAddressTracked(address)
        }
        
        print("🔍 AddressManager: Ingested \(addresses.count) wallet addresses from RPC")
    }
    
    /// Get all used addresses (for balance checking)
    func getAllUsedAddresses() -> [String] {
        let receive = getUsedReceiveAddressInfos().map { $0.address }
        let change = getUsedChangeAddressInfos().map { $0.address }
        return receive + change
    }
    
    /// Performs BIP44 discovery by deriving paths until gap limit of unused addresses is reached.
    /// - Parameters:
    ///   - gapLimit: Maximum consecutive unused addresses to scan before stopping.
    ///   - activityCheck: Async callback to determine whether an address has activity (balance or txs).
    /// - Returns: True if any activity was discovered.
    func discoverUsedIndices(
        gapLimit: UInt32 = 20,
        scanReceiveOnly: Bool = false,
        activityCheck: @escaping (String) async -> Bool
    ) async -> Bool {
        print("🔍 AddressManager.discoverUsedIndices: Starting (gapLimit=\(gapLimit), receiveOnly=\(scanReceiveOnly))...")
        
        guard let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false) else {
            print("❌ AddressManager.discoverUsedIndices: No mnemonic available")
            return false
        }
        
        async let receiveResult = discoverHighestUsedIndex(
            forChangePath: 0,
            mnemonic: mnemonic,
            gapLimit: gapLimit,
            activityCheck: activityCheck
        )
        
        let recvRes = await receiveResult
        saveReceiveIndex(recvRes.lastUsed)
        
        if scanReceiveOnly {
            print("✅ AddressManager.discoverUsedIndices: Complete (receive-only) - receive=\(recvRes.lastUsed), foundActivity=\(recvRes.foundActivity)")
            return recvRes.foundActivity
        }
        
        let changeResult = await discoverHighestUsedIndex(
            forChangePath: 1,
            mnemonic: mnemonic,
            gapLimit: gapLimit,
            activityCheck: activityCheck
        )
        
        saveChangeIndex(changeResult.lastUsed)
        
        let foundActivity = recvRes.foundActivity || changeResult.foundActivity
        print("✅ AddressManager.discoverUsedIndices: Complete - receive=\(recvRes.lastUsed), change=\(changeResult.lastUsed), foundActivity=\(foundActivity)")
        
        return foundActivity
    }
    
    private func discoverHighestUsedIndex(
        forChangePath change: UInt32,
        mnemonic: String,
        gapLimit: UInt32,
        activityCheck: @escaping (String) async -> Bool
    ) async -> (lastUsed: UInt32, foundActivity: Bool) {
        let pathType = change == 0 ? "receive" : "change"
        print("🔍 AddressManager: Discovering \(pathType) addresses (gapLimit=\(gapLimit))...")
        
        var lastUsed: UInt32 = 0
        var foundActivity = false
        
        // Build candidate addresses up to gap limit
        var candidates: [(UInt32, String)] = []
        for index in 0..<(gapLimit + 10) {
            guard let address = deriveAddress(index: index, change: change, mnemonic: mnemonic) else { break }
            candidates.append((index, address))
        }
        
        print("🔍 AddressManager: Checking \(candidates.count) \(pathType) addresses in parallel...")
        
        // Check all candidates in parallel
        var activeIndices: [UInt32] = []
        await withTaskGroup(of: (UInt32, String, Bool).self) { group in
            for (index, address) in candidates {
                group.addTask {
                    let hasActivity = await activityCheck(address)
                    return (index, address, hasActivity)
                }
            }
            
            for await (index, address, hasActivity) in group {
                if hasActivity {
                    activeIndices.append(index)
                    foundActivity = true
                    print("✅ AddressManager: Found active \(pathType) address at index \(index): \(address)")
                    Task {
                        try? await self.importAddressToRPC(address)
                    }
                }
            }
        }
        
        // Find highest used index
        if let highest = activeIndices.max() {
            lastUsed = highest
        }
        
        print("✅ AddressManager: \(pathType) discovery complete - lastUsed=\(lastUsed), scanned=\(candidates.count), foundActivity=\(foundActivity)")
        return (lastUsed, foundActivity)
    }
    
    #if DEBUG
    /// Trim stored indices down to the highest indices that currently have activity.
    func trimDerivedIndices(activeReceiveAddresses: Set<UInt32>, activeChangeAddresses: Set<UInt32>) {
        let newReceiveIndex = activeReceiveAddresses.max() ?? 0
        let newChangeIndex = activeChangeAddresses.max() ?? 0
        
        let currentReceive = getCurrentReceiveIndex()
        let currentChange = getCurrentChangeIndex()
        
        if newReceiveIndex < currentReceive {
            saveReceiveIndex(newReceiveIndex)
            print("🔧 AddressManager(Debug): Trimmed receive index from \(currentReceive) ➜ \(newReceiveIndex)")
        }
        
        if newChangeIndex < currentChange {
            saveChangeIndex(newChangeIndex)
            print("🔧 AddressManager(Debug): Trimmed change index from \(currentChange) ➜ \(newChangeIndex)")
        }
    }
    
    func debugTrimDerivedIndices(maxReceive: UInt32?, maxChange: UInt32?) {
        let targetReceive = maxReceive ?? 0
        let targetChange = maxChange ?? 0
        
        saveReceiveIndex(targetReceive)
        saveChangeIndex(targetChange)
        print("🔧 AddressManager(Debug): Manually set receive index ➜ \(targetReceive), change index ➜ \(targetChange)")
    }
    #endif
    
    /// Return all derived receive addresses with their derivation index.
    func getUsedReceiveAddressInfos() -> [(index: UInt32, address: String)] {
        if !activeReceivePaths.isEmpty {
            let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false)
            return activeReceivePaths
                .sorted { $0.index < $1.index }
                .compactMap { path in
                    if let cached = receiveAddressCache[path.index] {
                        return (path.index, cached)
                    }
                    guard let mnemonic = mnemonic,
                          let derived = deriveAddress(index: path.index, change: 0, mnemonic: mnemonic) else {
                        return nil
                    }
                    return (path.index, derived)
                }
        }
        
        guard let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false) else {
            return []
        }
        
        let receiveIndex = getCurrentReceiveIndex()
        
        var results: [(UInt32, String)] = []
        for i in 0...receiveIndex {
            if let addr = deriveAddress(index: i, change: 0, mnemonic: mnemonic) {
                results.append((i, addr))
            }
        }
        return results
    }
    
    /// Return all derived change addresses with their derivation index.
    func getUsedChangeAddressInfos() -> [(index: UInt32, address: String)] {
        if !activeChangePaths.isEmpty {
            let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false)
            return activeChangePaths
                .sorted { $0.index < $1.index }
                .compactMap { path in
                    if let cached = changeAddressCache[path.index] {
                        return (path.index, cached)
                    }
                    guard let mnemonic = mnemonic,
                          let derived = deriveAddress(index: path.index, change: 1, mnemonic: mnemonic) else {
                        return nil
                    }
                    return (path.index, derived)
                }
        }
        
        guard let mnemonic = WalletService.shared.loadMnemonic(requireBiometrics: false) else {
            return []
        }
        
        let changeIndex = getCurrentChangeIndex()
        
        var results: [(UInt32, String)] = []
        for i in 0...changeIndex {
            if let addr = deriveAddress(index: i, change: 1, mnemonic: mnemonic) {
                results.append((i, addr))
            }
        }
        return results
    }
    
}


