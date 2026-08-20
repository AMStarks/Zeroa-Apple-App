import Foundation

struct LASKOAuthSession {
    let tlsAddress: String
    let sessionToken: String
    let signature: String
    let canonicalMessage: String?
    let signatureBase64: String?
    let pubkeyCompressedHex: String?
    let requestNonce: String?
    let timestamp: Int64
    let expiresAt: Int64
    let permissions: [String]
}

struct LegacyPostSignature {
    let signature: String
    let tlsAddress: String
    let timestamp: Int64
    let content: String
    let sessionToken: String
} 