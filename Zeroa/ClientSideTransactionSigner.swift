import Foundation
import CryptoKit
#if canImport(P256K)
import P256K
#elseif canImport(secp256k1)
import secp256k1
#endif

/// Client-side transaction signer - replicates Core wallet's CWallet::SignTransaction behavior
/// Signs transactions locally without relying on RPC signrawtransaction
final class ClientSideTransactionSigner {
    static let shared = ClientSideTransactionSigner()
    
    private init() {}
    
    // SIGHASH flags
    private let SIGHASH_ALL: UInt8 = 0x01
    private let SIGHASH_NONE: UInt8 = 0x02
    private let SIGHASH_SINGLE: UInt8 = 0x03
    private let SIGHASH_ANYONECANPAY: UInt8 = 0x80
    
    private enum SigVersion {
        case legacy      // SIGVERSION_BASE in Core (P2PKH, P2SH, etc.)
        case witnessV0   // SIGVERSION_WITNESS_V0 (P2WPKH / P2WSH)
    }
    
    /// Sign a raw transaction using client-side signing (like Core wallet)
    /// - Parameters:
    ///   - rawHex: Raw transaction hex string
    ///   - inputs: Array of input info (txid, vout, scriptPubKey, amount)
    ///   - privateKeys: Array of private key Data (32 bytes each) for each input
    ///   - sighashType: SIGHASH flag (default: SIGHASH_ALL)
    /// - Returns: Signed transaction hex string
    func signTransaction(
        rawHex: String,
        inputs: [TransactionInput],
        privateKeys: [Data],
        sighashType: UInt8 = 0x01 // SIGHASH_ALL
    ) throws -> String {
        // Log the raw transaction hex we're about to parse
        print("🔍 ClientSideSigner: Parsing raw transaction:")
        print("   Raw hex (first 200 chars): \(rawHex.prefix(200))...")
        print("   Raw hex length: \(rawHex.count) chars = \(rawHex.count / 2) bytes")
        
        // Parse transaction
        let tx = try parseTransaction(hex: rawHex)
        
        // Log the parsed transaction
        print("🔍 ClientSideSigner: Parsed transaction:")
        print("   Version: \(tx.version)")
        print("   Input count: \(tx.inputs.count)")
        for (idx, input) in tx.inputs.enumerated() {
            print("   Input \(idx): prevTxid=\(input.prevTxid.map { String(format: "%02x", $0) }.joined().prefix(16))..., prevVout=\(input.prevVout), scriptSig length=\(input.scriptSig.count), sequence=\(input.sequence)")
        }
        print("   Output count: \(tx.outputs.count)")
        for (idx, output) in tx.outputs.enumerated() {
            print("   Output \(idx): value=\(output.value) satoshis (\(Double(output.value) / 100_000_000.0) TLS), scriptPubKey length=\(output.scriptPubKey.count)")
        }
        print("   Locktime: \(tx.locktime)")
        
        guard tx.inputs.count == inputs.count else {
            throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Input count mismatch"])
        }
        
        guard privateKeys.count == inputs.count else {
            throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Private key count mismatch"])
        }
        
        // Sign each input
        var signedTx = tx // Make mutable copy
        for (index, input) in inputs.enumerated() {
            let privateKey = privateKeys[index]
            
            // Compute SignatureHash
            let scriptPubKey = Data(hexString: input.scriptPubKey) ?? Data()
            print("🔍 ClientSideSigner: Computing signature hash for input \(index)")
            print("   scriptPubKey (hex): \(scriptPubKey.map { String(format: "%02x", $0) }.joined())")
            print("   scriptPubKey length: \(scriptPubKey.count) bytes")
            print("   amount: \(input.amount) TLS")
            print("   sighashType: 0x\(String(format: "%02x", sighashType))")
            
            let signatureHash = try computeSignatureHash(
                transaction: tx,
                inputIndex: index,
                scriptPubKey: scriptPubKey,
                amount: input.amount,
                sighashType: sighashType
            )
            
            // Sign the hash (use same crypto library as CryptoService)
            // CRITICAL: Convert CryptoKit.SHA256.Digest to P256K.SHA256Digest
            // This ensures we use the DigestSigner protocol which signs the hash directly
            // WITHOUT additional internal hashing.
            //
            // The P256K library has two signature methods:
            // 1. signature(for data: DataProtocol) -> Hashes data with SHA256 first, then signs
            // 2. signature(for digest: Digest) -> Signs the digest directly (no extra hashing)
            //
            // We need method #2 since we've already computed the double-SHA256 sighash.
            // To use it, we must convert our CryptoKit digest to P256K's SHA256Digest type.
            let hashBytes = Array(signatureHash)  // Convert CryptoKit.SHA256.Digest to [UInt8]
            print("🔍 ClientSideSigner: Signature hash computed: \(hashBytes.map { String(format: "%02x", $0) }.joined())")
            
            // Sign and store both key and signature for verification
            // SHA256Digest/HashDigest is a top-level typealias in the P256K module
            #if canImport(P256K)
            let digestForSigning = SHA256Digest(hashBytes)  // Create P256K-compatible digest (top-level type)
            let signingKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
            let signature = try signingKey.signature(for: digestForSigning)  // Uses DigestSigner - no extra hashing!
            let publicKeyForVerification = signingKey.publicKey
            #elseif canImport(secp256k1)
            let digestForSigning = SHA256Digest(hashBytes)  // Create secp256k1-compatible digest (top-level type)
            let signingKey = try secp256k1.Signing.PrivateKey(dataRepresentation: privateKey)
            let signature = try signingKey.signature(for: digestForSigning)  // Uses DigestSigner - no extra hashing!
            let publicKeyForVerification = signingKey.publicKey
            #else
            throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "No secp256k1 library available"])
            #endif
            
            // CRITICAL FIX: Use the library's DER representation directly!
            // The library handles proper serialization internally.
            // dataRepresentation is the INTERNAL secp256k1 format, NOT standard r||s
            // derRepresentation gives us proper DER-encoded signature
            let sigDataDER = try signature.derRepresentation
            print("🔍 ClientSideSigner: DER signature from library: \(sigDataDER.count) bytes")
            print("   DER hex: \(sigDataDER.map { String(format: "%02x", $0) }.joined())")
            
            // Verify DER format is correct (should start with 0x30)
            guard sigDataDER.first == 0x30 else {
                throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid DER signature format"])
            }
            
            // IMPORTANT: libsecp256k1 already produces low-s signatures by default
            // So we don't need manual low-s normalization
            print("✅ ClientSideSigner: Using library's DER signature (low-s already normalized)")
            
            // Append SIGHASH byte
            var sigData = sigDataDER
            sigData.append(sighashType)
            print("🔍 ClientSideSigner: Signature with SIGHASH length: \(sigData.count) bytes")
            
            // Get public key (compressed)
            let publicKey = signingKey.publicKey.dataRepresentation // 33 bytes compressed
            print("🔍 ClientSideSigner: Public key (hex): \(publicKey.map { String(format: "%02x", $0) }.joined())")
            print("🔍 ClientSideSigner: Public key length: \(publicKey.count) bytes")
            
            // Verify public key hash matches scriptPubKey hash (critical for OP_EQUALVERIFY)
            let publicKeyHash = RIPEMD160.hash(Data(SHA256.hash(data: publicKey)))
            let scriptPubKeyHash = extractPubKeyHash(from: scriptPubKey)
            if publicKeyHash != scriptPubKeyHash {
                print("❌ ClientSideSigner: CRITICAL - Public key hash mismatch!")
                print("   Public key: \(publicKey.map { String(format: "%02x", $0) }.joined().prefix(20))...")
                print("   Public key hash: \(publicKeyHash.map { String(format: "%02x", $0) }.joined())")
                print("   ScriptPubKey hash: \(scriptPubKeyHash.map { String(format: "%02x", $0) }.joined())")
                print("   This will cause OP_EQUALVERIFY to fail!")
                throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Public key hash does not match scriptPubKey hash"])
            }
            print("✅ ClientSideSigner: Public key hash matches scriptPubKey hash")
            
            // Verify signature before using it (using the same key that created it)
            // NOTE: Use the same digest type for verification, matching how we signed
            #if canImport(P256K)
            let isValid = publicKeyForVerification.isValidSignature(signature, for: digestForSigning)
            #elseif canImport(secp256k1)
            let isValid = publicKeyForVerification.isValidSignature(signature, for: digestForSigning)
            #else
            let isValid = true // Skip verification if library not available
            #endif
            
            if !isValid {
                print("❌ ClientSideSigner: CRITICAL - Signature verification failed!")
                print("   Signature hash: \(hashBytes.map { String(format: "%02x", $0) }.joined())")
                print("   Public key: \(publicKey.map { String(format: "%02x", $0) }.joined())")
                throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Signature verification failed - signature does not match hash"])
            }
            print("✅ ClientSideSigner: Signature verified successfully before adding to transaction")
            
            // Build scriptSig: <signature> <public_key>
            let scriptSig = buildScriptSig(signature: sigData, publicKey: publicKey)
            
            // CRITICAL: Verify the scriptSig format is correct
            // ScriptSig should be: [signature_length] [signature] [pubkey_length] [pubkey]
            // Parse it back to verify
            var scriptSigOffset = 0
            var parsedSignature: Data?
            var parsedPublicKey: Data?
            
            if scriptSigOffset < scriptSig.count {
                let sigLen = Int(scriptSig[scriptSigOffset])
                scriptSigOffset += 1
                if scriptSigOffset + sigLen <= scriptSig.count {
                    parsedSignature = scriptSig.subdata(in: scriptSigOffset..<scriptSigOffset + sigLen)
                    scriptSigOffset += sigLen
                }
            }
            
            if scriptSigOffset < scriptSig.count {
                let pubkeyLen = Int(scriptSig[scriptSigOffset])
                scriptSigOffset += 1
                if scriptSigOffset + pubkeyLen <= scriptSig.count {
                    parsedPublicKey = scriptSig.subdata(in: scriptSigOffset..<scriptSigOffset + pubkeyLen)
                }
            }
            
            // Verify the parsed public key matches what we used
            if let parsedPubkey = parsedPublicKey {
                let parsedPubkeyHash = RIPEMD160.hash(Data(SHA256.hash(data: parsedPubkey)))
                if parsedPubkeyHash != publicKeyHash {
                    print("❌ ClientSideSigner: CRITICAL - Parsed public key hash from scriptSig doesn't match!")
                    print("   Parsed public key: \(parsedPubkey.map { String(format: "%02x", $0) }.joined())")
                    print("   Parsed public key hash: \(parsedPubkeyHash.map { String(format: "%02x", $0) }.joined())")
                    print("   Expected hash: \(publicKeyHash.map { String(format: "%02x", $0) }.joined())")
                    print("   This will cause OP_EQUALVERIFY to fail!")
                } else {
                    print("✅ ClientSideSigner: Parsed public key from scriptSig matches expected hash")
                }
            }
            
            // Log scriptSig for debugging
            print("🔍 ClientSideSigner: Built scriptSig:")
            print("   Length: \(scriptSig.count) bytes")
            print("   Hex (FULL): \(scriptSig.map { String(format: "%02x", $0) }.joined())")
            print("   Signature length: \(sigData.count) bytes")
            print("   Public key length: \(publicKey.count) bytes")
            if let parsedSig = parsedSignature {
                print("   Parsed signature (first 20): \(parsedSig.prefix(20).map { String(format: "%02x", $0) }.joined())...")
            }
            if let parsedPubkey = parsedPublicKey {
                print("   Parsed public key: \(parsedPubkey.map { String(format: "%02x", $0) }.joined())")
            }
            
            // Update transaction input with scriptSig
            signedTx.inputs[index].scriptSig = scriptSig
        }
        
        // CRITICAL VERIFICATION: Verify the signed transaction (minus scriptSig) matches what we hashed
        // The daemon will recompute the hash from the signed transaction, so they must match
        print("🔍 ClientSideSigner: Verifying signed transaction matches hash computation...")
        for (idx, input) in signedTx.inputs.enumerated() {
            // Create a copy of the signed transaction with empty scriptSig for this input
            var txForVerification = signedTx
            txForVerification.inputs[idx].scriptSig = Data()
            
            // Recompute the signature hash for this input
            let scriptPubKey = Data(hexString: inputs[idx].scriptPubKey) ?? Data()
            let verificationHash = try computeSignatureHash(
                transaction: txForVerification,
                inputIndex: idx,
                scriptPubKey: scriptPubKey,
                amount: inputs[idx].amount,
                sighashType: sighashType
            )
            
            // Compare with the hash we used for signing
            let originalHash = try computeSignatureHash(
                transaction: tx,
                inputIndex: idx,
                scriptPubKey: scriptPubKey,
                amount: inputs[idx].amount,
                sighashType: sighashType
            )
            
            if Data(verificationHash) != Data(originalHash) {
                print("❌ ClientSideSigner: CRITICAL - Signed transaction hash mismatch!")
                print("   Original hash: \(Data(originalHash).map { String(format: "%02x", $0) }.joined())")
                print("   Verification hash: \(Data(verificationHash).map { String(format: "%02x", $0) }.joined())")
                print("   This will cause daemon verification to fail!")
            } else {
                print("✅ ClientSideSigner: Signed transaction hash matches original hash for input \(idx)")
            }
        }
        
        // Log the full signed transaction before serialization
        print("🔍 ClientSideSigner: Signed transaction details:")
        print("   Version: \(signedTx.version)")
        print("   Input count: \(signedTx.inputs.count)")
        for (idx, input) in signedTx.inputs.enumerated() {
            print("   Input \(idx): prevTxid=\(input.prevTxid.map { String(format: "%02x", $0) }.joined().prefix(16))..., prevVout=\(input.prevVout), scriptSig length=\(input.scriptSig.count), sequence=\(input.sequence)")
        }
        print("   Output count: \(signedTx.outputs.count)")
        for (idx, output) in signedTx.outputs.enumerated() {
            print("   Output \(idx): value=\(output.value) satoshis (\(Double(output.value) / 100_000_000.0) TLS), scriptPubKey length=\(output.scriptPubKey.count)")
        }
        print("   Locktime: \(signedTx.locktime)")
        
        // Serialize signed transaction
        let serializedHex = try serializeTransaction(signedTx)
        print("🔍 ClientSideSigner: Serialized transaction hex (first 200 chars): \(serializedHex.prefix(200))...")
        print("🔍 ClientSideSigner: Serialized transaction hex length: \(serializedHex.count) chars = \(serializedHex.count / 2) bytes")
        
        return serializedHex
    }
    
    // MARK: - Transaction Structure
    
    struct ParsedTransaction {
        var version: UInt32
        var inputs: [TransactionInputData]
        var outputs: [TransactionOutput]
        var locktime: UInt32
    }
    
    struct TransactionInputData {
        var prevTxid: Data // 32 bytes, reversed
        var prevVout: UInt32
        var scriptSig: Data // Will be set during signing
        var sequence: UInt32
    }
    
    struct TransactionOutput {
        var value: UInt64 // 8 bytes (satoshi)
        var scriptPubKey: Data
    }
    
    struct TransactionInput {
        let txid: String
        let vout: Int
        let scriptPubKey: String
        let amount: Double // In TLS (will be converted to satoshi)
    }
    
    // MARK: - Transaction Parsing
    
    private func parseTransaction(hex: String) throws -> ParsedTransaction {
        guard let data = Data(hexString: hex) else {
            throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid hex string"])
        }
        
        var offset = 0
        
        // Version (4 bytes, little-endian)
        guard offset + 4 <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing version"]) }
        let versionBytes = data.subdata(in: offset..<offset+4)
        let version = versionBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4
        
        // Input count (varint)
        let (inputCount, inputCountSize) = try readVarInt(data: data, offset: offset)
        offset += inputCountSize
        
        var inputs: [TransactionInputData] = []
        for _ in 0..<inputCount {
            // Previous txid (32 bytes, reversed)
            guard offset + 32 <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing prevTxid"]) }
            let prevTxid = data.subdata(in: offset..<offset+32)
            offset += 32
            
            // Previous vout (4 bytes, little-endian)
            guard offset + 4 <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing prevVout"]) }
            let prevVoutBytes = data.subdata(in: offset..<offset+4)
            let prevVout = prevVoutBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            offset += 4
            
            // ScriptSig length (varint)
            let (scriptSigLen, scriptSigLenSize) = try readVarInt(data: data, offset: offset)
            offset += scriptSigLenSize
            
            // ScriptSig (empty for unsigned transactions)
            guard offset + Int(scriptSigLen) <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing scriptSig"]) }
            let scriptSig = data.subdata(in: offset..<offset+Int(scriptSigLen))
            offset += Int(scriptSigLen)
            
            // Sequence (4 bytes, little-endian)
            guard offset + 4 <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing sequence"]) }
            let sequenceBytes = data.subdata(in: offset..<offset+4)
            let sequence = sequenceBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            offset += 4
            
            inputs.append(TransactionInputData(
                prevTxid: prevTxid,
                prevVout: prevVout,
                scriptSig: scriptSig,
                sequence: sequence
            ))
        }
        
        // Output count (varint)
        let (outputCount, outputCountSize) = try readVarInt(data: data, offset: offset)
        offset += outputCountSize
        
        var outputs: [TransactionOutput] = []
        for _ in 0..<outputCount {
            // Value (8 bytes, little-endian)
            guard offset + 8 <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing value"]) }
            let valueBytes = data.subdata(in: offset..<offset+8)
            let value = valueBytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
            offset += 8
            
            // ScriptPubKey length (varint)
            let (scriptPubKeyLen, scriptPubKeyLenSize) = try readVarInt(data: data, offset: offset)
            offset += scriptPubKeyLenSize
            
            // ScriptPubKey
            guard offset + Int(scriptPubKeyLen) <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing scriptPubKey"]) }
            let scriptPubKey = data.subdata(in: offset..<offset+Int(scriptPubKeyLen))
            offset += Int(scriptPubKeyLen)
            
            outputs.append(TransactionOutput(
                value: value,
                scriptPubKey: scriptPubKey
            ))
        }
        
        // Locktime (4 bytes, little-endian)
        guard offset + 4 <= data.count else { throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid transaction: missing locktime"]) }
        let locktimeBytes = data.subdata(in: offset..<offset+4)
        let locktime = locktimeBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        
        return ParsedTransaction(
            version: version,
            inputs: inputs,
            outputs: outputs,
            locktime: locktime
        )
    }
    
    // MARK: - SignatureHash Computation
    
    /// Select the appropriate sighash algorithm based on the script type.
    private func computeSignatureHash(
        transaction: ParsedTransaction,
        inputIndex: Int,
        scriptPubKey: Data,
        amount: Double,
        sighashType: UInt8
    ) throws -> CryptoKit.SHA256.Digest {
        let sigVersion = determineSigVersion(scriptPubKey: scriptPubKey)
        switch sigVersion {
        case .legacy:
            print("🔍 ClientSideSigner: Computing LEGACY sighash (SIGVERSION_BASE)")
            return try computeLegacySignatureHash(
                transaction: transaction,
                inputIndex: inputIndex,
                scriptPubKey: scriptPubKey,
                sighashType: sighashType
            )
        case .witnessV0:
            let amountSats = UInt64(amount * 100_000_000)
            print("🔍 ClientSideSigner: Computing BIP143 sighash (SIGVERSION_WITNESS_V0)")
            return try computeBIP143SignatureHash(
                transaction: transaction,
                inputIndex: inputIndex,
                scriptPubKey: scriptPubKey,
                amount: amountSats,
                sighashType: sighashType
            )
        }
    }
    
    private func determineSigVersion(scriptPubKey: Data) -> SigVersion {
        // P2WPKH: 0x00 0x14 <20-byte-hash>
        if scriptPubKey.count == 22,
           scriptPubKey[0] == 0x00,
           scriptPubKey[1] == 0x14 {
            return .witnessV0
        }
        // P2WSH: 0x00 0x20 <32-byte-hash>
        if scriptPubKey.count == 34,
           scriptPubKey[0] == 0x00,
           scriptPubKey[1] == 0x20 {
            return .witnessV0
        }
        return .legacy
    }
    
    private func computeLegacySignatureHash(
        transaction: ParsedTransaction,
        inputIndex: Int,
        scriptPubKey: Data,
        sighashType: UInt8
    ) throws -> CryptoKit.SHA256.Digest {
        let baseType = sighashType & 0x1f
        let hashSingle = baseType == SIGHASH_SINGLE
        let hashNone = baseType == SIGHASH_NONE
        let anyoneCanPay = (sighashType & SIGHASH_ANYONECANPAY) != 0
        
        if hashSingle && inputIndex >= transaction.outputs.count {
            throw NSError(
                domain: "ClientSideSigner",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "SIGHASH_SINGLE invalid for input \(inputIndex)"]
            )
        }
        
        print("   Input index: \(inputIndex)")
        print("   SighashType: 0x\(String(format: "%02x", sighashType))")
        
        var buffer = Data()
        appendLittleEndian(transaction.version, to: &buffer)
        
        let inputCount = anyoneCanPay ? 1 : transaction.inputs.count
        writeVarInt(buffer: &buffer, value: UInt64(inputCount))
        
        let scriptCodeSection = serializedScriptCode(scriptPubKey: scriptPubKey)
        
        for idx in 0..<inputCount {
            let actualIndex = anyoneCanPay ? inputIndex : idx
            let input = transaction.inputs[actualIndex]
            buffer.append(input.prevTxid)
            appendLittleEndian(input.prevVout, to: &buffer)
            
            if actualIndex == inputIndex {
                buffer.append(scriptCodeSection)
            } else {
                writeVarInt(buffer: &buffer, value: 0)
            }
            
            let sequence: UInt32
            if actualIndex != inputIndex && (hashSingle || hashNone) {
                sequence = 0
            } else {
                sequence = input.sequence
            }
            appendLittleEndian(sequence, to: &buffer)
        }
        
        if hashNone {
            writeVarInt(buffer: &buffer, value: 0)
        } else if hashSingle {
            writeVarInt(buffer: &buffer, value: UInt64(inputIndex + 1))
            for outputIndex in 0...inputIndex {
                if outputIndex == inputIndex {
                    serializeOutput(buffer: &buffer, output: transaction.outputs[outputIndex])
                } else {
                    serializeNullOutput(buffer: &buffer)
                }
            }
        } else {
            writeVarInt(buffer: &buffer, value: UInt64(transaction.outputs.count))
            for output in transaction.outputs {
                serializeOutput(buffer: &buffer, output: output)
            }
        }
        
        appendLittleEndian(transaction.locktime, to: &buffer)
        appendLittleEndian(UInt32(sighashType), to: &buffer)
        
        print("   Legacy preimage length: \(buffer.count) bytes")
        print("   Legacy preimage (first 100): \(buffer.prefix(100).map { String(format: "%02x", $0) }.joined())...")
        
        let firstHash = CryptoKit.SHA256.hash(data: buffer)
        let finalHash = CryptoKit.SHA256.hash(data: Data(firstHash))
        print("   Legacy hash: \(Data(finalHash).map { String(format: "%02x", $0) }.joined())")
        return finalHash
    }
    
    private func computeBIP143SignatureHash(
        transaction: ParsedTransaction,
        inputIndex: Int,
        scriptPubKey: Data,
        amount: UInt64,
        sighashType: UInt8
    ) throws -> CryptoKit.SHA256.Digest {
        let baseType = sighashType & 0x1f
        let hashSingle = baseType == SIGHASH_SINGLE
        let hashNone = baseType == SIGHASH_NONE
        let hashAnyoneCanPay = (sighashType & SIGHASH_ANYONECANPAY) != 0
        
        var buffer = Data()
        appendLittleEndian(transaction.version, to: &buffer)
        
        let hashPrevouts: Data
        if hashAnyoneCanPay {
            hashPrevouts = Data(repeating: 0, count: 32)
        } else {
            var prevouts = Data()
            for input in transaction.inputs {
                prevouts.append(input.prevTxid)
                appendLittleEndian(input.prevVout, to: &prevouts)
            }
            hashPrevouts = doubleSHA256(prevouts)
        }
        buffer.append(hashPrevouts)
        print("   hashPrevouts: \(hashPrevouts.map { String(format: "%02x", $0) }.joined())")
        
        let hashSequence: Data
        if hashAnyoneCanPay || hashSingle || hashNone {
            hashSequence = Data(repeating: 0, count: 32)
        } else {
            var sequences = Data()
            for input in transaction.inputs {
                appendLittleEndian(input.sequence, to: &sequences)
            }
            hashSequence = doubleSHA256(sequences)
        }
        buffer.append(hashSequence)
        print("   hashSequence: \(hashSequence.map { String(format: "%02x", $0) }.joined())")
        
        let input = transaction.inputs[inputIndex]
        buffer.append(input.prevTxid)
        appendLittleEndian(input.prevVout, to: &buffer)
        
        writeVarInt(buffer: &buffer, value: UInt64(scriptPubKey.count))
        buffer.append(scriptPubKey)
        
        appendLittleEndian(amount, to: &buffer)
        appendLittleEndian(input.sequence, to: &buffer)
        
        let hashOutputs: Data
        if hashSingle {
            if inputIndex < transaction.outputs.count {
                var single = Data()
                let output = transaction.outputs[inputIndex]
                serializeOutput(buffer: &single, output: output)
                hashOutputs = doubleSHA256(single)
            } else {
                hashOutputs = Data(repeating: 0, count: 32)
            }
        } else if hashNone {
            hashOutputs = Data(repeating: 0, count: 32)
        } else {
            var outputs = Data()
            for output in transaction.outputs {
                serializeOutput(buffer: &outputs, output: output)
            }
            hashOutputs = doubleSHA256(outputs)
        }
        buffer.append(hashOutputs)
        print("   hashOutputs: \(hashOutputs.map { String(format: "%02x", $0) }.joined())")
        
        appendLittleEndian(transaction.locktime, to: &buffer)
        appendLittleEndian(UInt32(sighashType), to: &buffer)
        
        let firstHash = CryptoKit.SHA256.hash(data: buffer)
        let finalHash = CryptoKit.SHA256.hash(data: Data(firstHash))
        print("   Witness preimage length: \(buffer.count) bytes")
        print("   Witness hash: \(Data(finalHash).map { String(format: "%02x", $0) }.joined())")
        return finalHash
    }
    
    private func serializedScriptCode(scriptPubKey: Data) -> Data {
        // Strip OP_CODESEPARATOR (0xab) to mirror Core
        var cleaned = Data()
        for byte in scriptPubKey where byte != 0xab {
            cleaned.append(byte)
        }
        var serialized = Data()
        writeVarInt(buffer: &serialized, value: UInt64(cleaned.count))
        serialized.append(cleaned)
        return serialized
    }
    
    private func doubleSHA256(_ data: Data) -> Data {
        let first = CryptoKit.SHA256.hash(data: data)
        let second = CryptoKit.SHA256.hash(data: Data(first))
        return Data(second)
    }
    
    // NEW: Serialize input directly from transaction (matching Core Wallet's approach)
    // This function serializes an input from the transaction, where scriptSig has already been set
    // For the signing input, scriptSig = scriptPubKey (scriptCode)
    // For other inputs, scriptSig = empty
    private func serializeInputFromTransaction(buffer: inout Data, transaction: ParsedTransaction, inputIndex: Int, signingInputIndex: Int, hashSingle: Bool, hashNone: Bool) {
        let input = transaction.inputs[inputIndex]
        
        // Previous txid (32 bytes, reversed)
        buffer.append(input.prevTxid)
        
        // Previous vout (4 bytes, little-endian)
        buffer.append(contentsOf: withUnsafeBytes(of: input.prevVout.littleEndian) { Data($0) })
        
        // ScriptSig length (varint) - this is the scriptCode (scriptPubKey) for signing input, empty for others
        // CRITICAL: This matches Core Wallet's behavior where scriptCode is set as scriptSig
        writeVarInt(buffer: &buffer, value: UInt64(input.scriptSig.count))
        buffer.append(input.scriptSig)
        
        // Sequence (4 bytes, little-endian)
        // For non-signing inputs with SIGHASH_SINGLE or SIGHASH_NONE, use 0
        let sequence: UInt32
        if inputIndex != signingInputIndex && (hashSingle || hashNone) {
            // This is a non-signing input with SIGHASH_SINGLE or SIGHASH_NONE, use 0 sequence
            sequence = 0
        } else {
            sequence = input.sequence
        }
        buffer.append(contentsOf: withUnsafeBytes(of: sequence.littleEndian) { Data($0) })
    }
    
    // OLD: Keep for backward compatibility (not used anymore)
    private func serializeInput(buffer: inout Data, transaction: ParsedTransaction, inputIndex: Int, scriptPubKey: Data, hashSingle: Bool, hashNone: Bool, isSigningInput: Bool = true) {
        let input = transaction.inputs[inputIndex]
        
        // Previous txid (32 bytes, reversed)
        buffer.append(input.prevTxid)
        
        // Previous vout (4 bytes, little-endian)
        buffer.append(contentsOf: withUnsafeBytes(of: input.prevVout.littleEndian) { Data($0) })
        
        // ScriptPubKey length (varint) - this is the scriptCode
        // For non-signing inputs, use empty script
        if isSigningInput {
            writeVarInt(buffer: &buffer, value: UInt64(scriptPubKey.count))
            buffer.append(scriptPubKey)
        } else {
            writeVarInt(buffer: &buffer, value: 0)
        }
        
        // Sequence (4 bytes, little-endian)
        // For non-signing inputs with SIGHASH_SINGLE or SIGHASH_NONE, use 0
        let sequence: UInt32
        if !isSigningInput && (hashSingle || hashNone) {
            sequence = 0
        } else {
            sequence = input.sequence
        }
        buffer.append(contentsOf: withUnsafeBytes(of: sequence.littleEndian) { Data($0) })
    }
    
    private func serializeOutput(buffer: inout Data, output: TransactionOutput) {
        // Value (8 bytes, little-endian)
        appendLittleEndian(output.value, to: &buffer)
        
        // ScriptPubKey length (varint)
        writeVarInt(buffer: &buffer, value: UInt64(output.scriptPubKey.count))
        
        // ScriptPubKey
        buffer.append(output.scriptPubKey)
    }
    
    private func serializeNullOutput(buffer: inout Data) {
        appendLittleEndian(UInt64.max, to: &buffer)
        writeVarInt(buffer: &buffer, value: 0)
    }
    
    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to buffer: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { rawBuffer in
            buffer.append(contentsOf: rawBuffer)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Extract public key hash from P2PKH scriptPubKey
    private func extractPubKeyHash(from scriptPubKey: Data) -> Data {
        // P2PKH format: 76a914<20-byte-hash>88ac
        guard scriptPubKey.count >= 25,
              scriptPubKey[0] == 0x76, // OP_DUP
              scriptPubKey[1] == 0xa9, // OP_HASH160
              scriptPubKey[2] == 0x14, // Push 20 bytes
              scriptPubKey[23] == 0x88, // OP_EQUALVERIFY
              scriptPubKey[24] == 0xac else { // OP_CHECKSIG
            return Data()
        }
        // Extract 20-byte hash (bytes 3-22)
        return scriptPubKey.subdata(in: 3..<23)
    }
    
    // MARK: - ScriptSig Building
    
    /// Build scriptSig for P2PKH: <signature> <public_key>
    /// Format: [signature_length] [signature_bytes] [pubkey_length] [pubkey_bytes]
    private func buildScriptSig(signature: Data, publicKey: Data) -> Data {
        var scriptSig = Data()
        
        // CRITICAL: Verify signature length is reasonable (DER signatures are typically 70-72 bytes)
        if signature.count < 70 || signature.count > 73 {
            print("❌ ClientSideSigner: WARNING - Signature length is unusual: \(signature.count) bytes")
        }
        
        // Push signature (DER-encoded with SIGHASH byte)
        // Use OP_PUSHDATA1 if > 75 bytes, otherwise use direct push
        if signature.count <= 75 {
            scriptSig.append(UInt8(signature.count))
        } else if signature.count <= 255 {
            scriptSig.append(0x4c) // OP_PUSHDATA1
            scriptSig.append(UInt8(signature.count))
        } else {
            // Shouldn't happen for signatures, but handle it
            scriptSig.append(0x4d) // OP_PUSHDATA2
            scriptSig.append(contentsOf: withUnsafeBytes(of: UInt16(signature.count).littleEndian) { Data($0) })
        }
        scriptSig.append(signature)
        
        // CRITICAL: Verify public key is exactly 33 bytes (compressed)
        if publicKey.count != 33 {
            print("❌ ClientSideSigner: CRITICAL - Public key length is wrong: \(publicKey.count) bytes (expected 33)")
        }
        if let firstByte = publicKey.first, firstByte != 0x02 && firstByte != 0x03 {
            print("❌ ClientSideSigner: CRITICAL - Public key doesn't start with 0x02 or 0x03: \(String(format: "0x%02x", firstByte))")
        }
        
        // Push public key (33 bytes compressed)
        scriptSig.append(UInt8(publicKey.count)) // Always 33 bytes
        scriptSig.append(publicKey)
        
        // Verify the scriptSig can be parsed back correctly
        var offset = 0
        var parsedSigLen = 0
        var parsedPubkeyLen = 0
        
        // Parse signature length
        if offset < scriptSig.count {
            let firstByte = scriptSig[offset]
            if firstByte <= 75 {
                parsedSigLen = Int(firstByte)
                offset += 1
            } else if firstByte == 0x4c {
                offset += 1
                if offset < scriptSig.count {
                    parsedSigLen = Int(scriptSig[offset])
                    offset += 1
                }
            } else if firstByte == 0x4d {
                offset += 1
                if offset + 2 <= scriptSig.count {
                    let lenBytes = scriptSig.subdata(in: offset..<offset+2)
                    parsedSigLen = Int(lenBytes.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
                    offset += 2
                }
            }
        }
        
        // Verify signature length matches
        if parsedSigLen != signature.count {
            print("❌ ClientSideSigner: CRITICAL - Parsed signature length (\(parsedSigLen)) doesn't match actual (\(signature.count))")
        }
        
        // Skip signature bytes
        offset += parsedSigLen
        
        // Parse public key length
        if offset < scriptSig.count {
            parsedPubkeyLen = Int(scriptSig[offset])
            offset += 1
        }
        
        // Verify public key length matches
        if parsedPubkeyLen != publicKey.count {
            print("❌ ClientSideSigner: CRITICAL - Parsed public key length (\(parsedPubkeyLen)) doesn't match actual (\(publicKey.count))")
        }
        
        // Extract and verify public key
        if offset + parsedPubkeyLen <= scriptSig.count {
            let parsedPubkey = scriptSig.subdata(in: offset..<offset + parsedPubkeyLen)
            if parsedPubkey != publicKey {
                print("❌ ClientSideSigner: CRITICAL - Parsed public key doesn't match!")
                print("   Expected: \(publicKey.map { String(format: "%02x", $0) }.joined())")
                print("   Parsed: \(parsedPubkey.map { String(format: "%02x", $0) }.joined())")
            } else {
                print("✅ ClientSideSigner: scriptSig format verified - can be parsed correctly")
            }
        }
        
        return scriptSig
    }
    
    // MARK: - Transaction Serialization
    
    private func serializeTransaction(_ tx: ParsedTransaction) throws -> String {
        var buffer = Data()
        
        // Version (4 bytes, little-endian)
        buffer.append(contentsOf: withUnsafeBytes(of: tx.version.littleEndian) { Data($0) })
        
        // Input count (varint)
        writeVarInt(buffer: &buffer, value: UInt64(tx.inputs.count))
        
        // Inputs
        for input in tx.inputs {
            // Previous txid (32 bytes, reversed)
            buffer.append(input.prevTxid)
            
            // Previous vout (4 bytes, little-endian)
            buffer.append(contentsOf: withUnsafeBytes(of: input.prevVout.littleEndian) { Data($0) })
            
            // ScriptSig length (varint)
            writeVarInt(buffer: &buffer, value: UInt64(input.scriptSig.count))
            
            // ScriptSig
            buffer.append(input.scriptSig)
            
            // Sequence (4 bytes, little-endian)
            buffer.append(contentsOf: withUnsafeBytes(of: input.sequence.littleEndian) { Data($0) })
        }
        
        // Output count (varint)
        writeVarInt(buffer: &buffer, value: UInt64(tx.outputs.count))
        
        // Outputs
        for output in tx.outputs {
            // Value (8 bytes, little-endian)
            buffer.append(contentsOf: withUnsafeBytes(of: output.value.littleEndian) { Data($0) })
            
            // ScriptPubKey length (varint)
            writeVarInt(buffer: &buffer, value: UInt64(output.scriptPubKey.count))
            
            // ScriptPubKey
            buffer.append(output.scriptPubKey)
        }
        
        // Locktime (4 bytes, little-endian)
        buffer.append(contentsOf: withUnsafeBytes(of: tx.locktime.littleEndian) { Data($0) })
        
        return buffer.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - DER Signature Encoding
    
    /// Encode signature (r, s) in DER format
    private func encodeDERSignature(r: Data, s: Data) throws -> Data {
        // Remove leading zeros
        var rTrimmed = r
        while rTrimmed.count > 1 && rTrimmed.first == 0 {
            rTrimmed = rTrimmed.dropFirst()
        }
        // Ensure first byte is < 0x80 (not negative)
        if rTrimmed.first! >= 0x80 {
            rTrimmed = Data([0x00]) + rTrimmed
        }
        
        var sTrimmed = s
        while sTrimmed.count > 1 && sTrimmed.first == 0 {
            sTrimmed = sTrimmed.dropFirst()
        }
        // Ensure first byte is < 0x80 (not negative)
        if sTrimmed.first! >= 0x80 {
            sTrimmed = Data([0x00]) + sTrimmed
        }
        
        // Build DER: 0x30 [length] 0x02 [r_length] [r] 0x02 [s_length] [s]
        var der = Data()
        der.append(0x30) // SEQUENCE
        
        // Calculate total length
        let rLen = rTrimmed.count
        let sLen = sTrimmed.count
        let totalLen = 2 + 1 + rLen + 2 + 1 + sLen // 0x02 + rLen + r + 0x02 + sLen + s
        
        if totalLen < 0x80 {
            der.append(UInt8(totalLen))
        } else if totalLen < 0x100 {
            der.append(0x81)
            der.append(UInt8(totalLen))
        } else {
            der.append(0x82)
            der.append(contentsOf: withUnsafeBytes(of: UInt16(totalLen).bigEndian) { Data($0) })
        }
        
        // r
        der.append(0x02) // INTEGER
        der.append(UInt8(rLen))
        der.append(rTrimmed)
        
        // s
        der.append(0x02) // INTEGER
        der.append(UInt8(sLen))
        der.append(sTrimmed)
        
        return der
    }
    
    // MARK: - VarInt Helpers
    
    private func readVarInt(data: Data, offset: Int) throws -> (value: UInt64, size: Int) {
        guard offset < data.count else {
            throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid varint: out of bounds"])
        }
        
        let firstByte = data[offset]
        
        if firstByte < 0xfd {
            return (UInt64(firstByte), 1)
        } else if firstByte == 0xfd {
            guard offset + 3 <= data.count else {
                throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid varint: incomplete 0xfd"])
            }
            let valueBytes = data.subdata(in: (offset + 1)..<(offset + 3))
            let value = valueBytes.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            return (UInt64(value), 3)
        } else if firstByte == 0xfe {
            guard offset + 5 <= data.count else {
                throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid varint: incomplete 0xfe"])
            }
            let valueBytes = data.subdata(in: (offset + 1)..<(offset + 5))
            let value = valueBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            return (UInt64(value), 5)
        } else { // 0xff
            guard offset + 9 <= data.count else {
                throw NSError(domain: "ClientSideSigner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid varint: incomplete 0xff"])
            }
            let valueBytes = data.subdata(in: (offset + 1)..<(offset + 9))
            let value = valueBytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
            return (value, 9)
        }
    }
    
    private func writeVarInt(buffer: inout Data, value: UInt64) {
        if value < 0xfd {
            buffer.append(UInt8(value))
        } else if value <= 0xffff {
            buffer.append(0xfd)
            buffer.append(contentsOf: withUnsafeBytes(of: UInt16(value).littleEndian) { Data($0) })
        } else if value <= 0xffffffff {
            buffer.append(0xfe)
            buffer.append(contentsOf: withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) })
        } else {
            buffer.append(0xff)
            buffer.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
        }
    }
}

