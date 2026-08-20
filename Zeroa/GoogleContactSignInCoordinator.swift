import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Google contact sign-in via ASWebAuthenticationSession + PKCE (no GoogleSignIn SDK).
/// Configure `GIDClientID` and matching reversed-client URL scheme in Info.plist.
@MainActor
final class GoogleContactSignInCoordinator: NSObject, ObservableObject {
    static let shared = GoogleContactSignInCoordinator()

    enum FlowResult {
        case createdNewWallet(address: String)
        case boundExistingWallet(address: String)
        case cancelled
        case failed(String)
    }

    @Published var isWorking = false

    static var clientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("REPLACE_") else { return nil }
        return trimmed
    }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
    static var reversedClientID: String? {
        if let explicit = Bundle.main.object(forInfoDictionaryKey: "GIDURLScheme") as? String {
            let t = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !t.hasPrefix("REPLACE_") { return t }
        }
        guard let clientID else { return nil }
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { return nil }
        let prefix = String(clientID.dropLast(".apps.googleusercontent.com".count))
        return "com.googleusercontent.apps.\(prefix)"
    }

    static var isConfigured: Bool {
        clientID != nil && reversedClientID != nil
    }

    private var authSession: ASWebAuthenticationSession?

    func continueWithGoogle(createIfNeeded: Bool = true) async -> FlowResult {
        guard let clientID = Self.clientID, let scheme = Self.reversedClientID else {
            return .failed("Add GIDClientID and GIDURLScheme (reversed client id) to Info.plist.")
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let sub = try await fetchGoogleSubject(clientID: clientID, callbackScheme: scheme)
            let outcome = await IdentityWalletBootstrap.bindOrCreate(
                provider: "google",
                stableSubjectId: sub,
                displayLabel: "Google",
                createIfNeeded: createIfNeeded
            )
            switch outcome {
            case .createdNewWallet(let a): return .createdNewWallet(address: a)
            case .boundExistingWallet(let a): return .boundExistingWallet(address: a)
            case .failed(let m): return .failed(m)
            }
        } catch let err as CancellationError {
            return .cancelled
        } catch {
            let ns = error as NSError
            if ns.domain == ASWebAuthenticationSessionErrorDomain,
               ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                return .cancelled
            }
            return .failed(error.localizedDescription)
        }
    }

    private func fetchGoogleSubject(clientID: String, callbackScheme: String) async throws -> String {
        let verifier = pkceVerifier()
        let challenge = pkceChallenge(verifier: verifier)
        let redirectURI = "\(callbackScheme):/oauth2redirect/google"
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let authURL = comps.url else {
            throw NSError(domain: "ZeroaGoogle", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad auth URL"])
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let url else {
                    cont.resume(throwing: NSError(domain: "ZeroaGoogle", code: 2, userInfo: [NSLocalizedDescriptionKey: "No callback URL"]))
                    return
                }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.authSession = session
            if !session.start() {
                cont.resume(throwing: NSError(domain: "ZeroaGoogle", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not start Google sign-in"]))
            }
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(domain: "ZeroaGoogle", code: 4, userInfo: [NSLocalizedDescriptionKey: "No authorization code from Google"])
        }

        let idToken = try await exchangeCode(
            code: code,
            clientID: clientID,
            redirectURI: redirectURI,
            verifier: verifier
        )
        return try parseJWTSubject(idToken)
    }

    private func exchangeCode(code: String, clientID: String, redirectURI: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code=\(code.urlQueryEncoded)",
            "client_id=\(clientID.urlQueryEncoded)",
            "redirect_uri=\(redirectURI.urlQueryEncoded)",
            "grant_type=authorization_code",
            "code_verifier=\(verifier.urlQueryEncoded)"
        ].joined(separator: "&")
        req.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "token exchange failed"
            throw NSError(domain: "ZeroaGoogle", code: 5, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw NSError(domain: "ZeroaGoogle", code: 6, userInfo: [NSLocalizedDescriptionKey: "No id_token in Google response"])
        }
        return idToken
    }

    private func parseJWTSubject(_ jwt: String) throws -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            throw NSError(domain: "ZeroaGoogle", code: 7, userInfo: [NSLocalizedDescriptionKey: "Malformed id_token"])
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String,
              !sub.isEmpty else {
            throw NSError(domain: "ZeroaGoogle", code: 8, userInfo: [NSLocalizedDescriptionKey: "No sub in id_token"])
        }
        return sub
    }

    private func pkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func pkceChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleContactSignInCoordinator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
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

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
