import SwiftUI

struct SettingsGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
    }
}

struct SettingsDivider: View {
    var leading: CGFloat = Theme.rowInset

    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
            .padding(.leading, leading)
            .accessibilityHidden(true)
    }
}

/// Presentation only: wrap actionable rows in Button or NavigationLink.
struct SettingsRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let title: String
    var value: String? = nil
    var icon: String? = nil
    var showsChevron = true

    var body: some View {
        HStack(spacing: 16) {
            if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    titleText
                    valueText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    titleText
                    Spacer(minLength: 8)
                    valueText.multilineTextAlignment(.trailing)
                }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.rowInset)
        .frame(minHeight: Theme.minimumTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title)
            .font(.body)
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var valueText: some View {
        if let value {
            Text(value)
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PrimaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.medium()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).accessibilityHidden(true) }
                Text(title).multilineTextAlignment(.center)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, Theme.rowInset)
            .padding(.vertical, Theme.rowInset)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

struct PillBadge: View {
    let text: String
    var color: Color = Theme.secondaryText
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(Theme.statusFillOpacity), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var isMultiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(placeholder).font(.caption).foregroundStyle(Theme.secondaryText)
            Group {
                if isMultiline {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                } else {
                    TextField(placeholder, text: $text)
                        .frame(minHeight: Theme.minimumTapTarget)
                }
            }
            .font(.body)
            .foregroundStyle(Theme.primaryText)
            .accessibilityLabel(placeholder)
        }
        .padding(Theme.rowInset)
    }
}

struct ResultGroup: View {
    let title: String
    let value: String
    var onCopy: (() -> Void)? = nil

    var body: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
                Text(value.isEmpty ? "—" : value)
                    .font(.body.monospaced())
                    .foregroundStyle(Theme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.rowInset)
            .accessibilityElement(children: .combine)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = value
                    Haptic.success()
                    onCopy?()
                } label: { Label("Копировать", systemImage: "doc.on.doc") }
                .disabled(value.isEmpty)
                ShareLink(item: value) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                    .disabled(value.isEmpty)
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.headline).foregroundStyle(Theme.primaryText)
            Text(message).font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
    }
}

/// Keeps the primary action above the keyboard/tab bar without guessed bottom padding.
struct ToolLayout<Content: View>: View {
    private let content: Content
    private let primaryTitle: String?
    private let primaryAction: (() -> Void)?
    private let isBusy: Bool

    init(primaryTitle: String? = nil, isBusy: Bool = false,
         primaryAction: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.isBusy = isBusy
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) { content }
                .padding(Theme.pageInset)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let primaryTitle, let primaryAction {
                PrimaryButton(title: primaryTitle, action: primaryAction)
                    .disabled(isBusy)
                    .padding(Theme.pageInset)
                    .background(Theme.background)
            }
        }
    }
}

struct IconAction: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }
}

struct StatusBadges<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout { content }
            .padding(Theme.rowInset)
    }
}
