import SwiftUI

struct MainTabView: View {
    @State private var tab = 0
    @StateObject private var certs = CertificateStore.shared

    var body: some View {
        TabView(selection: $tab) {
            AppsView()
                .tag(0)

            SettingsView()
                .tag(1)
        }
        .tint(Theme.primaryLight)
        .environmentObject(certs)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            glassTabBar
        }
    }

    private var glassTabBar: some View {
        HStack(spacing: 8) {
            tabButton(title: "Apps", symbol: "app.badge.fill", index: 0)
            tabButton(title: "Settings", symbol: "gearshape.fill", index: 1)
        }
        .padding(7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background {
            LinearGradient(
                colors: [
                    Theme.background.opacity(0),
                    Theme.background.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(title: String, symbol: String, index: Int) -> some View {
        let isSelected = tab == index

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                tab = index
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.primaryLight : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.primaryLight.opacity(0.16))
                        .overlay {
                            Capsule()
                                .strokeBorder(Theme.primaryLight.opacity(0.2), lineWidth: 1)
                        }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
