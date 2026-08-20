import SwiftUI

/// Welcome / create CTAs for IdP contact bind (Zeroa only).
struct IdPContactSignInSection: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var path: NavigationPath
    @StateObject private var apple = AppleContactSignInCoordinator.shared
    @StateObject private var google = GoogleContactSignInCoordinator.shared
    @State private var showAppleConsent = false
    @State private var showGoogleConsent = false
    @State private var errorText: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Or continue with")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Button {
                showAppleConsent = true
            } label: {
                HStack {
                    if apple.isWorking {
                        ProgressView()
                            .tint(DesignSystem.Colors.onPrimary)
                    } else {
                        Image(systemName: "apple.logo")
                    }
                    Text("Continue with Apple")
                        .font(DesignSystem.Typography.headline)
                }
                .foregroundColor(DesignSystem.Colors.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.extraLarge))
            }
            .disabled(apple.isWorking || google.isWorking)
            .padding(.horizontal, DesignSystem.Spacing.md)

            Button {
                if GoogleContactSignInCoordinator.isConfigured {
                    showGoogleConsent = true
                } else {
                    errorText = "Add your Google iOS OAuth client ID to Info.plist (GIDClientID + GIDURLScheme), then rebuild."
                    showError = true
                }
            } label: {
                HStack {
                    if google.isWorking {
                        ProgressView()
                    } else {
                        Image(systemName: "g.circle.fill")
                    }
                    Text("Continue with Google")
                        .font(DesignSystem.Typography.headline)
                }
                .foregroundColor(DesignSystem.Colors.text)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.extraLarge)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.extraLarge))
            }
            .disabled(apple.isWorking || google.isWorking)
            .padding(.horizontal, DesignSystem.Spacing.md)

            Text("Creates or links a local Zeroa identity. Apple/Google do not hold your keys and cannot restore your seed. No email is sent in this phase.")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .alert("Link Apple ID as contact?", isPresented: $showAppleConsent) {
            Button("Continue") { Task { await finish(await apple.continueWithApple(createIfNeeded: true)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple verifies a contact label only. It does not own your wallet. You can unbind in Settings.")
        }
        .alert("Link Google as contact?", isPresented: $showGoogleConsent) {
            Button("Continue") { Task { await finish(await google.continueWithGoogle(createIfNeeded: true)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Google verifies a contact label only. It does not own your wallet. You can unbind in Settings.")
        }
        .alert("Sign in", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "Something went wrong")
        }
    }

    private func finish(_ result: AppleContactSignInCoordinator.FlowResult) async {
        switch result {
        case .createdNewWallet, .boundExistingWallet:
            authManager.isAuthenticated = true
            path.append("home")
            Task { await HaloService.shared.ensureToken() }
        case .cancelled:
            break
        case .failed(let msg):
            errorText = msg
            showError = true
        }
    }

    private func finish(_ result: GoogleContactSignInCoordinator.FlowResult) async {
        switch result {
        case .createdNewWallet, .boundExistingWallet:
            authManager.isAuthenticated = true
            path.append("home")
            Task { await HaloService.shared.ensureToken() }
        case .cancelled:
            break
        case .failed(let msg):
            errorText = msg
            showError = true
        }
    }
}
