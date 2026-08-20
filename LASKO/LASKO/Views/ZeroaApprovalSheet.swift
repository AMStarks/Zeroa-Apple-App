import SwiftUI

struct ZeroaApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var laskoService: LASKOService
    @EnvironmentObject var authUIState: AuthUIState
    @StateObject private var themeManager = LASKThemeManager.shared
    
    @State private var showingApproved = false
    @State private var pollTimer: Timer?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: showingApproved ? "checkmark.seal.fill" : "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(showingApproved ? .green : LASKDesignSystem.Colors.primary)
                .padding(.top, 8)
            
            Text(showingApproved ? "Approved" : "Connect with Zeroa")
                .font(LASKDesignSystem.Typography.titleMedium)
                .foregroundColor(LASKDesignSystem.Colors.text)
            
            Text(showingApproved ? "You're connected to Zeroa."
                 : "Approve this request in Zeroa to let LASKO access your TLS address and post on your behalf.")
                .multilineTextAlignment(.center)
                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                .font(LASKDesignSystem.Typography.bodyMedium)
                .padding(.horizontal, 16)
            
            if !showingApproved {
                VStack(spacing: 12) {
                    Button {
                        // Open Zeroa approval screen via custom scheme only
                        if let url = URL(string: "zeroa://auth/request") {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open Zeroa to Approve")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LASKDesignSystem.Colors.primary)
                    
                    Button {
                        // Fallback: guide to download (wire real App Store URL later)
                        if let url = URL(string: "https://apps.apple.com") {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Download Zeroa")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(LASKDesignSystem.Colors.text)
                    .overlay(
                        RoundedRectangle(cornerRadius: LASKDesignSystem.CornerRadius.medium)
                            .stroke(LASKDesignSystem.Colors.border, lineWidth: 1)
                    )
                }
                .padding(.top, 6)
            }
            
            Spacer(minLength: 8)
        }
        .padding(20)
        .background(LASKDesignSystem.Colors.background)
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Start polling every 0.5s while the sheet is visible
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in
                    await laskoService.checkForAuthResponse()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Re-check when returning from Zeroa
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                laskoService.checkForAuthResponse()
            }
        }
        .onChange(of: laskoService.isAuthenticatedWithZeroa, initial: false) { _, isAuthed in
            if isAuthed {
                withAnimation(.spring()) {
                    showingApproved = true
                    authUIState.step = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    pollTimer?.invalidate()
                    dismiss()
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
    }
}

