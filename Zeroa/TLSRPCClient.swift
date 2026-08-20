import Foundation

// MARK: - TLS RPC Models
struct RPCRequest: Codable {
    let method: String
    let params: [AnyCodable]
    let id: Int
}

struct RPCResponse: Codable {
    let result: AnyCodable?
    let error: RPCError?
    let id: Int
}

struct RPCError: Codable {
    let code: Int
    let message: String
}

struct UTXO: Codable {
    let txid: String
    let vout: Int
    let address: String
    let amount: Double
    let confirmations: Int
    let scriptPubKey: String
}

struct RawTransaction: Codable {
    let hex: String
}

struct RPCWalletTransaction: Codable {
    let involvesWatchonly: Bool?
    let address: String?
    let category: String
    let amount: Double
    let fee: Double?
    let confirmations: Int?
    let blockhash: String?
    let blockindex: Int?
    let blocktime: Int?
    let txid: String
    let time: Int?
    let timereceived: Int?
}

struct SignedTransaction: Codable {
    let hex: String
    let complete: Bool
    let errors: [SigningError]?
    
    enum CodingKeys: String, CodingKey {
        case hex
        case complete
        case errors
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hex = try container.decode(String.self, forKey: .hex)
        complete = try container.decode(Bool.self, forKey: .complete)
        // errors is optional and might not be present
        errors = try? container.decode([SigningError].self, forKey: .errors)
    }
}

private struct AddressIndexUTXO: Codable {
    let address: String
    let txid: String
    let outputIndex: Int
    let script: String
    let satoshis: Int64
    let height: Int
}

struct SigningError: Codable {
    let txid: String?
    let vout: Int?
    let scriptSig: String?
    let sequence: Int?
    let error: String?
    let witness: [String]?
}

// MARK: - TLS RPC Client
class TLSRPCClient {
    static let shared = TLSRPCClient()
    
    // Use Halo API as proxy to RPC on mainnet (more secure than direct RPC access).
    // TestNet uses TLSNetwork.rpcBaseURL (Optimus soak proxy). Route: …/rpc.
    private var defaultBaseURL: String { TLSNetwork.current.rpcBaseURL }
    private let baseURLOVerrideDefaultsKey = "zeroa_rpc_base_url_override"
    private let overrideMigrationDefaultsKey = "zeroa_rpc_override_migration_v1"
    private let userDefaults = UserDefaults.standard
    private let environmentOverride: String?
    private let environmentOverrideEnabled: Bool
    private var environmentOverrideDisabled = false
    
    private init() {
        environmentOverrideEnabled = Self.isEnvironmentOverrideEnabled()
        
        if let rawOverride = ProcessInfo.processInfo.environment["ZEROA_RPC_BASE_URL"],
           !rawOverride.isEmpty {
            if environmentOverrideEnabled {
                let sanitized = Self.sanitizeBaseURL(rawOverride)
                environmentOverride = sanitized
                print("⚙️ TLSRPCClient: Detected ZEROA_RPC_BASE_URL override: \(sanitized)")
            } else {
                environmentOverride = nil
                print("⚠️ TLSRPCClient: Ignoring ZEROA_RPC_BASE_URL override (override feature disabled).")
            }
        } else {
            environmentOverride = nil
        }
    }
    
    /// Allows runtime override of the RPC base URL. Pass nil to clear.
    func setBaseURLOverride(_ urlString: String?) {
        if let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty {
            userDefaults.set(urlString, forKey: baseURLOVerrideDefaultsKey)
            AppGroupsService.shared.sharedDefaults?.set(urlString, forKey: baseURLOVerrideDefaultsKey)
            AppGroupsService.shared.sharedDefaults?.synchronize()
            print("⚙️ TLSRPCClient: Persisted RPC base URL override: \(urlString)")
        } else {
            userDefaults.removeObject(forKey: baseURLOVerrideDefaultsKey)
            AppGroupsService.shared.sharedDefaults?.removeObject(forKey: baseURLOVerrideDefaultsKey)
            AppGroupsService.shared.sharedDefaults?.synchronize()
            print("⚙️ TLSRPCClient: Cleared RPC base URL override; falling back to default.")
        }
    }
    
    /// Returns the currently effective base URL (environment > persisted override > default)
    func currentBaseURL() -> String {
        if environmentOverrideEnabled,
           let envOverride = environmentOverride,
           !environmentOverrideDisabled {
            return envOverride
        }
        
        if let persisted = userDefaults.string(forKey: baseURLOVerrideDefaultsKey),
           !persisted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.sanitizeBaseURL(persisted)
        }
        
        if let appGroupOverride = AppGroupsService.shared.sharedDefaults?.string(forKey: baseURLOVerrideDefaultsKey),
           !appGroupOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.sanitizeBaseURL(appGroupOverride)
        }
        
        return defaultBaseURL
    }
    
    /// Clears any previously persisted RPC overrides once.
    func performLegacyOverrideMigrationIfNeeded() {
        if userDefaults.bool(forKey: overrideMigrationDefaultsKey) {
            return
        }
        
        setBaseURLOverride(nil)
        userDefaults.set(true, forKey: overrideMigrationDefaultsKey)
        AppGroupsService.shared.sharedDefaults?.set(true, forKey: overrideMigrationDefaultsKey)
        AppGroupsService.shared.sharedDefaults?.synchronize()
        
        print("🧹 TLSRPCClient: Cleared legacy RPC overrides.")
    }
    
    private static func sanitizeBaseURL(_ urlString: String) -> String {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
    
    private static func isEnvironmentOverrideEnabled() -> Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment["ZEROA_ENABLE_RPC_OVERRIDE"] == "1"
#else
        return false
#endif
    }
    
    // MARK: - RPC Methods
    
    /// Get unspent transaction outputs for an address
    func listUnspent(address: String) async throws -> [UTXO] {
        // Try getaddressutxos first (requires address indexing)
        let addressesDict: [String: AnyCodable] = ["addresses": AnyCodable([address])]
        let getAddressParams: [AnyCodable] = [AnyCodable(addressesDict)]
        
        var response = try await callRPC(method: "getaddressutxos", params: getAddressParams)
        
        // If getaddressutxos fails with "No information available", try listunspent as fallback
        if let error = response.error, error.code == -5 {
            print("⚠️ TLSRPCClient: getaddressutxos returned 'No information available', trying listunspent fallback...")
            
            // Use listunspent with address filter: listunspent(minconf, maxconf, [addresses])
            let listUnspentParams: [AnyCodable] = [
                AnyCodable(0),      // minconf
                AnyCodable(9999999), // maxconf
                AnyCodable([address]) // addresses array
            ]
            
            response = try await callRPC(method: "listunspent", params: listUnspentParams)
        }
        
        if let error = response.error {
            print("❌ TLSRPCClient: listunspent failed for \(address): \(error.message) (code: \(error.code))")
            throw NSError(domain: "TLSRPC", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        guard let result = response.result else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "RPC returned no result for address \(address)"])
        }
        
        // Decode UTXO array
        let jsonData = try JSONEncoder().encode(result)
        let decoder = JSONDecoder()
        if let utxos = try? decoder.decode([UTXO].self, from: jsonData) {
            let filteredUtxos = utxos.filter { $0.address == address }
            
            if filteredUtxos.isEmpty && !utxos.isEmpty {
                print("⚠️ TLSRPCClient: Found \(utxos.count) UTXOs but none match address \(address)")
            }
            
            return filteredUtxos.isEmpty ? utxos : filteredUtxos
        }
        
        if let indexed = try? decoder.decode([AddressIndexUTXO].self, from: jsonData) {
            let currentHeight = try await getBlockCount()
            return indexed.map {
                UTXO(
                    txid: $0.txid,
                    vout: $0.outputIndex,
                    address: $0.address,
                    amount: Double($0.satoshis) / 100_000_000.0,
                    confirmations: max(0, currentHeight - $0.height + 1),
                    scriptPubKey: $0.script
                )
            }
        }
        
        throw NSError(
            domain: "TLSRPC",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to decode UTXOs for address \(address)"]
        )
    }
    
    /// List wallet transactions for the node wallet (used as explorer fallback)
    func listTransactions(count: Int = 200) async throws -> [RPCWalletTransaction] {
        let params: [AnyCodable] = [
            AnyCodable("*"),          // account
            AnyCodable(count),        // count
            AnyCodable(0),            // skip
            AnyCodable(true)          // include_watchonly
        ]
        
        let response = try await callRPC(method: "listtransactions", params: params)
        
        if let error = response.error {
            throw NSError(domain: "TLSRPC", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        guard let result = response.result else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "RPC returned no result for listtransactions"])
        }
        
        let jsonData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode([RPCWalletTransaction].self, from: jsonData)
    }
    
    /// Create a raw transaction
    func createRawTransaction(inputs: [[String: AnyCodable]], outputs: [String: AnyCodable]) async throws -> String {
        // Validate inputs and outputs before encoding
        guard !inputs.isEmpty else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transaction inputs"])
        }
        guard !outputs.isEmpty else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transaction outputs"])
        }
        
        // Validate that all output amounts are valid numbers
        for (address, amountCodable) in outputs {
            guard let amount = amountCodable.value as? Double else {
                throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid amount type for address \(address)"])
            }
            guard amount.isFinite && amount >= 0 else {
                throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid amount value for address \(address): \(amount)"])
            }
        }
        
        let params: [AnyCodable] = [
            AnyCodable(inputs),
            AnyCodable(outputs)
        ]
        
        let response = try await callRPC(method: "createrawtransaction", params: params)
        
        if let error = response.error {
            throw NSError(domain: "TLSRPC", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        guard let result = response.result,
              let hex = result.value as? String else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return hex
    }
    
    /// Sign a raw transaction using private keys (CLIENT-SIDE via RPC)
    /// This is more secure than server-side signing as private keys are only in the RPC request
    /// - Parameters:
    ///   - hex: Raw transaction hex
    ///   - privateKeys: Array of private key hex strings
    ///   - prevTxs: Optional previous transaction outputs (for proper signing)
    ///   - sighashType: SIGHASH flag (default: SIGHASH_ALL = 0x01)
    /// - Returns: Signed transaction
    func signRawTransaction(hex: String, privateKeys: [String], prevTxs: [[String: AnyCodable]]? = nil, sighashType: String = "ALL") async throws -> SignedTransaction {
        // Build params: [hexstring, prevtxs, privatekeys, sighashtype]
        var params: [AnyCodable] = [AnyCodable(hex)]
        
        // Add previous transactions if provided
        // RPC expects: null or array of objects with txid, vout, scriptPubKey, amount
        if let prevTxs = prevTxs, !prevTxs.isEmpty {
            params.append(AnyCodable(prevTxs))
        } else {
            // Pass null instead of empty array - some RPC implementations prefer null
            // But JSON encoding doesn't support null directly, so we'll pass empty array
            params.append(AnyCodable([] as [[String: AnyCodable]]))
        }
        
        // Add private keys (this is the key difference - keys are in RPC request, not stored on server)
        params.append(AnyCodable(privateKeys))
        
        // Add SIGHASH type
        params.append(AnyCodable(sighashType))
        
        // Log parameter structure for debugging
        print("🔍 TLSRPCClient: signrawtransaction params structure:")
        print("   params[0] (hex): \(hex.prefix(50))... (length: \(hex.count))")
        print("   params[1] (prevTxs): \(prevTxs?.count ?? 0) items")
        if let prevTxs = prevTxs, !prevTxs.isEmpty {
            for (idx, prevTx) in prevTxs.enumerated() {
                if let txid = prevTx["txid"]?.value as? String,
                   let vout = prevTx["vout"]?.value as? Int,
                   let scriptPubKey = prevTx["scriptPubKey"]?.value as? String,
                   let amount = prevTx["amount"]?.value as? Double {
                    print("      prevTxs[\(idx)]: txid=\(txid.prefix(16))..., vout=\(vout), scriptPubKey=\(scriptPubKey.prefix(20))..., amount=\(amount)")
        }
            }
        }
        print("   params[2] (privateKeys): \(privateKeys.count) key(s)")
        for (idx, key) in privateKeys.enumerated() {
            print("      privateKeys[\(idx)]: WIF length=\(key.count), starts with '\(key.prefix(1))'")
        }
        print("   params[3] (sighashType): \(sighashType)")
        
        let response = try await callRPC(method: "signrawtransaction", params: params)
        
        if let error = response.error {
            print("❌ TLSRPCClient: signrawtransaction RPC error: \(error.message) (code: \(error.code))")
            throw NSError(domain: "TLSRPC", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        guard let result = response.result else {
            print("❌ TLSRPCClient: signrawtransaction returned no result")
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result from RPC"])
        }
        
        // Decode signed transaction
        let jsonData = try JSONEncoder().encode(result)
        let signed = try JSONDecoder().decode(SignedTransaction.self, from: jsonData)
        
        if !signed.complete {
            print("❌ TLSRPCClient: Transaction signing incomplete. Signed hex length: \(signed.hex.count) bytes")
            if let errors = signed.errors, !errors.isEmpty {
                for (index, error) in errors.enumerated() {
                    print("   Error \(index + 1): txid=\(error.txid ?? "unknown"), vout=\(error.vout?.description ?? "unknown"), error='\(error.error ?? "unknown")'")
                }
            }
            // Try to log more details if available
            if let resultDict = result.value as? [String: Any] {
                print("   RPC result details: \(resultDict)")
            }
        } else {
            print("✅ TLSRPCClient: Transaction signing complete. Signed hex length: \(signed.hex.count) bytes")
        }
        
        return signed
    }
    
    /// Send a raw transaction
    func sendRawTransaction(hex: String) async throws -> String {
        let params: [AnyCodable] = [AnyCodable(hex)]
        
        let response = try await callRPC(method: "sendrawtransaction", params: params)
        
        if let error = response.error {
            throw NSError(domain: "TLSRPC", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        guard let result = response.result,
              let txid = result.value as? String else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return txid
    }
    
    /// Import a private key into the RPC wallet (temporary, for signing)
    /// WARNING: This stores the private key on the server temporarily
    /// Returns the address associated with the imported key, or nil if import failed
    func importPrivateKey(wif: String, label: String = "", rescan: Bool = false) async throws -> String? {
        let params: [AnyCodable] = [
            AnyCodable(wif),
            AnyCodable(label),
            AnyCodable(rescan)
        ]
        
        let response = try await callRPC(method: "importprivkey", params: params)
        
        if let error = response.error {
            // If key already exists, that's okay - try to get the address
            if error.message.contains("already exists") || error.message.contains("already in") {
                print("⚠️ TLSRPCClient: Private key already imported (this is okay)")
                // Try to get the address using getaddressesbyaccount or validateaddress
                // For now, return nil and let the caller handle it
                return nil
            }
            print("❌ TLSRPCClient: importprivkey RPC error: \(error.message) (code: \(error.code))")
            throw NSError(domain: "TLSRPC", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        print("✅ TLSRPCClient: Private key imported successfully")
        
        // Try to get the address associated with this key
        // We can use getaddressesbyaccount with empty string to get all addresses
        do {
            let addressResponse = try await callRPC(method: "getaddressesbyaccount", params: [AnyCodable("")])
            if let addressResult = addressResponse.result,
               let addresses = addressResult.value as? [String],
               let lastAddress = addresses.last {
                print("🔍 TLSRPCClient: Imported key is associated with address: \(lastAddress)")
                return lastAddress
            }
        } catch {
            print("⚠️ TLSRPCClient: Could not determine address for imported key: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Get current block height
    func getBlockCount() async throws -> Int {
        let response = try await callRPC(method: "getblockcount", params: [])
        
        if let error = response.error {
            throw NSError(domain: "TLSRPC", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        
        guard let result = response.result else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result from RPC"])
        }
        
        if let count = result.value as? Int {
            return count
        } else if let countStr = result.value as? String, let count = Int(countStr) {
            return count
        }
        
        throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid block count format"])
    }
    
    // MARK: - Internal Methods (accessible to other services)
    
    /// Internal RPC call method (accessible to other services in the module)
    func callRPC(method: String, params: [AnyCodable], allowOverrideRetry: Bool = true) async throws -> RPCResponse {
        let baseURL = currentBaseURL()
        guard let url = URL(string: "\(baseURL)/rpc") else {
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let request = RPCRequest(method: method, params: params, id: Int.random(in: 1...1000000))
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encode with better error handling
        do {
        urlRequest.httpBody = try JSONEncoder().encode(request)
            
            // Log the actual JSON being sent for debugging (especially for signrawtransaction)
            if method == "signrawtransaction" {
                if let jsonString = String(data: urlRequest.httpBody!, encoding: .utf8) {
                    print("🔍 TLSRPCClient: signrawtransaction request JSON:")
                    // Redact private keys for security, but show structure
                    let redacted = jsonString.replacingOccurrences(of: #""[A-Za-z0-9]{50,}""#, with: "\"[REDACTED_WIF]\"", options: .regularExpression)
                    print("   \(redacted.prefix(500))\(redacted.count > 500 ? "..." : "")")
                }
            }
        } catch {
            print("❌ TLSRPCClient: JSON encoding error: \(error)")
            if let encodingError = error as? EncodingError {
                print("   Encoding error details: \(encodingError)")
            }
            throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request: \(error.localizedDescription)"])
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
            guard let httpResponse = response as? HTTPURLResponse else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
                print("❌ TLSRPCClient: Invalid HTTP response: \(errorMsg)")
                throw NSError(domain: "TLSRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response: \(errorMsg)"])
            }
        
            guard httpResponse.statusCode == 200 else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP error"
                print("❌ TLSRPCClient: HTTP \(httpResponse.statusCode): \(errorMsg)")
                throw NSError(domain: "TLSRPC", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorMsg)"])
            }
        
            let rpcResponse = try JSONDecoder().decode(RPCResponse.self, from: data)
        
            if let error = rpcResponse.error {
                print("❌ TLSRPCClient: RPC error (\(method)): \(error.message) (code: \(error.code))")
            }
        
            return rpcResponse
        } catch {
            if allowOverrideRetry,
               shouldDisableEnvironmentOverride(baseURL: baseURL, error: error) {
                environmentOverrideDisabled = true
                print("⚠️ TLSRPCClient: RPC override \(baseURL) unreachable, falling back to default.")
                return try await callRPC(method: method, params: params, allowOverrideRetry: false)
            }
            throw error
        }
    }
    
    private func shouldDisableEnvironmentOverride(baseURL: String, error: Error) -> Bool {
        guard let envOverride = environmentOverride,
              !environmentOverrideDisabled,
              baseURL == envOverride else {
            return false
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        
        return false
    }
}

// MARK: - JSON Coding Key Helper
struct JSONCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - AnyCodable Helper
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        // Use unkeyed/keyed containers for complex types, single value for primitives
        switch value {
        case let bool as Bool:
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case let int as Int:
            var container = encoder.singleValueContainer()
            try container.encode(int)
        case let int64 as Int64:
            var container = encoder.singleValueContainer()
            try container.encode(int64)
        case let double as Double:
            // Validate Double is finite before encoding
            guard double.isFinite else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode non-finite Double value: \(double)"))
            }
            var container = encoder.singleValueContainer()
            try container.encode(double)
        case let string as String:
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case let stringArray as [String]:
            // Handle arrays of strings specifically (needed for RPC params like addresses)
            var container = encoder.singleValueContainer()
            try container.encode(stringArray)
        case let array as [Any]:
            var container = encoder.singleValueContainer()
            try container.encode(array.map { AnyCodable($0) })
        case let anyCodableDict as [String: AnyCodable]:
            // Handle dictionaries that already have AnyCodable values
            // Use keyed container to encode each value
            var keyedContainer = encoder.container(keyedBy: JSONCodingKey.self)
            for (key, anyCodableValue) in anyCodableDict {
                let codingKey = JSONCodingKey(stringValue: key)!
                try anyCodableValue.encode(to: keyedContainer.superEncoder(forKey: codingKey))
            }
        case let dict as [String: Any]:
            var keyedContainer = encoder.container(keyedBy: JSONCodingKey.self)
            for (key, val) in dict {
                let codingKey = JSONCodingKey(stringValue: key)!
                try AnyCodable(val).encode(to: keyedContainer.superEncoder(forKey: codingKey))
            }
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable value cannot be encoded: \(type(of: value))"))
        }
    }
}

