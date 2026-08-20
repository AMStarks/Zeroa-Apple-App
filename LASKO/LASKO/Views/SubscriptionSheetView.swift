import SwiftUI

struct SubscriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.15, blue: 0.15)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Subscription")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Icon + blurb
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 56))
                            .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))

                        Text("Unlock LASKO Features")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Subscribe to enable enhanced services across the LASKO platform.")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    // Plan card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                            Text("Pro Plan")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text("10 TLS / month")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 14, weight: .medium))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Full Platform Access", systemImage: "bolt.fill")
                                .foregroundColor(.white)
                            Label("Storage sync perks", systemImage: "externaldrive.fill")
                                .foregroundColor(.white)
                            Label("Support the network", systemImage: "hands.sparkles.fill")
                                .foregroundColor(.white)
                        }
                        .font(.system(size: 14))
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    Spacer()

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                            .padding(.horizontal, 20)
                    }

                    Button(action: subscribe) {
                        HStack(spacing: 12) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 18, weight: .semibold))
                            }

                            Text(isProcessing ? "Processing…" : "Subscribe with TLS")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.6, blue: 0.0),
                                    Color(red: 1.0, green: 0.4, blue: 0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .padding(.horizontal, 20)
                    }

                    Button(action: { dismiss() }) {
                        Text("Not now")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func subscribe() {
        isProcessing = true
        errorMessage = nil

        Task {
            let success = await LASKOService.shared.requestSubscriptionPayment()
            
            await MainActor.run {
                isProcessing = false
                if success {
                    dismiss()
                } else {
                    errorMessage = "Payment failed. Please try again."
                }
            }
        }
    }
}
