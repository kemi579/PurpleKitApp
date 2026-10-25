import SwiftUI

/// All application colors and layout constants live here.
enum Theme {
    static let background = Color(hex: "000000")
    static let surface = Color(hex: "1C1C1E")
    static let primaryText = Color.white
    static let secondaryText = Color(hex: "8E8E93")
    // White semibold button text meets normal-text contrast against this purple.
    static let accent = Color(hex: "7957D5")
    static let success = Color(hex: "30D158")
    static let error = Color(hex: "FF453A")
    static let warning = Color(hex: "FFD60A")
    static let separator = Color.white.opacity(0.12)
    static let statusFillOpacity = 0.12
    static let groupRadius: CGFloat = 18
    static let buttonRadius: CGFloat = 16
    static let rowInset: CGFloat = 16
    static let pageInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let minimumTapTarget: CGFloat = 44
    static let qrBackground = Color.white
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255,
                  opacity: 1)
    }
}

@MainActor
struct Haptic {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
