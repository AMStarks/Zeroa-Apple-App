import Foundation

/// Shared on-device wallet create / bind used by Apple + Google contact flows.
enum IdentityWalletBootstrap {
    enum Outcome {
        case createdNewWallet(address: String)
        case boundExistingWallet(address: String)
        case failed(String)
    }

    @MainActor
    static func bindOrCreate(
        provider: String,
        stableSubjectId: String,
        displayLabel: String,
        createIfNeeded: Bool
    ) async -> Outcome {
        let wallet = WalletService.shared

        if let existing = wallet.loadAddress(), wallet.keychain.read(key: "wallet_mnemonic") != nil {
            do {
                try ContactBindingStore.shared.bind(
                    provider: provider,
                    stableSubjectId: stableSubjectId,
                    tlsAddress: existing,
                    displayLabel: displayLabel
                )
                return .boundExistingWallet(address: existing)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        guard createIfNeeded else {
            return .failed("No local Zeroa identity. Create an account or enter your recovery phrase.")
        }

        let mnemonic = wallet.generateMnemonic()
        let address: String
        do {
            address = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                wallet.importMnemonic(mnemonic) { success, derived in
                    if success, let derived {
                        cont.resume(returning: derived)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "ZeroaIdentity",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create local wallet"]
                        ))
                    }
                }
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        do {
            try ContactBindingStore.shared.bind(
                provider: provider,
                stableSubjectId: stableSubjectId,
                tlsAddress: address,
                displayLabel: displayLabel
            )
        } catch {
            return .failed(error.localizedDescription)
        }

        BackupStatusStore.markCreatedWithoutCeremony()
        AppGroupsService.shared.setProfileActive(true)
        AppGroupsService.shared.storeTLSAddress(address)
        return .createdNewWallet(address: address)
    }
}
