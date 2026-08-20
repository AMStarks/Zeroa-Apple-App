import SwiftUI

/// Compact posting-key status next to the feed profile avatar.
/// Green tick = can post; orange light = renew in Zeroa (tappable).
struct LASKOPostingKeyStatusDot: View {
    @EnvironmentObject var laskoService: LASKOService

    private enum Status {
        case ok
        case needsRenew
        case hidden
    }

    private var status: Status {
        guard laskoService.isAuthenticatedWithZeroa else { return .hidden }
        if laskoService.needsOpenZeroaToSign { return .needsRenew }
        if let mins = laskoService.postingKeyMinutesRemaining(), mins <= 0 {
            return .needsRenew
        }
        return .ok
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Group {
                switch status {
                case .hidden:
                    EmptyView()
                case .ok:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                        .accessibilityLabel("Posting permission active")
                case .needsRenew:
                    Button {
                        laskoService.openZeroaToFinishSigning()
                    } label: {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.orange.opacity(0.45), lineWidth: 4)
                                    .frame(width: 14, height: 14)
                            )
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Posting permission expired. Tap to renew in Zeroa.")
                }
            }
        }
    }
}

struct LASKOActivityInboxView: View {
    @EnvironmentObject var laskoService: LASKOService
    @State private var items: [LASKOInboxItem] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            LASKDesignSystem.Colors.background.ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .tint(Color(red: 1.0, green: 0.6, blue: 0.0))
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell")
                            .font(.system(size: 36))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                        Text("No replies yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                        Text("When someone comments on your posts, it’ll show up here.")
                            .font(.system(size: 13))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.fromAddress.map { shortAddr($0) } ?? "Someone")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(LASKDesignSystem.Colors.text)
                                    Text(item.preview ?? "Replied to your post")
                                        .font(.system(size: 13))
                                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                        .lineLimit(3)
                                    Text(RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: TimeInterval(item.at) / 1000), relativeTo: Date()))
                                        .font(.system(size: 11))
                                        .foregroundColor(LASKDesignSystem.Colors.textSecondary.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                Divider().background(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = await laskoService.loadInbox()
            isLoading = false
        }
    }

    private func shortAddr(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
