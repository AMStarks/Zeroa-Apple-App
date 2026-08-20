import Foundation

/// Telestai network for Zeroa. Production default is mainnet (Cryptoscope + Halo RPC).
/// Enable TestNet with UserDefaults `tls.useTestnet` = true (never the App Store default).
/// TestNet targets Core 3.0.1 (Meraki) soak on Optimus.
enum TLSNetwork: String {
    case mainnet
    case testnet

    /// UserDefaults key for the TestNet toggle (Settings → Network).
    static let useTestnetDefaultsKey = "tls.useTestnet"

    static var current: TLSNetwork {
        if UserDefaults.standard.bool(forKey: useTestnetDefaultsKey) {
            return .testnet
        }
        return .mainnet
    }

    /// Address / UTXO API (Cryptoscope shape on mainnet).
    var apiBaseURL: String {
        switch self {
        case .mainnet:
            return "https://cryptoscope.io/telestai/api"
        case .testnet:
            // Soak explorer (Optimus WAN). HTTP allowed via Info.plist ATS exception.
            return "http://114.73.210.115:4174/api"
        }
    }

    /// Tip / health (`/api/status` includes `algo`, `subversion`).
    var explorerBaseURL: String {
        switch self {
        case .mainnet:
            return "https://explorer.telestai.io"
        case .testnet:
            return "http://114.73.210.115:4174"
        }
    }

    /// JSON-RPC base used by `TLSRPCClient` when no override is set.
    /// Mainnet: Halo proxy. TestNet: optional `tls.testnetRpcBaseURL` (Halo-shaped `/rpc`);
    /// never reuse the mainnet LAN proxy (18787) — that node is 2.1.x mainnet.
    var rpcBaseURL: String {
        switch self {
        case .mainnet:
            return "https://halo.telestai.io/api/tls"
        case .testnet:
            if let override = UserDefaults.standard.string(forKey: "tls.testnetRpcBaseURL")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !override.isEmpty {
                var trimmed = override
                while trimmed.hasSuffix("/") { trimmed.removeLast() }
                return trimmed
            }
            // Unreachable sentinel until a TestNet Halo-shaped proxy is published.
            // Balance/history still work via explorerBaseURL; sends need the override.
            return "http://127.0.0.1:9"
        }
    }

    var displayName: String {
        switch self {
        case .mainnet: return "Mainnet"
        case .testnet: return "TestNet 3.0.1"
        }
    }

    /// Expected PoW label after Meraki activation (explorer `algo` field).
    var expectedAlgo: String {
        switch self {
        case .mainnet: return "KawPoW" // until mainnet Meraki height
        case .testnet: return "Meraki"
        }
    }
}
