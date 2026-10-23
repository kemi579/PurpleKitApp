import SwiftUI

struct MainTabView: View {
    @State private var tab = 0
    @StateObject private var certs = CertificateStore.shared
    @Namespace private var tabNS

    private let tabs: [(title: String, symbol: String)] = [
        ("Apps", "app.badge.fill"),
        ("Settings", "gearshape.fill")
    ]

    var body: some View {
        ZStack {
            AmbientBackground()

            TabView(selection: $tab) {
                AppsView()
                    .tag(0)

                SettingsView()
                    .tag(1)
            }
            .tint(Theme.primaryLight)
            .environmentObject(certs)
            .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            liquidTabBar
        }
    }

    // MARK: - Slim horizontal Liquid Glass bar

    private var liquidTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, item in
                tabButton(title: item.title, symbol: item.symbol, index: index)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background {
            // Outer glass capsule
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.88)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.03),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Theme.primary.opacity(0.16), radius: 14, x: 0, y: 6)
                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
        }
        .padding(.horizontal, 48)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background {
            LinearGradient(
                colors: [
                    Theme.background.opacity(0),
                    Theme.background.opacity(0.5),
                    Theme.background.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(title: String, symbol: String, index: Int) -> some View {
        let isSelected = tab == index

        return Button {
            Haptic.light()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                tab = index
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.primary.opacity(0.9),
                                    Theme.primaryLight.opacity(0.75)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                        }
                        .shadow(color: Theme.primary.opacity(0.5), radius: 8, x: 0, y: 3)
                        .matchedGeometryEffect(id: "liquidPill", in: tabNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
