import SwiftUI

// MARK: - Tool Card

struct ToolCard: View {
    let tool: AnyTool
    let isFavorite: Bool
    let onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: tool.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.primaryGradient)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.primaryLight.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.primaryLight.opacity(0.2), lineWidth: 1)
                            }
                    }

                Spacer()

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isFavorite ? Theme.warning : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text(tool.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            Text(tool.description)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    var color: Color = Theme.primaryLight

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Text Field

struct PurpleTextField: View {
    let placeholder: String
    @Binding var text: String
    var isMultiline: Bool = false

    var body: some View {
        Group {
            if isMultiline {
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.7)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.glassStroke, lineWidth: 1)
                }
        }
        .foregroundColor(Theme.textPrimary)
        .font(.system(size: 15, design: .monospaced))
    }
}

// MARK: - Button

struct PurpleButton: View {
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    let action: () -> Void

    enum Style {
        case primary, secondary, danger, glass
    }

    var body: some View {
        Button(action: {
            Haptic.medium()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundColor(foreground)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if style == .glass || style == .secondary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.glassStroke, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary, .danger: return .white
        case .secondary, .glass: return Theme.textPrimary
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch style {
        case .primary:
            Theme.primaryGradient
                .shadow(color: Theme.primary.opacity(0.45), radius: 12, x: 0, y: 6)
        case .secondary:
            Color.white.opacity(0.06)
        case .danger:
            Color(hex: "F87171").opacity(0.85)
        case .glass:
            Color.clear
                .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Result Box

struct ResultBox: View {
    let title: String
    let value: String
    var onCopy: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                if let onCopy {
                    Button {
                        UIPasteboard.general.string = value
                        Haptic.success()
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.primaryLight)
                    }
                }
            }
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassCard(cornerRadius: 14, intensity: 0.85)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.primary.opacity(0.12))
                    .frame(width: 88, height: 88)
                    .blur(radius: 2)

                Image(systemName: icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.primaryGradient)
            }

            Text(title)
                .font(.title3.bold())
                .foregroundColor(Theme.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(36)
        .glassCard(cornerRadius: 24)
    }
}

// MARK: - Glass Row / Link Card

struct GlassLinkCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconColor: Color = Theme.primaryLight

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 46, height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(iconColor.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(iconColor.opacity(0.22), lineWidth: 1)
                        }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.6), radius: 4)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.85)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
