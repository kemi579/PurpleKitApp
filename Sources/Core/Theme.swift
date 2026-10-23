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
    // Base
    static let background = Color(hex: "08050F")
    static let surface = Color(hex: "14101F")
    static let surfaceElevated = Color(hex: "1E182C")

    // Brand
    static let primary = Color(hex: "7C3AED")
    static let primaryLight = Color(hex: "A78BFA")
    static let accent = Color(hex: "C084FC")
    static let neon = Color(hex: "E879F9")

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "A1A1AA")
    static let textTertiary = Color(hex: "71717A")

    // Status
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FBBF24")
    static let error = Color(hex: "F87171")

    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "7C3AED"), Color(hex: "A78BFA")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let neonGradient = LinearGradient(
        colors: [Color(hex: "C084FC"), Color(hex: "E879F9")],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let cardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.08),
            Color.white.opacity(0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glowGradient = RadialGradient(
        colors: [
            Color(hex: "7C3AED").opacity(0.35),
            Color(hex: "7C3AED").opacity(0.0)
        ],
        center: .center,
        startRadius: 0,
        endRadius: 180
    )

    // Glass tokens
    static let glassStroke = Color.white.opacity(0.14)
    static let glassStrokeStrong = Color.white.opacity(0.22)
    static let glassFill = Color.white.opacity(0.06)
    static let glassHighlight = Color.white.opacity(0.12)
}

// MARK: - Liquid Glass modifiers

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 20
    var intensity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.85 * intensity)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Theme.cardGradient)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Theme.glassStrokeStrong,
                                        Theme.glassStroke.opacity(0.4),
                                        Theme.glassStroke
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color.black.opacity(0.28), radius: 20, x: 0, y: 10)
            }
    }
}

struct GlassCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(0.9)
                    .overlay {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.28),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20, intensity: Double = 1.0) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, intensity: intensity))
    }

    func glassCapsule() -> some View {
        modifier(GlassCapsuleBackground())
    }
}

// MARK: - Ambient background

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.background

            // Top-left purple orb
            Circle()
                .fill(Theme.primary.opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -90, y: -160)

            // Bottom-right neon orb
            Circle()
                .fill(Theme.neon.opacity(0.14))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: 100, y: 320)

            // Center soft glow
            Circle()
                .fill(Theme.accent.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(y: 40)
        }
        .ignoresSafeArea()
    }
}

@MainActor
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
