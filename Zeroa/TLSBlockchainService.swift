import Foundation
import CryptoKit

// MARK: - TLS Blockchain Models
struct TLSAddress: Codable {
    let address: String
    let balance: Double
    let transactions: [TLSTransaction]
}

struct TLSTransaction: Codable {
    let txid: String
    let amount: Double
    let fee: Double
    let confirmations: Int
    let timestamp: Int
    let type: String // "send", "receive", "stake", "message"
    let from: String?
    let to: String?
    let message: String? // Encrypted message data
    let messageType: String? // "text", "payment", "identity", "system", "group"
}

struct TLSPaymentRequest: Codable {
    let fromAddress: String
    let toAddress: String
    let amount: Double
    let fee: Double
    let message: String?
    let messageType: String?
}

struct TLSPaymentResponse: Codable {
    let success: Bool
    let txid: String?
    let error: String?
    let blockHeight: Int?
}

// MARK: - TLS Message Transaction Models (Enhanced)
struct TLSBlockchainMessageTransaction: Codable {
    let txid: String
    let fromAddress: String
    let toAddress: String
    let amount: Double
    let fee: Double
    let message: String
    let messageType: String
    let timestamp: Date
    let blockHeight: Int
    let confirmations: Int
    let signature: String
}

struct TLSBlockchainMessageRequest: Codable {
    let fromAddress: String
    let toAddress: String
    let encryptedMessage: String
    let messageType: String
    let amount: Double
    let fee: Double
    let signature: String
}

actor AddressInfoCacheBox {
    private var storage: [String: (info: TLSAddress, fetchedAt: Date)] = [:]
    private let ttl: TimeInterval
    
    init(ttl: TimeInterval) {
        self.ttl = ttl
    }
    
    func value(for address: String) -> TLSAddress? {
        if let entry = storage[address], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.info
        }
        storage[address] = nil
        return nil
    }
    
    func store(_ info: TLSAddress) {
        storage[info.address] = (info, Date())
    }
}

actor BlockHeightCacheBox {
    private var cached: (height: Int, fetchedAt: Date)?
    private let ttl: TimeInterval
    
    init(ttl: TimeInterval) {
        self.ttl = ttl
    }
    
    func value() -> Int? {
        if let cached = cached, Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.height
        }
        cached = nil
        return nil
    }
    
    func store(_ height: Int) {
        cached = (height, Date())
    }
}

// MARK: - TLS Blockchain Service
class TLSBlockchainService: ObservableObject {
    static let shared = TLSBlockchainService()
    
    private let baseURL = "https://telestai.cryptoscope.io/api"
    private let walletService = WalletService.shared
    
    @Published var isConnected = false
    @Published var currentBalance: Double = 0.0
    @Published var recentTransactions: [TLSTransaction] = []
    @Published var lastBlockHeight: Int = 0
    
    private let addressInfoCache = AddressInfoCacheBox(ttl: 30)
    private let blockHeightCache = BlockHeightCacheBox(ttl: 30)
    private let addressFetchBatchSize = 8
    private let refreshCooldown: TimeInterval = 15
    
    private var lastRefreshDate: Date?
    private var isRefreshingBalance = false
    
    private var hasPerformedAddressDiscovery = false
    private var isDiscoveringAddresses = false
    
    private let addressDiscoveryGapLimit: UInt32 = 5
    
    private var verboseLogsEnabled: Bool {
        ProcessInfo.processInfo.environment["ZEROA_VERBOSE_TLS_LOGS"] == "1"
    }
    
    // MARK: - Network Methods
    func checkConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/stats/") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                isConnected = httpResponse.statusCode == 200
                return isConnected
            }
        } catch {
            print("TLS connection error: \(error)")
        }
        
        isConnected = false
        return false
    }
    
    func getAddressInfo(address: String) async -> TLSAddress? {
        if let cached = await cachedAddressInfo(address: address) {
            return cached
        }
        
        if let explorerInfo = await fetchExplorerAddressInfo(address: address) {
            await cacheAddressInfo(explorerInfo)
            return explorerInfo
        }
        
        if let rpcInfo = await fetchRPCAddressInfo(address: address) {
            await cacheAddressInfo(rpcInfo)
            return rpcInfo
        }
        
        return nil
    }
    
    // MARK: - Enhanced Payment with Message Support
    func sendPayment(toAddress: String, amount: Double, message: String? = nil, messageType: String? = nil) async -> TLSPaymentResponse {
        guard let fromAddress = walletService.loadAddress() else {
            return TLSPaymentResponse(success: false, txid: nil, error: "No wallet address found", blockHeight: nil)
        }
        
        let rpcBaseURL = TLSRPCClient.shared.currentBaseURL()
        print("🔗 TLSBlockchainService: Preparing payment via RPC base URL: \(rpcBaseURL)")
        
        do {
            // Step 1: Get UTXOs from all used addresses (for address rotation support)
            let allAddresses = AddressManager.shared.getAllUsedAddresses()
            let addressesToCheck = allAddresses.isEmpty ? [fromAddress] : allAddresses
            
            // Collect UTXOs from all addresses
            var allUtxos: [UTXO] = []
            for address in addressesToCheck {
                do {
                    let addressUtxos = try await TLSRPCClient.shared.listUnspent(address: address)
                    allUtxos.append(contentsOf: addressUtxos)
                } catch {
                    print("⚠️ TLSBlockchainService: Could not get UTXOs for address \(address): \(error.localizedDescription)")
                    // Continue with other addresses
                }
            }
            
            // Use all collected UTXOs
            let utxos = allUtxos.isEmpty ? (try await TLSRPCClient.shared.listUnspent(address: fromAddress)) : allUtxos
            
            guard !utxos.isEmpty else {
                return TLSPaymentResponse(success: false, txid: nil, error: "No unspent outputs found", blockHeight: nil)
            }
            
            // Check for dust accumulation
            let dustCheck = UTXOSelectionService.shared.checkDustAccumulation(utxos: utxos)
            if dustCheck.hasDust {
                print("⚠️ TLSBlockchainService: Wallet has \(dustCheck.dustCount) dust UTXOs (total: \(dustCheck.dustTotal) TLS)")
            }
            
            // Validate all UTXO amounts are finite and positive
            for utxo in utxos {
                guard utxo.amount.isFinite && utxo.amount >= 0 else {
                    return TLSPaymentResponse(success: false, txid: nil, error: "Invalid UTXO amount: \(utxo.amount)", blockHeight: nil)
                }
            }
            
            // Step 2: Estimate transaction size and fee
            // Initial estimate (will refine after UTXO selection)
            let initialSizeEstimate = FeeEstimationService.shared.estimateTransactionSize(
                inputCount: utxos.count,
                outputCount: 2 // recipient + change (worst case)
            )
            let initialFee = await FeeEstimationService.shared.estimateFee(
                transactionSizeBytes: initialSizeEstimate
            )
            
            // Step 3: Select UTXOs using intelligent algorithm
            let totalNeeded = amount + initialFee
            let (selectedUTXOs, changeAmount) = UTXOSelectionService.shared.selectUTXOs(
                utxos: utxos,
                targetAmount: totalNeeded
            )
            
            guard !selectedUTXOs.isEmpty else {
                return TLSPaymentResponse(success: false, txid: nil, error: "Could not select sufficient UTXOs", blockHeight: nil)
            }
            
            let selectedTotal = selectedUTXOs.reduce(0.0) { $0 + $1.amount }
            
            // Recalculate fee with actual selected UTXOs
            let actualSize = FeeEstimationService.shared.estimateTransactionSize(
                inputCount: selectedUTXOs.count,
                outputCount: changeAmount > 0.00001 ? 2 : 1 // recipient + change if needed
            )
            let fee = await FeeEstimationService.shared.estimateFee(
                transactionSizeBytes: actualSize
            )
            
            // Recalculate with actual fee
            let finalTotalNeeded = amount + fee
            guard selectedTotal >= finalTotalNeeded else {
                return TLSPaymentResponse(success: false, txid: nil, error: "Insufficient balance. Available: \(selectedTotal), Needed: \(finalTotalNeeded)", blockHeight: nil)
            }
            
            // Step 4: Build transaction inputs and outputs
            let inputs: [[String: AnyCodable]] = selectedUTXOs.map { utxo in
                [
                    "txid": AnyCodable(utxo.txid),
                    "vout": AnyCodable(utxo.vout)
                ]
            }
            
            // Ensure amounts are valid numbers (not NaN or infinity)
            guard amount.isFinite && amount > 0 else {
                return TLSPaymentResponse(success: false, txid: nil, error: "Invalid amount: \(amount)", blockHeight: nil)
            }
            
            var outputs: [String: AnyCodable] = [
                toAddress: AnyCodable(amount)
            ]
            
            // Add change output if needed (use change address for privacy)
            let finalChange = selectedTotal - finalTotalNeeded
            guard finalChange.isFinite else {
                return TLSPaymentResponse(success: false, txid: nil, error: "Invalid change calculation: \(finalChange)", blockHeight: nil)
            }
            
            if !UTXOSelectionService.shared.isDust(finalChange) {
                let reusePrimaryForChange = UserDefaults.standard.bool(forKey: "zeroa_reuse_primary_change")
                
                if reusePrimaryForChange {
                    let existingAmount = (outputs[fromAddress]?.value as? Double) ?? 0.0
                    outputs[fromAddress] = AnyCodable(existingAmount + finalChange)
                    print("⚙️ TLSBlockchainService: Reusing primary address for change output (\(fromAddress.prefix(8))...)")
                } else if let changeAddress = AddressManager.shared.getNextChangeAddress() {
                    outputs[changeAddress] = AnyCodable(finalChange)
                } else {
                    // Fallback to from address if change address unavailable
                    let existingAmount = (outputs[fromAddress]?.value as? Double) ?? 0.0
                    outputs[fromAddress] = AnyCodable(existingAmount + finalChange)
                }
            } else if finalChange > 0 {
                // Dust change - add to fee (don't create dust output)
                print("⚠️ TLSBlockchainService: Change amount \(finalChange) is dust, adding to fee")
            }
            
            // Step 5: Create raw transaction
            let rawHex = try await TLSRPCClient.shared.createRawTransaction(inputs: inputs, outputs: outputs)
            
            // Log the raw transaction and outputs for debugging
            print("🔍 TLSBlockchainService: Raw transaction created:")
            print("   Raw hex (first 200 chars): \(rawHex.prefix(200))...")
            print("   Raw hex length: \(rawHex.count) chars = \(rawHex.count / 2) bytes")
            print("   Outputs sent to createrawtransaction:")
            for (address, amountCodable) in outputs {
                if let amount = amountCodable.value as? Double {
                    print("     \(address): \(amount) TLS (\(UInt64(amount * 100_000_000)) satoshis)")
                }
            }
            
            // Step 6: Sign transaction CLIENT-SIDE via RPC (more secure than server endpoint)
            // CRITICAL: Derive private keys for ALL addresses that have UTXOs in this transaction
            // This is necessary when UTXOs come from multiple addresses (address rotation)
            guard let mnemonic = walletService.loadMnemonic(requireBiometrics: false) else {
                return TLSPaymentResponse(success: false, txid: nil, error: "Mnemonic not found", blockHeight: nil)
            }
            
            // Get unique addresses from selected UTXOs
            let uniqueAddresses = Set(selectedUTXOs.map { $0.address })
            
            // Derive private keys for each address
            var privateKeys: [String] = []
            for address in uniqueAddresses {
                do {
                    // First get the private key Data to verify it matches the address
                    let privKeyData = try derivePrivateKeyDataForAddress(address: address, mnemonic: mnemonic)
                    
                    // Verify the private key matches the address by deriving the address from it
                    let signingKey = try Secp.Signing.PrivateKey(dataRepresentation: privKeyData)
                    let derivedAddress = WalletService.deriveAddress(from: signingKey)
                    
                    if derivedAddress != address {
                        print("❌ TLSBlockchainService: CRITICAL - Private key does not match address!")
                        print("   Expected address: \(address)")
                        print("   Derived address:  \(derivedAddress)")
                        print("   This means the private key derivation is incorrect!")
                        throw NSError(domain: "TLSBlockchain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Private key does not match address \(address)"])
                    }
                    
                    // Convert to WIF
                    let privKeyWIF = privateKeyToWIF(privateKey: privKeyData)
                    privateKeys.append(privKeyWIF)
                    print("✅ TLSBlockchainService: Derived private key (WIF) for address \(address.prefix(8))... (WIF length: \(privKeyWIF.count), address verified)")
                } catch {
                    print("⚠️ TLSBlockchainService: Could not derive private key for address \(address): \(error.localizedDescription), trying primary key as fallback")
                    // Fallback: try to use primary key (convert hex to WIF)
                    if let primaryAddress = walletService.loadAddress(),
                       primaryAddress == address,
                       let primaryKeyHex = walletService.keychain.read(key: "wallet_private_key"),
                       primaryKeyHex.count == 64,
                       let keyData = Data(hexString: primaryKeyHex) {
                        let primaryKeyWIF = privateKeyToWIF(privateKey: keyData)
                        if !privateKeys.contains(primaryKeyWIF) {
                            privateKeys.append(primaryKeyWIF)
                            print("✅ TLSBlockchainService: Using primary key (converted to WIF) as fallback")
                        }
                    } else {
                        print("❌ TLSBlockchainService: Could not use primary key fallback - address mismatch or invalid key format")
                    }
                }
            }
            
            guard !privateKeys.isEmpty else {
                return TLSPaymentResponse(success: false, txid: nil, error: "Could not derive private keys for transaction", blockHeight: nil)
            }
            
            print("✅ TLSBlockchainService: Using \(privateKeys.count) private key(s) for signing (addresses: \(uniqueAddresses.count))")
            
            // Log UTXO details for debugging
            for utxo in selectedUTXOs {
                print("🔍 TLSBlockchainService: UTXO \(utxo.txid):\(utxo.vout) - address: \(utxo.address.prefix(8))..., amount: \(utxo.amount), scriptPubKey: \(utxo.scriptPubKey.isEmpty ? "EMPTY" : "\(utxo.scriptPubKey.prefix(20))...")")
            }
            
            // Build prevTxs array with scriptPubKey and amount (required for proper signing)
            // RPC needs this information to correctly sign the transaction inputs
            // CRITICAL: Validate scriptPubKey matches our derived public key hash
            var prevTxs: [[String: AnyCodable]] = []
            var addressToPrivateKeyMap: [String: Data] = [:]
            
            // Build map of address to private key for validation
            for address in uniqueAddresses {
                do {
                    let privKeyData = try derivePrivateKeyDataForAddress(address: address, mnemonic: mnemonic)
                    addressToPrivateKeyMap[address] = privKeyData
                } catch {
                    print("⚠️ TLSBlockchainService: Could not derive private key for validation: \(error.localizedDescription)")
                }
            }
            
            for utxo in selectedUTXOs {
                var scriptPubKeyHex = utxo.scriptPubKey
                
                // Validate scriptPubKey is not empty (required by RPC)
                if scriptPubKeyHex.isEmpty {
                    print("⚠️ TLSBlockchainService: UTXO \(utxo.txid):\(utxo.vout) has empty scriptPubKey, fetching from RPC...")
                    do {
                        let txResponse = try await TLSRPCClient.shared.callRPC(method: "getrawtransaction", params: [AnyCodable(utxo.txid), AnyCodable(true)])
                        if let txResult = txResponse.result,
                           let txDict = txResult.value as? [String: Any],
                           let vouts = txDict["vout"] as? [[String: Any]],
                           utxo.vout < vouts.count,
                           let vout = vouts[utxo.vout] as? [String: Any],
                           let scriptPubKey = vout["scriptPubKey"] as? [String: Any],
                           let hex = scriptPubKey["hex"] as? String {
                            scriptPubKeyHex = hex
                            print("✅ TLSBlockchainService: Fetched scriptPubKey for UTXO \(utxo.txid):\(utxo.vout): \(hex.prefix(20))...")
                        } else {
                            print("❌ TLSBlockchainService: Could not extract scriptPubKey from transaction \(utxo.txid)")
                            continue // Skip this UTXO if we can't get scriptPubKey
                        }
                    } catch {
                        print("❌ TLSBlockchainService: Failed to fetch scriptPubKey for UTXO \(utxo.txid):\(utxo.vout): \(error.localizedDescription)")
                        continue // Skip this UTXO
                    }
                }
                
                // Validate scriptPubKey format and match with our public key hash
                if let privKeyData = addressToPrivateKeyMap[utxo.address] {
                    do {
                        let validationResult = try validateScriptPubKeyMatchesPrivateKey(
                            scriptPubKeyHex: scriptPubKeyHex,
                            privateKeyData: privKeyData,
                            address: utxo.address
                        )
                        
                        if !validationResult.matches {
                            print("⚠️ TLSBlockchainService: scriptPubKey hash mismatch for address \(utxo.address.prefix(8))...")
                            print("   scriptPubKey hash (from script): \(validationResult.scriptHashHex)")
                            print("   Derived hash (compressed): \(validationResult.derivedHashCompressedHex)")
                            print("   Derived hash (uncompressed): \(validationResult.derivedHashUncompressedHex)")
                            print("   This may cause signing to fail - will try both compression formats")
                        } else {
                            print("✅ TLSBlockchainService: scriptPubKey hash matches for address \(utxo.address.prefix(8))... (format: \(validationResult.matchedFormat))")
                        }
                    } catch {
                        print("⚠️ TLSBlockchainService: Could not validate scriptPubKey: \(error.localizedDescription)")
                    }
                }
                
                prevTxs.append([
                    "txid": AnyCodable(utxo.txid),
                    "vout": AnyCodable(utxo.vout),
                    "scriptPubKey": AnyCodable(scriptPubKeyHex),
                    "amount": AnyCodable(utxo.amount)
                ])
            }
            
            if prevTxs.count < selectedUTXOs.count {
                print("⚠️ TLSBlockchainService: Only \(prevTxs.count) of \(selectedUTXOs.count) UTXOs have scriptPubKey, RPC will need to fetch the rest")
            }
            
            print("✅ TLSBlockchainService: Providing \(prevTxs.count) prevTx outputs with scriptPubKey and amount for signing")
            
            // Log what we're sending to RPC for debugging
            print("🔍 TLSBlockchainService: Sending to RPC - privateKeys count: \(privateKeys.count), prevTxs count: \(prevTxs.count)")
            for (index, key) in privateKeys.enumerated() {
                print("🔍 TLSBlockchainService: Private key \(index + 1) (WIF) - first 10 chars: \(key.prefix(10))..., length: \(key.count), starts with: '\(key.prefix(1))'")
            }
            
            // Log prevTxs details
            for (index, prevTx) in prevTxs.enumerated() {
                if let txid = prevTx["txid"]?.value as? String,
                   let vout = prevTx["vout"]?.value as? Int,
                   let scriptPubKey = prevTx["scriptPubKey"]?.value as? String,
                   let amount = prevTx["amount"]?.value as? Double {
                    print("🔍 TLSBlockchainService: prevTx[\(index)] - txid: \(txid.prefix(16))..., vout: \(vout), scriptPubKey: \(scriptPubKey.prefix(20))..., amount: \(amount)")
                }
            }
            
            // CLIENT-SIDE SIGNING: Sign transaction locally (like Core wallet)
            // This bypasses RPC signing issues and is more secure (keys never leave device)
            print("🔧 TLSBlockchainService: Signing transaction CLIENT-SIDE (Core wallet style)...")
            
            // Prepare inputs for client-side signer
            var signerInputs: [ClientSideTransactionSigner.TransactionInput] = []
            var signerPrivateKeys: [Data] = []
            
            for (index, utxo) in selectedUTXOs.enumerated() {
                // Find the private key for this UTXO's address
                var privKeyData: Data?
                for address in uniqueAddresses {
                    if address == utxo.address {
                        do {
                            privKeyData = try derivePrivateKeyDataForAddress(address: address, mnemonic: mnemonic)
                            break
                        } catch {
                            print("⚠️ TLSBlockchainService: Could not derive key for \(address.prefix(8))...: \(error.localizedDescription)")
                        }
                    }
                }
                
                guard let keyData = privKeyData else {
                    return TLSPaymentResponse(success: false, txid: nil, error: "Could not derive private key for UTXO \(utxo.txid):\(utxo.vout)", blockHeight: nil)
                }
                
                // Get scriptPubKey (fetch if empty)
                var scriptPubKeyHex = utxo.scriptPubKey
                if scriptPubKeyHex.isEmpty {
                    print("⚠️ TLSBlockchainService: UTXO \(utxo.txid):\(utxo.vout) has empty scriptPubKey, fetching from RPC...")
                    do {
                        let txResponse = try await TLSRPCClient.shared.callRPC(method: "getrawtransaction", params: [AnyCodable(utxo.txid), AnyCodable(true)])
                        if let txResult = txResponse.result,
                           let txDict = txResult.value as? [String: Any],
                           let vouts = txDict["vout"] as? [[String: Any]],
                           utxo.vout < vouts.count,
                           let vout = vouts[utxo.vout] as? [String: Any],
                           let scriptPubKey = vout["scriptPubKey"] as? [String: Any],
                           let hex = scriptPubKey["hex"] as? String {
                            scriptPubKeyHex = hex
                            print("✅ TLSBlockchainService: Fetched scriptPubKey for UTXO \(utxo.txid):\(utxo.vout)")
                        } else {
                            return TLSPaymentResponse(success: false, txid: nil, error: "Could not fetch scriptPubKey for UTXO \(utxo.txid):\(utxo.vout)", blockHeight: nil)
                        }
                    } catch {
                        return TLSPaymentResponse(success: false, txid: nil, error: "Failed to fetch scriptPubKey: \(error.localizedDescription)", blockHeight: nil)
                    }
                }
                
                signerInputs.append(ClientSideTransactionSigner.TransactionInput(
                    txid: utxo.txid,
                    vout: utxo.vout,
                    scriptPubKey: scriptPubKeyHex,
                    amount: utxo.amount
                ))
                signerPrivateKeys.append(keyData)
            }
            
            // DEBUG: Verify UTXO scriptPubKey directly from RPC before signing
            for input in signerInputs {
                print("🔬 DEBUG: Verifying UTXO \(input.txid):\(input.vout) scriptPubKey from RPC...")
                do {
                    let txResponse = try await TLSRPCClient.shared.callRPC(method: "getrawtransaction", params: [AnyCodable(input.txid), AnyCodable(true)])
                    if let txResult = txResponse.result?.value as? [String: Any],
                       let vouts = txResult["vout"] as? [[String: Any]],
                       input.vout < vouts.count,
                       let vout = vouts[input.vout] as? [String: Any],
                       let scriptPubKey = vout["scriptPubKey"] as? [String: Any] {
                        if let hex = scriptPubKey["hex"] as? String {
                            print("   RPC scriptPubKey.hex: \(hex)")
                            print("   Our scriptPubKey:     \(input.scriptPubKey)")
                            print("   Match: \(hex == input.scriptPubKey ? "✅ YES" : "❌ NO")")
                        }
                        if let asm = scriptPubKey["asm"] as? String {
                            print("   RPC scriptPubKey.asm: \(asm)")
                        }
                        if let addresses = scriptPubKey["addresses"] as? [String] {
                            print("   RPC addresses: \(addresses)")
                        }
                    }
                } catch {
                    print("   ⚠️ Could not verify: \(error.localizedDescription)")
                }
            }
            
            // Sign transaction client-side
            let signedHex: String
            do {
                signedHex = try ClientSideTransactionSigner.shared.signTransaction(
                    rawHex: rawHex,
                    inputs: signerInputs,
                    privateKeys: signerPrivateKeys,
                    sighashType: 0x01 // SIGHASH_ALL (Telestai expects legacy hash type)
                )
                print("✅ TLSBlockchainService: Transaction signed successfully (client-side)")
            } catch {
                let errorMsg = "Client-side signing failed: \(error.localizedDescription)"
                print("❌ TLSBlockchainService: \(errorMsg)")
                return TLSPaymentResponse(success: false, txid: nil, error: errorMsg, blockHeight: nil)
            }
            
            // DEBUG: Decode the signed transaction to see what daemon thinks
            do {
                let decodeResponse = try await TLSRPCClient.shared.callRPC(method: "decoderawtransaction", params: [AnyCodable(signedHex)])
                if let decodedTx = decodeResponse.result?.value as? [String: Any] {
                    print("🔬 DEBUG: Decoded signed transaction:")
                    if let txid = decodedTx["txid"] as? String {
                        print("   txid: \(txid)")
                    }
                    if let vin = decodedTx["vin"] as? [[String: Any]], !vin.isEmpty {
                        for (i, input) in vin.enumerated() {
                            print("   vin[\(i)]:")
                            if let inputTxid = input["txid"] as? String {
                                print("      txid: \(inputTxid)")
                            }
                            if let vout = input["vout"] as? Int {
                                print("      vout: \(vout)")
                            }
                            if let scriptSig = input["scriptSig"] as? [String: Any] {
                                if let asm = scriptSig["asm"] as? String {
                                    print("      scriptSig.asm: \(asm)")
                                }
                                if let hex = scriptSig["hex"] as? String {
                                    print("      scriptSig.hex: \(hex)")
                                }
                            }
                        }
                    }
                    if let vout = decodedTx["vout"] as? [[String: Any]], !vout.isEmpty {
                        for (i, output) in vout.enumerated() {
                            print("   vout[\(i)]:")
                            if let value = output["value"] as? Double {
                                print("      value: \(value)")
                            }
                            if let scriptPubKey = output["scriptPubKey"] as? [String: Any] {
                                if let asm = scriptPubKey["asm"] as? String {
                                    print("      scriptPubKey.asm: \(asm)")
                                }
                                if let addresses = scriptPubKey["addresses"] as? [String] {
                                    print("      addresses: \(addresses)")
                                }
                            }
                        }
                    }
                }
            } catch {
                print("⚠️ DEBUG: Could not decode signed transaction: \(error.localizedDescription)")
            }
            
            // Also test the transaction with testmempoolaccept if available
            do {
                let testResponse = try await TLSRPCClient.shared.callRPC(method: "testmempoolaccept", params: [AnyCodable([signedHex])])
                if let testResults = testResponse.result?.value as? [[String: Any]], let testResult = testResults.first {
                    print("🔬 DEBUG: testmempoolaccept result:")
                    if let allowed = testResult["allowed"] as? Bool {
                        print("   allowed: \(allowed)")
                    }
                    if let rejectReason = testResult["reject-reason"] as? String {
                        print("   reject-reason: \(rejectReason)")
                    }
                }
            } catch {
                print("⚠️ DEBUG: testmempoolaccept not available or failed: \(error.localizedDescription)")
            }
            
            // Step 7: Broadcast transaction (with retry logic)
            let txid = try await broadcastTransactionWithRetry(hex: signedHex)
            
            // Step 8: Get current block height
            let blockHeight = try await TLSRPCClient.shared.getBlockCount()
            
            // Create transaction record
            let transaction = TLSTransaction(
                txid: txid,
                amount: amount,
                fee: fee,
                confirmations: 0,
                timestamp: Int(Date().timeIntervalSince1970),
                type: message != nil ? "message" : "send",
                from: fromAddress,
                to: toAddress,
                message: message,
                messageType: messageType
            )
            
            // Add to recent transactions
            await MainActor.run {
                self.recentTransactions.insert(transaction, at: 0)
                self.lastBlockHeight = blockHeight
            }
            
            print("✅ TLSBlockchainService: Payment sent successfully, txid: \(txid)")
            
             // Refresh aggregated balance to include new change outputs
            Task {
                await self.refreshAggregatedBalance()
            }
            
            return TLSPaymentResponse(
                success: true,
                txid: txid,
                error: nil,
                blockHeight: blockHeight
            )
            
        } catch {
            let errorMessage: String
            if let nsError = error as NSError? {
                errorMessage = nsError.localizedDescription
                print("❌ TLSBlockchainService: Payment failed: \(errorMessage) (domain: \(nsError.domain), code: \(nsError.code))")
            } else {
                errorMessage = error.localizedDescription
                print("❌ TLSBlockchainService: Payment failed: \(errorMessage)")
            }
            return TLSPaymentResponse(
                success: false,
                txid: nil,
                error: errorMessage,
                blockHeight: nil
            )
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Derive private key Data for a specific address (helper for WIF version byte retry)
    private func derivePrivateKeyDataForAddress(address: String, mnemonic: String) throws -> Data {
        // Try to find the address in all used addresses and derive its key
        let allAddresses = AddressManager.shared.getAllUsedAddresses()
        
        var privateKeyData: Data?
        
        // Check if this is the primary address (stored in keychain)
        // Note: The keychain stores the key as hex, we need to convert to Data
        if let primaryAddress = walletService.loadAddress(), primaryAddress == address {
            if let primaryKeyHex = walletService.keychain.read(key: "wallet_private_key") {
                // Check if it's already WIF (starts with base58 characters) or hex
                if primaryKeyHex.count == 64 && primaryKeyHex.allSatisfy({ $0.isHexDigit }) {
                    // It's hex, convert to Data
                    if let keyData = Data(hexString: primaryKeyHex) {
                        privateKeyData = keyData
                    }
                } else {
                    // It might already be WIF, but we need Data for consistency
                    // For now, try to derive from mnemonic instead
                    print("⚠️ TLSBlockchainService: Primary key appears to be in WIF format, deriving from mnemonic instead")
                }
            }
        }
        
        // If not primary, try to find address by checking all used indices
        if privateKeyData == nil {
            let receiveIndex = AddressManager.shared.getCurrentReceiveIndex()
            let changeIndex = AddressManager.shared.getCurrentChangeIndex()
            
            // Check receive addresses (change = 0)
            for i in 0...receiveIndex {
                if let wallet = try? walletService.deriveWalletForPath(mnemonic: mnemonic, account: 0, change: 0, index: i),
                   wallet.address == address {
                    privateKeyData = wallet.privateKey
                    break
                }
            }
            
            // Check change addresses (change = 1)
            if privateKeyData == nil {
                for i in 0...changeIndex {
                    if let wallet = try? walletService.deriveWalletForPath(mnemonic: mnemonic, account: 0, change: 1, index: i),
                       wallet.address == address {
                        privateKeyData = wallet.privateKey
                        break
                    }
                }
            }
        }
        
        guard let keyData = privateKeyData else {
            throw NSError(domain: "TLSBlockchain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find derivation path for address \(address)"])
        }
        
        return keyData
    }
    
    /// Sum balances across every derived receive/change address so the UI always shows the true total.
    private func refreshAggregatedBalance() async {
        var addressSet = Set(AddressManager.shared.getAllUsedAddresses())
        if let primary = walletService.loadAddress() {
            addressSet.insert(primary)
        }
        guard !addressSet.isEmpty else { return }
        
        let receiveInfos = AddressManager.shared.getUsedReceiveAddressInfos()
        let changeInfos = AddressManager.shared.getUsedChangeAddressInfos()
        var addressMetadata: [String: (isChange: Bool, index: UInt32)] = [:]
        for info in receiveInfos {
            addressMetadata[info.address] = (false, info.index)
        }
        for info in changeInfos {
            addressMetadata[info.address] = (true, info.index)
        }
        if let primary = walletService.loadAddress(), addressMetadata[primary] == nil {
            addressMetadata[primary] = (false, 0)
        }
        
        var aggregatedTotal: Double = 0
        var perAddressTotals: [String: Double] = [:]
        var activeReceiveIndices = Set<UInt32>()
        var activeChangeIndices = Set<UInt32>()
        
        await withTaskGroup(of: (String, Double)?.self) { group in
            for address in addressSet {
                group.addTask {
                    do {
                        let utxos = try await TLSRPCClient.shared.listUnspent(address: address)
                        let addressTotal = utxos.reduce(0.0) { $0 + $1.amount }
                        return (address, addressTotal)
                    } catch {
                        print("⚠️ TLSBlockchainService: Could not fetch UTXOs for \(address): \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            for await result in group {
                guard let (address, total) = result else { continue }
                perAddressTotals[address] = total
                aggregatedTotal += total
                if verboseLogsEnabled {
                    print("🔍 TLSBlockchainService: Aggregated \(total) TLS from \(address)")
                }
                if total > 0, let meta = addressMetadata[address] {
                    if meta.isChange {
                        activeChangeIndices.insert(meta.index)
                    } else {
                        activeReceiveIndices.insert(meta.index)
                    }
                }
            }
        }
        
        let finalAggregated = aggregatedTotal
        await MainActor.run {
            self.currentBalance = finalAggregated
        }
        print("✅ TLSBlockchainService: Aggregated wallet balance across \(addressSet.count) addresses: \(finalAggregated) TLS")
        
        #if DEBUG
        AddressManager.shared.trimDerivedIndices(
            activeReceiveAddresses: activeReceiveIndices,
            activeChangeAddresses: activeChangeIndices
        )
        #endif
    }
    
    private func shouldSuppressExplorerError(address: String, body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        let lowered = trimmed.lowercased()
        if lowered.contains("error: address not found") {
            if verboseLogsEnabled {
                print("ℹ️ TLSBlockchainService: Explorer has no record for \(address); treating as unused.")
            }
            return true
        }
        
        guard let firstChar = trimmed.first else { return true }
        let isJSON = firstChar == "{" || firstChar == "["
        if !isJSON {
            if verboseLogsEnabled {
                let snippet = trimmed.count > 160 ? "\(trimmed.prefix(160))…" : trimmed
                print("ℹ️ TLSBlockchainService: Explorer response for \(address) was not JSON: \(snippet)")
            }
            return true
        }
        
        return false
    }
    
    private func fetchExplorerAddressInfo(address: String) async -> TLSAddress? {
        struct TxItem: Decodable {
            let tx_time: Int
            let block_ix: Int
            let txid: String
            let amount: String
            let is_reward: Bool
        }
        struct AddressResp: Decodable {
            let timestamp: Int64
            let address: String
            let balance: String
            let received: String?
            let sent: String?
            let groupid: String?
            let last_txs: [TxItem]?
        }
        
        guard let url = URL(string: "\(baseURL)/getaddress/?address=\(address)") else {
            print("❌ TLSBlockchainService: Invalid URL for address: \(address)")
            return nil
        }
        
        var responseBody: String?
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            responseBody = String(data: data, encoding: .utf8)
            
            guard let http = response as? HTTPURLResponse else {
                print("❌ TLSBlockchainService: Invalid HTTP response when fetching \(address)")
                return nil
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("❌ TLSBlockchainService: Explorer HTTP \(http.statusCode) for \(address): \(body.prefix(200))")
                return nil
            }
            
            if let body = responseBody,
               shouldSuppressExplorerError(address: address, body: body) {
                return nil
            }
            
            let resp = try JSONDecoder().decode(AddressResp.self, from: data)
            let bal = Double(resp.balance) ?? 0.0
            let currentHeight = await currentBlockHeight()
            let txs: [TLSTransaction] = (resp.last_txs ?? []).map { t in
                let amountValue = Double(t.amount) ?? 0.0
                let derivedType: String
                if amountValue < 0 {
                    derivedType = "send"
                } else if t.is_reward {
                    derivedType = "reward"
                } else {
                    derivedType = "receive"
                }
                let confirmations: Int
                if let height = currentHeight, t.block_ix > 0 {
                    confirmations = max(0, height - t.block_ix + 1)
                } else {
                    confirmations = 0
                }
                
                return TLSTransaction(
                    txid: t.txid,
                    amount: amountValue,
                    fee: 0.0,
                    confirmations: confirmations,
                    timestamp: t.tx_time,
                    type: derivedType,
                    from: derivedType == "send" ? address : nil,
                    to: derivedType == "send" ? nil : address,
                    message: nil,
                    messageType: nil
                )
            }
            
            return TLSAddress(address: resp.address, balance: bal, transactions: txs)
        } catch {
            if let body = responseBody,
               shouldSuppressExplorerError(address: address, body: body) {
                return nil
            } else {
                print("❌ TLSBlockchainService: Error fetching address info for \(address): \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    private func fetchRPCAddressInfo(address: String) async -> TLSAddress? {
        do {
            let rpcTransactions = try await TLSRPCClient.shared.listTransactions()
            if rpcTransactions.isEmpty {
                return nil
            }
            
            let relevant = rpcTransactions.filter {
                guard let txAddress = $0.address else { return false }
                return txAddress == address
            }
            
            if relevant.isEmpty {
                return nil
            }
            
            let txs: [TLSTransaction] = relevant.compactMap { record in
                let category = record.category.lowercased()
                if category == "send", record.involvesWatchonly ?? false {
                    return nil
                }
                let timestamp = record.blocktime ?? record.time ?? Int(Date().timeIntervalSince1970)
                let confirmations = record.confirmations ?? 0
                let feeValue = abs(record.fee ?? 0.0)
                let type: String
                switch category {
                case "send":
                    type = "send"
                case "immature":
                    type = "reward"
                default:
                    type = "receive"
                }
                return TLSTransaction(
                    txid: record.txid,
                    amount: record.amount,
                    fee: feeValue,
                    confirmations: confirmations,
                    timestamp: timestamp,
                    type: type,
                    from: type == "send" ? address : record.address,
                    to: type == "send" ? (record.address ?? "external") : address,
                    message: nil,
                    messageType: nil
                )
            }
            
            let utxos = try? await TLSRPCClient.shared.listUnspent(address: address)
            let balance = utxos?.reduce(0.0) { $0 + $1.amount } ?? 0.0
            return TLSAddress(address: address, balance: balance, transactions: txs)
        } catch {
            print("❌ TLSBlockchainService: RPC fallback failed for \(address): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func cachedAddressInfo(address: String) async -> TLSAddress? {
        await addressInfoCache.value(for: address)
    }
    
    private func cacheAddressInfo(_ info: TLSAddress) async {
        await addressInfoCache.store(info)
    }
    
    private func currentBlockHeight() async -> Int? {
        if let cached = await blockHeightCache.value() {
            return cached
        }
        
        do {
            let height = try await TLSRPCClient.shared.getBlockCount()
            await blockHeightCache.store(height)
            return height
        } catch {
            print("⚠️ TLSBlockchainService: Could not fetch block height: \(error.localizedDescription)")
            return nil
        }
    }
    
#if DEBUG
    private var shouldTrimDerivedPaths: Bool {
        ProcessInfo.processInfo.environment["ZEROA_TRIM_DERIVED_PATHS"] == "1"
    }
    
    private func trimDerivedPathsIfNeeded(receiveIndex: UInt32?, changeIndex: UInt32?) {
        guard shouldTrimDerivedPaths else { return }
        AddressManager.shared.debugTrimDerivedIndices(maxReceive: receiveIndex, maxChange: changeIndex)
    }
#else
    private func trimDerivedPathsIfNeeded(receiveIndex: UInt32?, changeIndex: UInt32?) { }
#endif

    private func aggregateTransactions(_ transactions: [TLSTransaction]) -> [TLSTransaction] {
        var buckets: [String: AggregatedTransactionState] = [:]
        
        for tx in transactions {
            var state = buckets[tx.txid] ?? AggregatedTransactionState(txid: tx.txid)
            if tx.fee != 0 {
                state.fee = tx.fee
            }
            state.confirmations = max(state.confirmations, tx.confirmations)
            state.timestamp = max(state.timestamp, tx.timestamp)
            if state.message == nil {
                state.message = tx.message
            }
            if state.messageType == nil {
                state.messageType = tx.messageType
            }
            
            let lowerType = tx.type.lowercased()
            state.lastType = lowerType
            
            if lowerType == "send" {
                state.sawSend = true
                state.sendAmount = max(state.sendAmount, abs(tx.amount))
                if state.sendAddress == nil {
                    state.sendAddress = tx.from ?? tx.to
                }
            } else {
                state.sawReceive = true
                if tx.amount > 0 {
                    state.receiveAmount += tx.amount
                }
                if state.receiveAddress == nil {
                    state.receiveAddress = tx.to ?? tx.from
                }
            }
            
            buckets[tx.txid] = state
        }
        
        return buckets.values.map { state in
            let derivedType: String
            let amount: Double
            
            if state.sawSend {
                let changePortion = min(state.sendAmount, state.receiveAmount)
                let netSend = state.sendAmount - changePortion
                
                if netSend > 0 {
                    derivedType = "send"
                    amount = -netSend
                } else if state.sawReceive {
                    derivedType = "receive"
                    amount = state.receiveAmount
                } else {
                    derivedType = state.lastType
                    amount = -state.sendAmount
                }
            } else if state.sawReceive {
                derivedType = "receive"
                amount = state.receiveAmount
            } else {
                derivedType = state.lastType
                amount = state.lastType == "send" ? -abs(state.sendAmount) : state.receiveAmount
            }
            
            let fromAddress: String?
            let toAddress: String?
            if derivedType == "send" {
                fromAddress = state.sendAddress ?? state.receiveAddress
                toAddress = state.receiveAddress
            } else {
                fromAddress = state.sendAddress
                toAddress = state.receiveAddress ?? state.sendAddress
            }
            
            return TLSTransaction(
                txid: state.txid,
                amount: amount,
                fee: state.fee,
                confirmations: state.confirmations,
                timestamp: state.timestamp,
                type: derivedType,
                from: fromAddress,
                to: toAddress,
                message: state.message,
                messageType: state.messageType
            )
        }
    }
    
    private func fetchAddressUTXOBalance(address: String) async -> Double {
        do {
            let utxos = try await TLSRPCClient.shared.listUnspent(address: address)
            return utxos.reduce(0.0) { $0 + $1.amount }
        } catch {
            print("⚠️ TLSBlockchainService: Could not fetch UTXOs for \(address): \(error.localizedDescription)")
            return 0.0
        }
    }
    
    /// Derive private key for a specific address (needed when UTXOs come from multiple addresses)
    /// Returns the private key in WIF (Wallet Import Format) - base58-encoded as required by RPC
    private func derivePrivateKeyForAddress(address: String, mnemonic: String) throws -> String {
        let keyData = try derivePrivateKeyDataForAddress(address: address, mnemonic: mnemonic)
        // Convert private key to WIF (Wallet Import Format) - base58-encoded
        // WIF format: version byte (0x80 for mainnet, but Telestai may use different) + private key + compression flag (0x01) + checksum
        // For Telestai, we'll use 0x80 as the version byte (standard Bitcoin mainnet, but may need adjustment)
        // Actually, let's check if Telestai uses a different version byte. For now, using 0x80 (standard)
        return privateKeyToWIF(privateKey: keyData)
    }
    
    /// Convert private key to WIF with a specific version byte (for retry logic)
    private func privateKeyToWIFWithVersion(privateKey: Data, versionByte: UInt8) -> String {
        let compressionFlag: UInt8 = 0x01 // Indicates compressed public key
        
        var payload = Data()
        payload.append(versionByte)
        payload.append(privateKey)
        payload.append(compressionFlag)
        
        // Calculate checksum: double SHA256 of payload, take first 4 bytes
        let hash = Data(SHA256.hash(data: Data(SHA256.hash(data: payload))))
        let checksum = hash.prefix(4)
        payload.append(checksum)
        
        // Encode to Base58
        return Base58.encode(payload)
    }
    
    /// Convert private key to WIF without compression flag (uncompressed public key)
    private func privateKeyToWIFUncompressed(privateKey: Data) -> String {
        let versionByte: UInt8 = 0x80 // Standard Bitcoin mainnet WIF version byte
        
        var payload = Data()
        payload.append(versionByte)
        payload.append(privateKey)
        // No compression flag for uncompressed
        
        // Calculate checksum: double SHA256 of payload, take first 4 bytes
        let hash = Data(SHA256.hash(data: Data(SHA256.hash(data: payload))))
        let checksum = hash.prefix(4)
        payload.append(checksum)
        
        // Encode to Base58
        let wif = Base58.encode(payload)
        print("🔍 TLSBlockchainService: Generated uncompressed WIF - first 10 chars: \(wif.prefix(10)), length: \(wif.count)")
        return wif
    }
    
    /// Validate that scriptPubKey matches the public key hash derived from private key
    /// Returns validation result with hash comparisons
    private func validateScriptPubKeyMatchesPrivateKey(scriptPubKeyHex: String, privateKeyData: Data, address: String) throws -> ScriptPubKeyValidationResult {
        // Extract pubkey hash from scriptPubKey
        // P2PKH format: 76a914<20-byte-hash>88ac
        guard scriptPubKeyHex.count >= 50, // Minimum length for P2PKH
              scriptPubKeyHex.hasPrefix("76a914"),
              scriptPubKeyHex.hasSuffix("88ac") else {
            throw NSError(domain: "TLSBlockchain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid scriptPubKey format (expected P2PKH)"])
        }
        
        // Extract the 20-byte hash (between 76a914 and 88ac)
        let hashStart = scriptPubKeyHex.index(scriptPubKeyHex.startIndex, offsetBy: 6) // After "76a914"
        let hashEnd = scriptPubKeyHex.index(scriptPubKeyHex.endIndex, offsetBy: -4) // Before "88ac"
        let hashHex = String(scriptPubKeyHex[hashStart..<hashEnd])
        
        guard let scriptHash = Data(hexString: hashHex), scriptHash.count == 20 else {
            throw NSError(domain: "TLSBlockchain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not extract pubkey hash from scriptPubKey"])
        }
        
        // Derive public key from private key (compressed)
        let signingKey = try Secp.Signing.PrivateKey(dataRepresentation: privateKeyData)
        let publicKeyCompressed = signingKey.publicKey.dataRepresentation
        
        // Verify it's compressed (33 bytes, starts with 0x02 or 0x03)
        guard publicKeyCompressed.count == 33,
              (publicKeyCompressed.first == 0x02 || publicKeyCompressed.first == 0x03) else {
            throw NSError(domain: "TLSBlockchain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Public key is not compressed (expected 33 bytes)"])
        }
        
        // Hash compressed public key: RIPEMD160(SHA256(public_key))
        let sha = Data(SHA256.hash(data: publicKeyCompressed))
        let ripemdCompressed = RIPEMD160.hash(sha)
        
        // Also derive uncompressed public key for comparison
        // Uncompressed format: 0x04 + x (32 bytes) + y (32 bytes) = 65 bytes
        // We need to derive it from the private key
        // For secp256k1, we can get the uncompressed point from the compressed one
        // But for now, let's just try to see if we can get it
        // Note: The secp256k1 library might not directly support uncompressed, so we'll log what we have
        
        let matchesCompressed = ripemdCompressed == scriptHash
        
        // Log detailed comparison
        print("🔍 TLSBlockchainService: scriptPubKey validation for \(address.prefix(8))...")
        print("   scriptPubKey format: P2PKH (76a914...88ac)")
        print("   scriptPubKey hash: \(hashHex)")
        print("   Public key (compressed, 33 bytes): \(publicKeyCompressed.map { String(format: "%02x", $0) }.joined().prefix(20))...")
        print("   Derived hash (compressed): \(ripemdCompressed.map { String(format: "%02x", $0) }.joined())")
        print("   Match: \(matchesCompressed ? "✅ YES" : "❌ NO")")
        
        return ScriptPubKeyValidationResult(
            matches: matchesCompressed,
            matchedFormat: matchesCompressed ? "compressed" : "none",
            scriptHashHex: hashHex,
            derivedHashCompressedHex: ripemdCompressed.map { String(format: "%02x", $0) }.joined(),
            derivedHashUncompressedHex: "" // We'll add this if needed
        )
    }
    
    /// Result of scriptPubKey validation
    private struct ScriptPubKeyValidationResult {
        let matches: Bool
        let matchedFormat: String
        let scriptHashHex: String
        let derivedHashCompressedHex: String
        let derivedHashUncompressedHex: String
    }
    
    /// Convert private key Data to WIF (Wallet Import Format) - base58-encoded
    /// WIF format: version byte + private key (32 bytes) + compression flag (0x01) + checksum (4 bytes)
    /// 
    /// NOTE: Telestai WIF version byte is currently unknown. We try multiple common values.
    /// Common WIF version bytes:
    /// - 0x80 (Bitcoin mainnet - most common)
    /// - 0xB0 (some Bitcoin forks like Ravencoin)
    /// - 0xEF (testnet, but unlikely for mainnet)
    /// - 0x42 (may match Telestai address version byte 0x42)
    private func privateKeyToWIF(privateKey: Data) -> String {
        // Try multiple WIF version bytes - Telestai may use a non-standard one
        // We'll try the most common ones and use the first (0x80) as default
        let wifVersionBytes: [UInt8] = [0x80, 0xEF, 0xB0, 0x42] // Common Bitcoin, Testnet, Ravencoin, and Telestai address prefix
        let compressionFlag: UInt8 = 0x01 // Indicates compressed public key
        
        // For now, we'll use 0x80 as the default. If signing fails, we may need to iterate through these.
        // TODO: Implement retry logic that tries different version bytes if signing fails
        let versionByte = wifVersionBytes[0] // Start with 0x80 (Bitcoin standard)
        
        var payload = Data()
        payload.append(versionByte)
        payload.append(privateKey)
        payload.append(compressionFlag)
        
        // Calculate checksum: double SHA256 of payload, take first 4 bytes
        let hash = Data(SHA256.hash(data: Data(SHA256.hash(data: payload))))
        let checksum = hash.prefix(4)
        payload.append(checksum)
        
        // Encode to Base58
        let wif = Base58.encode(payload)
        
        // Log WIF details for debugging
        print("🔍 TLSBlockchainService: Generated WIF with version byte 0x\(String(format: "%02X", versionByte)) - first 10 chars: \(wif.prefix(10)), length: \(wif.count)")
        
        return wif
    }
    
    /// Broadcast transaction with retry logic
    private func broadcastTransactionWithRetry(hex: String, maxRetries: Int = 3) async throws -> String {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let txid = try await TLSRPCClient.shared.sendRawTransaction(hex: hex)
                if attempt > 1 {
                    print("✅ TLSBlockchainService: Transaction broadcast succeeded on attempt \(attempt)")
                }
                return txid
            } catch {
                lastError = error
                print("⚠️ TLSBlockchainService: Broadcast attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = Double(1 << (attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(domain: "TLSBlockchain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction broadcast failed after \(maxRetries) attempts"])
    }
    
    // MARK: - Message-Specific Transactions
    func sendMessageTransaction(toAddress: String, encryptedMessage: String, messageType: String = "text") async -> TLSPaymentResponse {
        // Send a message transaction (minimal amount, mostly for message delivery)
        return await sendPayment(
            toAddress: toAddress,
            amount: 0.0, // No actual payment, just message delivery
            message: encryptedMessage,
            messageType: messageType
        )
    }
    
    func sendPaymentMessage(toAddress: String, amount: Double, message: String) async -> TLSPaymentResponse {
        // Send a payment with an attached message
        return await sendPayment(
            toAddress: toAddress,
            amount: amount,
            message: message,
            messageType: "payment"
        )
    }
    
    // MARK: - Message Scanning
    func scanForMessages(address: String) async -> [TLSBlockchainMessageTransaction] {
        guard let addressInfo = await getAddressInfo(address: address) else { return [] }
        
        var messageTransactions: [TLSBlockchainMessageTransaction] = []
        
        for transaction in addressInfo.transactions {
            // Check if transaction contains a message
            if let message = transaction.message, let messageType = transaction.messageType {
                let messageTransaction = TLSBlockchainMessageTransaction(
                    txid: transaction.txid,
                    fromAddress: transaction.from ?? "",
                    toAddress: transaction.to ?? "",
                    amount: transaction.amount,
                    fee: transaction.fee,
                    message: message,
                    messageType: messageType,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(transaction.timestamp)),
                    blockHeight: 0, // Would be actual block height in real implementation
                    confirmations: transaction.confirmations,
                    signature: "" // Would be actual signature in real implementation
                )
                messageTransactions.append(messageTransaction)
            }
        }
        
        return messageTransactions
    }
    
    // MARK: - Block Height Monitoring
    func getCurrentBlockHeight() async -> Int {
        // In a real implementation, this would query the blockchain for current block height
        // For now, we'll simulate with a random block height
        return Int.random(in: 1000000...9999999)
    }
    
    func getBlockInfo(blockHeight: Int) async -> [String: Any]? {
        // In a real implementation, this would fetch block information
        // For now, we'll return mock data
        return [
            "height": blockHeight,
            "hash": "TLS" + String((0..<64).map { _ in "0123456789abcdef".randomElement()! }),
            "timestamp": Int(Date().timeIntervalSince1970),
            "transactions": []
        ]
    }
    
    // MARK: - Transaction History
    func getTransactionHistory(address: String) async -> [TLSTransaction] {
        guard let addressInfo = await getAddressInfo(address: address) else { return [] }
        return addressInfo.transactions
    }
    
    // MARK: - Message Transaction History
    func getMessageTransactionHistory(address: String) async -> [TLSBlockchainMessageTransaction] {
        return await scanForMessages(address: address)
    }
    
    // MARK: - Subscription Payment
    func processSubscriptionPayment() async -> Bool {
        // Subscription payment to a designated TLS address
        let subscriptionAddress = "TLS_SUBSCRIPTION_ADDRESS" // Replace with actual subscription address
        let subscriptionAmount = 10.0 // 10 TLS for subscription
        
        let paymentResponse = await sendPayment(
            toAddress: subscriptionAddress,
            amount: subscriptionAmount,
            message: "PAAI App Subscription",
            messageType: "system"
        )
        
        if paymentResponse.success {
            // Save subscription status
            let date = ISO8601DateFormatter().string(from: Date())
            _ = walletService.keychain.save(key: "last_payment", value: date)
            _ = walletService.keychain.save(key: "subscription_txid", value: paymentResponse.txid ?? "")
            return true
        }
        
        return false
    }
    
    // MARK: - Balance Check
    func refreshBalance(force: Bool = false) async {
        print("🔄 TLSBlockchainService.refreshBalance: Starting (force=\(force))")
        
        if !force {
            if isRefreshingBalance {
                print("⏭️ TLSBlockchainService.refreshBalance: Already refreshing, skipping")
                return
            }
            
            if let lastRefreshDate,
               Date().timeIntervalSince(lastRefreshDate) < refreshCooldown {
                print("⏭️ TLSBlockchainService.refreshBalance: Within cooldown period, skipping")
                return
            }
        }
        
        isRefreshingBalance = true
        defer {
            isRefreshingBalance = false
            lastRefreshDate = Date()
        }
        
        print("🔍 TLSBlockchainService.refreshBalance: Performing address discovery...")
        await performAddressDiscoveryIfNeeded()
        
        // Gather receive/change metadata so we can map usage back to derivation indices
        let receiveInfos = AddressManager.shared.getUsedReceiveAddressInfos()
        let changeInfos = AddressManager.shared.getUsedChangeAddressInfos()
        var combinedAddresses = (receiveInfos.map { $0.address } + changeInfos.map { $0.address })
        if combinedAddresses.isEmpty, let primary = walletService.loadAddress() {
            combinedAddresses = [primary]
        }
        let addressesToCheck = combinedAddresses.deduplicated()
        guard !addressesToCheck.isEmpty else {
            await MainActor.run {
                self.currentBalance = 0
                self.recentTransactions = []
            }
            return
        }
        
        let receiveLookup = Dictionary(uniqueKeysWithValues: receiveInfos.map { ($0.address, $0.index) })
        let changeLookup = Dictionary(uniqueKeysWithValues: changeInfos.map { ($0.address, $0.index) })
        var highestUsedReceive: UInt32?
        var highestUsedChange: UInt32?
        
        var totalBalance: Double = 0.0
        var collectedTransactions: [TLSTransaction] = []
        
        for chunk in addressesToCheck.chunked(into: addressFetchBatchSize) {
            await withTaskGroup(of: (String, TLSAddress?, Double).self) { group in
                for address in chunk {
                    group.addTask { [weak self] in
                        guard let self = self else { return (address, nil, 0.0) }
                        async let info = self.getAddressInfo(address: address)
                        async let balance = self.fetchAddressUTXOBalance(address: address)
                        return (address, await info, await balance)
                    }
                }
                
                for await (address, info, balance) in group {
                    totalBalance += balance
                    guard let info = info else { continue }
                    collectedTransactions.append(contentsOf: info.transactions)
                    
                    if info.hasActivity, let idx = receiveLookup[address] {
                        highestUsedReceive = max(highestUsedReceive ?? idx, idx)
                    }
                    if info.hasActivity, let idx = changeLookup[address] {
                        highestUsedChange = max(highestUsedChange ?? idx, idx)
                    }
                }
            }
        }
        
        let finalBalance = totalBalance
        let aggregatedTransactions = aggregateTransactions(collectedTransactions)
        
        await MainActor.run {
            self.currentBalance = finalBalance
            
            // Deduplicate explorer transactions while preserving newest-first order
            let sorted = aggregatedTransactions.sorted { $0.timestamp > $1.timestamp }
            var uniqueTransactions: [TLSTransaction] = []
            var seenTxids = Set<String>()
            for tx in sorted where !seenTxids.contains(tx.txid) {
                uniqueTransactions.append(tx)
                seenTxids.insert(tx.txid)
            }
            
            // Preserve pending (locally-sent) transactions that haven't appeared on-chain yet
            let pending = self.recentTransactions.filter { $0.confirmations == 0 }
            for pendingTx in pending where !seenTxids.contains(pendingTx.txid) {
                uniqueTransactions.insert(pendingTx, at: 0)
                seenTxids.insert(pendingTx.txid)
            }
            
            self.recentTransactions = uniqueTransactions
        }
        
        print("✅ TLSBlockchainService: Total balance from \(addressesToCheck.count) addresses: \(totalBalance) TLS")
        
        trimDerivedPathsIfNeeded(receiveIndex: highestUsedReceive, changeIndex: highestUsedChange)
        
        Task {
            await self.refreshAggregatedBalance()
        }
    }
    
    private func performAddressDiscoveryIfNeeded() async {
        if hasPerformedAddressDiscovery {
            print("⏭️ TLSBlockchainService: Address discovery already performed, skipping")
            return
        }
        if isDiscoveringAddresses {
            print("⏭️ TLSBlockchainService: Address discovery in progress, skipping")
            return
        }
        
        print("🔍 TLSBlockchainService: Starting address discovery (derivation-only, fast path)...")
        isDiscoveringAddresses = true
        defer { isDiscoveringAddresses = false }
        
        let discoveredViaDerivation = await AddressManager.shared.discoverUsedIndices(
            gapLimit: addressDiscoveryGapLimit,
            scanReceiveOnly: true
        ) { address in
            // Fast RPC check: does this address have any UTXOs?
            do {
                let utxos = try await TLSRPCClient.shared.listUnspent(address: address)
                return !utxos.isEmpty
            } catch {
                return false
            }
        }
        
        hasPerformedAddressDiscovery = discoveredViaDerivation
        print("✅ TLSBlockchainService: Address discovery complete (derivation=\(discoveredViaDerivation))")
    }
    
    private func recoverAddressesFromWallet() async -> Bool {
        do {
            let walletTransactions = try await TLSRPCClient.shared.listTransactions(count: 1000)
            let addressCount = Set(walletTransactions.compactMap { $0.address?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
            AddressManager.shared.ingestWalletTransactions(walletTransactions)
            print("🔍 TLSBlockchainService: Recovered \(addressCount) wallet addresses from RPC")
            return true
        } catch {
            print("⚠️ TLSBlockchainService: Failed to recover wallet addresses from RPC: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get total balance across all addresses
    func getTotalBalance() async -> Double {
        let allAddresses = AddressManager.shared.getAllUsedAddresses()
        var total: Double = 0.0
        
        // If no addresses from AddressManager, fall back to primary address
        let addressesToCheck = allAddresses.isEmpty ? [walletService.loadAddress()].compactMap { $0 } : allAddresses
        
        for address in addressesToCheck {
            if let addressInfo = await getAddressInfo(address: address) {
                total += addressInfo.balance
            }
        }
        
        return total
    }
    
    // MARK: - On-Ramp Integration (Future)
    func getOnRampOptions() -> [String] {
        // Future implementation for fiat-to-TLS on-ramp
        return [
            "Credit Card",
            "Bank Transfer", 
            "Crypto Exchange",
            "P2P Trading"
        ]
    }
    
    func initiateOnRamp(method: String, amount: Double) async -> Bool {
        // Future implementation for on-ramp processing
        // This would integrate with services like MoonPay, Ramp, etc.
        print("Initiating on-ramp: \(method) for \(amount) TLS")
        return true
    }
    
    // MARK: - Message Verification
    func verifyMessageTransaction(_ transaction: TLSBlockchainMessageTransaction) -> Bool {
        // In a real implementation, this would verify the transaction signature
        // For now, we'll return true if the transaction has a message
        return !transaction.message.isEmpty
    }
    
    // MARK: - Group Chat Support
    func sendGroupMessage(groupAddress: String, message: String, messageType: String = "group") async -> TLSPaymentResponse {
        // Send message to a group address (special address for group chats)
        return await sendMessageTransaction(
            toAddress: groupAddress,
            encryptedMessage: message,
            messageType: messageType
        )
    }
}

// MARK: - Extensions
extension TLSBlockchainService {
    func formatBalance(_ balance: Double) -> String {
        return String(format: "%.6f TLS", balance)
    }
    
    func formatAmount(_ amount: Double) -> String {
        return String(format: "%.6f", amount)
    }
} 

private struct AggregatedTransactionState {
    let txid: String
    var sendAmount: Double = 0.0
    var receiveAmount: Double = 0.0
    var fee: Double = 0.0
    var confirmations: Int = 0
    var timestamp: Int = 0
    var message: String?
    var messageType: String?
    var sendAddress: String?
    var receiveAddress: String?
    var sawSend = false
    var sawReceive = false
    var lastType: String = "receive"
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var start = 0
        while start < count {
            let end = Swift.min(start + size, count)
            result.append(Array(self[start..<end]))
            start = end
        }
        return result
    }
}

private extension Array where Element: Hashable {
    func deduplicated() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for item in self where seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }
}

private extension TLSAddress {
    var hasActivity: Bool {
        balance > 0 || !transactions.isEmpty
    }
}