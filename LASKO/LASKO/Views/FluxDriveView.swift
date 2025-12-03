import SwiftUI

struct FluxDriveView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var usedStorageGB: Double = 0.8
    @State private var totalStorageGB: Double = 5.0
    @State private var syncEnabled: Bool = true
    @State private var showStoredItems = false

    private var usedPercentage: Double {
        guard totalStorageGB > 0 else { return 0 }
        return min(max(usedStorageGB / totalStorageGB, 0), 1)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.15, blue: 0.15)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Header with Storage logo
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Storage")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Decentralized storage")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Usage card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "battery.50")
                                .font(.system(size: 26))
                                .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))

                            Text("Usage")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: usedPercentage)
                                .tint(Color(red: 1.0, green: 0.6, blue: 0.0))
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            HStack {
                                Text(String(format: "%.1f GB used", usedStorageGB))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14, weight: .medium))

                                Spacer()

                                Text(String(format: "of %.0f GB", totalStorageGB))
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.system(size: 14, weight: .regular))
                            }
                        }

                        // View Stored Items button
                        Button(action: { showStoredItems = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundColor(.white)
                                Text("View Stored Items")
                                    .foregroundColor(.white)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    // Sync settings
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                            Text("Sync")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Toggle("", isOn: $syncEnabled)
                                .labelsHidden()
                        }

                        Text("Keep your posts and media synchronized across devices.")
                            .foregroundColor(.white.opacity(0.75))
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

                    // Actions
                    VStack(spacing: 12) {
                        // Upgrade tiers
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Upgrade Storage")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            VStack(spacing: 10) {
                                upgradeRow(tier: "Basic", size: "5 GB", price: "2 TLS / mo")
                                upgradeRow(tier: "Plus", size: "20 GB", price: "5 TLS / mo")
                                upgradeRow(tier: "Pro", size: "100 GB", price: "10 TLS / mo")
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .cornerRadius(14)

                        Button(action: { dismiss() }) {
                            Text("Close")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showStoredItems) {
                FluxStoredItemsView()
            }
        }
    }
}

// MARK: - Upgrade row helper
private struct UpgradeButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 1.0, green: 0.4, blue: 0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

@ViewBuilder
private func upgradeRow(tier: String, size: String, price: String) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(tier) — \(size)")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .semibold))
            Text(price)
                .foregroundColor(.white.opacity(0.75))
                .font(.system(size: 12))
        }
        Spacer()
        UpgradeButton(title: "Select") {
            // TODO: Wire to subscription/payment flow
        }
    }
    .padding(12)
    .background(Color.white.opacity(0.04))
    .cornerRadius(10)
}

