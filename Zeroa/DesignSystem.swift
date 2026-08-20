import SwiftUI

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: String = "Light" {
        didSet {
            updateTheme()
            // Save to UserDefaults
            UserDefaults.standard.set(currentTheme, forKey: "user_theme")
        }
    }
    
    private init() {
        // Load saved theme from UserDefaults
        if let savedTheme = UserDefaults.standard.string(forKey: "user_theme") {
            // If saved theme is Native, convert to Light
            if savedTheme == "Native" {
                currentTheme = "Light"
                UserDefaults.standard.set("Light", forKey: "user_theme")
            } else {
                currentTheme = savedTheme
            }
        } else {
            // Default to Light if no saved theme
            currentTheme = "Light"
            UserDefaults.standard.set("Light", forKey: "user_theme")
        }
        updateTheme()
    }
    
    private func updateTheme() {
        // This will be called when theme changes
        // The actual theme application happens in the Colors struct
    }
}

// MARK: - Design System
struct DesignSystem {
    
    static func updateTheme(_ theme: String) {
        ThemeManager.shared.currentTheme = theme
    }
    
    // MARK: - Colors
    struct Colors {
        // Theme-aware colors
        static var primary: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#4f225b")
            case "Dark":
                return Color(hex: "#2d1b3d")
            default: // System
                return Color(hex: "#4f225b")
            }
        }
        
        static var secondary: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#b37fc6")
            case "Dark":
                return Color(hex: "#8a5a9a")
            default: // System
                return Color(hex: "#b37fc6")
            }
        }
        
        static var accent: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#803a99")
            case "Dark":
                return Color(hex: "#6b2d7a")
            default: // System
                return Color(hex: "#803a99")
            }
        }
        
        static var light: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#d6b8db")
            case "Dark":
                return Color(hex: "#a88bb0")
            default: // System
                return Color(hex: "#d6b8db")
            }
        }
        
        static var background: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color(hex: "#f8f9fa")
            case "Dark":
                return Color(hex: "#1a1a1a")
            default: // System
                return Color(hex: "#4f225b")
            }
        }
        
        static var surface: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.white
            case "Dark":
                return Color(hex: "#2d2d2d")
            default: // System
                return Color(hex: "#6a2d7a").opacity(0.8)
            }
        }
        
        static var text: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.black
            case "Dark":
                return Color.white
            default: // System
                return Color(hex: "#ffffff")
            }
        }
        
        static var textSecondary: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.7)
            case "Dark":
                return Color.white.opacity(0.7)
            default: // System
                return Color(hex: "#ffffff").opacity(0.9)
            }
        }
        
        static let error = Color.red
        static let success = Color.green
        static let warning = Color.orange
        /// Text/icons on filled primary or solid buttons (e.g. Apple sign-in).
        static let onPrimary = Color.white
        
        static var border: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.2)
            case "Dark":
                return Color.white.opacity(0.2)
            default: // System
                return Color.white.opacity(0.3)
            }
        }
        
        static var disabled: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.gray.opacity(0.5)
            case "Dark":
                return Color.gray.opacity(0.5)
            default: // System
                return Color.white.opacity(0.3)
            }
        }
    }
    
    // MARK: - Typography
    struct Typography {
        static let titleLarge = Font.custom("AbadiMTProBold", size: 32)
        static let titleMedium = Font.custom("AbadiMTProBold", size: 24)
        static let titleSmall = Font.custom("AbadiMTProBold", size: 20)
        static let headline = Font.custom("AbadiMTProBold", size: 18)
        static let bodyLarge = Font.custom("AzoSansRegular", size: 16)
        static let bodyMedium = Font.custom("AzoSansRegular", size: 14)
        static let bodySmall = Font.custom("AzoSansRegular", size: 12)
        static let caption = Font.custom("AzoSansRegular", size: 10)
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
    
    // MARK: - Shadows
    struct Shadows {
        static var small: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.08)
            case "Dark":
                return Color.black.opacity(0.3)
            default: // System
                return Color.black.opacity(0.1)
            }
        }
        
        static var medium: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.12)
            case "Dark":
                return Color.black.opacity(0.4)
            default: // System
                return Color.black.opacity(0.15)
            }
        }
        
        static var large: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.16)
            case "Dark":
                return Color.black.opacity(0.5)
            default: // System
                return Color.black.opacity(0.2)
            }
        }
        
        // Elevation shadows for cards
        static var cardElevation: Color {
            switch ThemeManager.shared.currentTheme {
            case "Light":
                return Color.black.opacity(0.06)
            case "Dark":
                return Color.black.opacity(0.25)
            default: // System
                return Color.black.opacity(0.08)
            }
        }
    }
}

// MARK: - Reusable Components
struct PrimaryButton: View {
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
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(DesignSystem.Colors.secondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.extraLarge))
        }
        .disabled(isLoading)
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(DesignSystem.Colors.light)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.extraLarge))
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

struct InputField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    
    init(_ placeholder: String, text: Binding<String>, isSecure: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
    }
    
    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(DesignSystem.Typography.bodyLarge)
        .foregroundColor(DesignSystem.Colors.text)
        .padding(DesignSystem.Spacing.md)
        .frame(minHeight: 44)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.light.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Colors.light.opacity(0.3), lineWidth: 0.5)
            )
            // Multiple shadow layers for proper elevation effect
            .shadow(color: DesignSystem.Shadows.cardElevation, radius: 1, x: 0, y: 1)
            .shadow(color: DesignSystem.Shadows.cardElevation.opacity(0.5), radius: 3, x: 0, y: 2)
            .shadow(color: DesignSystem.Shadows.cardElevation.opacity(0.3), radius: 6, x: 0, y: 4)
            // Accentuated shadow on bottom and right for enhanced depth
            .shadow(color: DesignSystem.Shadows.cardElevation.opacity(0.8), radius: 2, x: 1, y: 3)
    }
}

struct LoadingView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.secondary))
                .scaleEffect(1.2)
            
            Text(message)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: (() -> Void)?
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.error)
            
            Text(message)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            if let retryAction = retryAction {
                PrimaryButton("Retry", action: retryAction)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Animations
struct Animations {
    static let spring = Animation.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)
    static let easeInOut = Animation.easeInOut(duration: 0.3)
    static let easeOut = Animation.easeOut(duration: 0.2)
}

// MARK: - Extensions
extension View {
    func primaryButtonStyle() -> some View {
        self
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(DesignSystem.Colors.secondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.extraLarge))
    }
    
    func secondaryButtonStyle() -> some View {
        self
            .font(DesignSystem.Typography.headline)
            .foregroundColor(DesignSystem.Colors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(DesignSystem.Colors.light)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.extraLarge))
    }
    
    func cardStyle() -> some View {
        self
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Colors.light.opacity(0.3), lineWidth: 0.5)
            )
            // Multiple shadow layers for proper elevation effect
            .shadow(color: DesignSystem.Shadows.cardElevation, radius: 1, x: 0, y: 1)
            .shadow(color: DesignSystem.Shadows.cardElevation.opacity(0.5), radius: 3, x: 0, y: 2)
            .shadow(color: DesignSystem.Shadows.cardElevation.opacity(0.3), radius: 6, x: 0, y: 4)
            // Accentuated shadow on bottom and right for enhanced depth
            .shadow(color: DesignSystem.Shadows.cardElevation.opacity(0.8), radius: 2, x: 1, y: 3)
    }
} 