import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum Theme {
    static let background = Color(hex: "0B0714")
    static let surface = Color(hex: "1A1225")
    static let surfaceElevated = Color(hex: "251A35")
    static let primary = Color(hex: "6D28D9")
    static let primaryLight = Color(hex: "A78BFA")
    static let accent = Color(hex: "C084FC")
    static let neon = Color(hex: "E879F9")
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "A1A1AA")
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FBBF24")
    static let error = Color(hex: "F87171")

    static let cardGradient = LinearGradient(
        colors: [Color(hex: "1A1225"), Color(hex: "251A35")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "6D28D9"), Color(hex: "A78BFA")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let neonGradient = LinearGradient(
        colors: [Color(hex: "C084FC"), Color(hex: "E879F9")],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct Haptic {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
