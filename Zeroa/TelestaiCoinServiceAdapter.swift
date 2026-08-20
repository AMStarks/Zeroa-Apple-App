import Foundation

/// Bridges the Telestai-specific `TLSBlockchainService` to the generic `CoinServiceProtocol`
/// so it can participate in the multi-coin wallet/transaction flows.
final class TelestaiCoinServiceAdapter: CoinServiceProtocol {
    let coinType: CoinType = .telestai

    private let tlsService = TLSBlockchainService.shared
    private let walletService = WalletService.shared

    var isConnected: Bool {
        get async {
            await tlsService.checkConnection()
        }
    }

    var lastBlockHeight: Int {
        get async {
            await MainActor.run { tlsService.lastBlockHeight }
        }
    }

    func initialize() async {
        _ = await tlsService.checkConnection()
    }

    func deriveAddress(from mnemonic: String) async -> (Bool, String?) {
        do {
            let derived = try walletService.deriveWalletForPath(
                mnemonic: mnemonic,
                account: 0,
                change: 0,
                index: 0
            )
            return (true, derived.address)
        } catch {
            print("⚠️ TelestaiCoinServiceAdapter: Unable to derive address - \(error.localizedDescription)")
            return (false, nil)
        }
    }

    func getBalance(address: String) async -> WalletBalance {
        if let info = await tlsService.getAddressInfo(address: address) {
            let confirmed = max(0, info.balance)
            return WalletBalance(
                coinType: .telestai,
                confirmed: confirmed,
                unconfirmed: 0,
                total: confirmed,
                lastUpdated: Date()
            )
        }

        return WalletBalance(
            coinType: .telestai,
            confirmed: 0,
            unconfirmed: 0,
            total: 0,
            lastUpdated: Date()
        )
    }

    func sendTransaction(request: SendTransactionRequest) async -> SendTransactionResponse {
        let response = await tlsService.sendPayment(
            toAddress: request.toAddress,
            amount: request.amount,
            message: nil,
            messageType: nil
        )

        return SendTransactionResponse(
            success: response.success,
            txid: response.txid,
            error: response.error,
            fee: response.error == nil ? request.fee : nil,
            confirmations: response.blockHeight != nil ? 1 : 0
        )
    }

    func getTransactionHistory(address: String) async -> [WalletTransaction] {
        // Keep the core Telestai service refreshed so we leverage its multi-address aggregation.
        await tlsService.refreshBalance()
        let transactions = await MainActor.run { tlsService.recentTransactions }
        return transactions.map { mapTelestaiTransaction($0) }
    }

    func checkNetworkStatus() async -> Bool {
        await tlsService.checkConnection()
    }

    func estimateFee(priority: SendTransactionRequest.TransactionPriority) async -> Double {
        // Rough heuristic until Telestai exposes per-priority fee estimates.
        let defaultInputs = 2
        let defaultOutputs = 2
        let size = FeeEstimationService.shared.estimateTransactionSize(
            inputCount: defaultInputs,
            outputCount: defaultOutputs
        )
        let baseFee = await FeeEstimationService.shared.estimateFee(transactionSizeBytes: size)

        switch priority {
        case .low:
            return baseFee * 0.75
        case .medium:
            return baseFee
        case .high:
            return baseFee * 1.5
        }
    }

    func clear() async {
        // TLS service maintains its own caches; nothing to clear here yet.
    }

    // MARK: - Helpers

    private func mapTelestaiTransaction(_ tx: TLSTransaction) -> WalletTransaction {
        let lowerType = tx.type.lowercased()
        let kind: WalletTransaction.TransactionType = lowerType == "send" ? .send : .receive
        let amount = kind == .send ? -abs(tx.amount) : abs(tx.amount)
        let status: WalletTransaction.TransactionStatus = tx.confirmations > 0 ? .confirmed : .pending
        let date = Date(timeIntervalSince1970: TimeInterval(tx.timestamp))

        return WalletTransaction(
            coinType: .telestai,
            txid: tx.txid,
            amount: amount,
            fee: tx.fee,
            confirmations: tx.confirmations,
            timestamp: date,
            type: kind,
            fromAddress: tx.from,
            toAddress: tx.to,
            blockHeight: nil,
            status: status
        )
    }
}

