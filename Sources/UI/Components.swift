import SwiftUI

struct ToolCard: View {
    let tool: AnyTool
    let isFavorite: Bool
    let onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: tool.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primaryGradient)
                    .frame(width: 40, height: 40)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .medium))
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
        .background(Theme.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

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
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

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
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundColor(Theme.textPrimary)
        .font(.system(size: 15, design: .monospaced))
    }
}

struct PurpleButton: View {
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    let action: () -> Void

    enum Style {
        case primary, secondary, danger
    }

    var body: some View {
        Button(action: {
            Haptic.medium()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(buttonBackground)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch style {
        case .primary:
            Theme.primaryGradient
        case .secondary:
            Theme.surfaceElevated
        case .danger:
            Color(hex: "F87171").opacity(0.8)
        }
    }
}

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
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Theme.primaryGradient)
            Text(title)
                .font(.title3.bold())
                .foregroundColor(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
