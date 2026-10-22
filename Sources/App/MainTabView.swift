import SwiftUI

struct MainTabView: View {
    @State private var tab = 0
    @EnvironmentObject var registry: ToolRegistry
    @StateObject private var certs = CertificateStore.shared

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "square.grid.2x2.fill")
                }
                .tag(0)

            AppsView()
                .tabItem {
                    Label("Apps", systemImage: "app.badge.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(Theme.primaryLight)
        .environmentObject(certs)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Theme.surface)
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Theme.textSecondary)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(Theme.textSecondary)
            ]
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Theme.primaryLight)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(Theme.primaryLight)
            ]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
