import Foundation
import AuthenticationServices
import SwiftUI

/// Sign in with Apple → on-device key create/bind (LASKO Identity v0).
@MainActor
final class AppleContactSignInCoordinator: NSObject, ObservableObject {
    static let shared = AppleContactSignInCoordinator()

    @Published var isWorking = false
    @Published var lastError: String?

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    enum FlowResult {
        case createdNewWallet(address: String)
        case boundExistingWallet(address: String)
        case cancelled
        case failed(String)
    }

    func continueWithApple(createIfNeeded: Bool = true) async -> FlowResult {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            let credential = try await requestAppleCredential()
            let subject = credential.user
            guard !subject.isEmpty else {
                return .failed("Apple did not return a stable user id")
            }

            let outcome = await IdentityWalletBootstrap.bindOrCreate(
                provider: "apple",
                stableSubjectId: subject,
                displayLabel: "Apple ID",
                createIfNeeded: createIfNeeded
            )
            switch outcome {
            case .createdNewWallet(let a): return .createdNewWallet(address: a)
            case .boundExistingWallet(let a): return .boundExistingWallet(address: a)
            case .failed(let m): return .failed(m)
            }
        } catch let err as ASAuthorizationError where err.code == .canceled {
            return .cancelled
        } catch {
            lastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) in
            self.continuation = cont
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = []
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleContactSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let cont = continuation else { return }
            continuation = nil
            if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
                cont.resume(returning: cred)
            } else {
                cont.resume(throwing: NSError(domain: "ZeroaIdentity", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected Apple credential type"]))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            guard let cont = continuation else { return }
            continuation = nil
            cont.resume(throwing: error)
        }
    }
}

extension AppleContactSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        var anchor: ASPresentationAnchor?
        DispatchQueue.main.sync {
            anchor = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
        }
        return anchor ?? ASPresentationAnchor()
    }
}
