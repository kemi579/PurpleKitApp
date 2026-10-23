import SwiftUI

struct MainTabView: View {
    @State private var tab = 0
    @StateObject private var certs = CertificateStore.shared

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

    // MARK: - Liquid Glass Tab Bar

    private var liquidTabBar: some View {
        HStack(spacing: 6) {
            tabButton(title: "Apps", symbol: "app.badge.fill", index: 0)
            tabButton(title: "Settings", symbol: "gearshape.fill", index: 1)
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.92)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.32),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(color: Theme.primary.opacity(0.18), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        }
        .padding(.horizontal, 36)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                colors: [
                    Theme.background.opacity(0),
                    Theme.background.opacity(0.55),
                    Theme.background.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(title: String, symbol: String, index: Int) -> some View {
        let isSelected = tab == index

        return Button {
            Haptic.light()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                tab = index
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(isSelected ? 1.05 : 1.0)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.primary.opacity(0.85),
                                    Theme.primaryLight.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        }
                        .shadow(color: Theme.primary.opacity(0.45), radius: 10, x: 0, y: 4)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
