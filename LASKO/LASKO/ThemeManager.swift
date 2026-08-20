import SwiftUI

// MARK: - LASKO Theme Manager
class LASKThemeManager: ObservableObject {
    static let shared = LASKThemeManager()
    
    @Published var currentTheme: String = "Dark" {
        didSet {
            updateTheme()
            UserDefaults.standard.set(currentTheme, forKey: "lasko_theme")
        }
    }
    
    private init() {
        // Load saved theme from UserDefaults
        if let savedTheme = UserDefaults.standard.string(forKey: "lasko_theme") {
            currentTheme = savedTheme
        } else {
            // Default to Dark for LASKO (maintains current appearance)
            currentTheme = "Dark"
            UserDefaults.standard.set("Dark", forKey: "lasko_theme")
        }
        updateTheme()
    }
    
    private func updateTheme() {
        // This will be called when theme changes
        // The actual theme application happens in the Colors struct
    }
    
    static func updateTheme(_ theme: String) {
        LASKThemeManager.shared.currentTheme = theme
    }
}

// MARK: - LASKO Design System
struct LASKDesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Theme-aware colors for LASKO
        static var background: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#eef0f3") // Soft gray so white cards stand out
            case "Dark":
                return Color(hex: "#181818")
            default:
                return Color(hex: "#181818")
            }
        }
        
        static var postSurface: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color.white
            case "Dark":
                return Color(hex: "#252525")
            default:
                return Color(hex: "#252525")
            }
        }
        
        static var nestedPostSurface: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#f7f8fa")
            case "Dark":
                return Color(hex: "#2E2E2E")
            default:
                return Color(hex: "#2E2E2E")
            }
        }
        
        static var cardBackground: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color.white
            case "Dark":
                return Color(hex: "#202020")
            default:
                return Color(hex: "#202020")
            }
        }
        
        static var text: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color.black
            case "Dark":
                return Color(hex: "#F2F2F2")
            default:
                return Color(hex: "#F2F2F2")
            }
        }
        
        static var textSecondary: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.7)
            case "Dark":
                return Color(hex: "#A8A8A8")
            default:
                return Color(hex: "#A8A8A8")
            }
        }
        
        // LASKO Orange - consistent across themes
        static let primary = Color(red: 1.0, green: 0.6, blue: 0.0)
        static let primaryDark = Color(red: 1.0, green: 0.4, blue: 0.0)
        
        // Accent colors
        static var accent: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#803a99") // Purple accent for light mode
            case "Dark":
                return Color(red: 1.0, green: 0.6, blue: 0.0) // Orange for dark mode
            default:
                return Color(red: 1.0, green: 0.6, blue: 0.0)
            }
        }
        
        static var border: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.1)
            case "Dark":
                return Color(hex: "#3A3A3A")
            default:
                return Color(hex: "#3A3A3A")
            }
        }
        
        static var divider: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.1)
            case "Dark":
                return Color(hex: "#3A3A3A")
            default:
                return Color(hex: "#3A3A3A")
            }
        }
        
        static var shadow: Color {
            switch LASKThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.1)
            case "Dark":
                return Color.black.opacity(0.3)
            default:
                return Color.black.opacity(0.3)
            }
        }
        
        // Status colors
        static let success = Color.green
        static let error = Color.red
        static let warning = Color.orange
    }
    
    // MARK: - Typography
    struct Typography {
        static let titleLarge = Font.system(size: 32, weight: .bold)
        static let titleMedium = Font.system(size: 24, weight: .semibold)
        static let titleSmall = Font.system(size: 20, weight: .semibold)
        static let headline = Font.system(size: 18, weight: .semibold)
        static let bodyLarge = Font.system(size: 16, weight: .regular)
        static let bodyMedium = Font.system(size: 14, weight: .regular)
        static let bodySmall = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 10, weight: .regular)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 25
    }
}

// MARK: - Reusable LASKO Components
struct LASKCardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(LASKDesignSystem.Spacing.md)
            .background(LASKDesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: LASKDesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: LASKDesignSystem.CornerRadius.large)
                    .stroke(LASKDesignSystem.Colors.border, lineWidth: 0.5)
            )
            .shadow(color: LASKDesignSystem.Colors.shadow, radius: 4, x: 0, y: 2)
    }
}

struct LASKPrimaryButton: View {
    let title: String
    let action: () -> Void
    let isLoading: Bool
    
    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                Text(title)
                    .font(LASKDesignSystem.Typography.headline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                LinearGradient(
                    colors: [LASKDesignSystem.Colors.primary, LASKDesignSystem.Colors.primaryDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: LASKDesignSystem.CornerRadius.extraLarge))
        }
        .disabled(isLoading)
        .padding(.horizontal, LASKDesignSystem.Spacing.md)
    }
}
