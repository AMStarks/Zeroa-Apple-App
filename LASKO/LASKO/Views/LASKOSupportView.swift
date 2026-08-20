import SwiftUI

private enum LASKOSupportLink {
    static let charter = URL(string: "https://halo.telestai.io/charter")!
    static let faq = URL(string: "https://telestai.org/faq")!
    static let status = URL(string: "https://status.telestai.io")!
    static let supportEmail = "support@telestai.org"
}

struct LASKOSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.15, blue: 0.15)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    HStack {
                        Text("Support & Help")
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

                    VStack(alignment: .leading, spacing: 12) {
                        supportRow(
                            icon: "doc.text.fill",
                            title: "The Charter",
                            subtitle: "Community standards for LASKO",
                            action: { openURL(LASKOSupportLink.charter) }
                        )
                        supportRow(
                            icon: "questionmark.circle",
                            title: "FAQ",
                            subtitle: "Common questions and answers",
                            action: { openURL(LASKOSupportLink.faq) }
                        )
                        supportRow(
                            icon: "envelope.fill",
                            title: "Contact Support",
                            subtitle: "Email support@telestai.org",
                            action: {
                                if let url = URL(string: "mailto:\(LASKOSupportLink.supportEmail)?subject=LASKO%20Support%20Request") {
                                    openURL(url)
                                }
                            }
                        )
                        supportRow(
                            icon: "link",
                            title: "Status Page",
                            subtitle: "Network and service status",
                            action: { openURL(LASKOSupportLink.status) }
                        )
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func supportRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                    .font(.system(size: 18, weight: .semibold))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                    Text(subtitle)
                        .foregroundColor(.white.opacity(0.75))
                        .font(.system(size: 13))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
