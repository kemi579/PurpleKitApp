import SwiftUI

struct MainTabView: View {
    @State private var tab = 0
    @StateObject private var certs = CertificateStore.shared

    var body: some View {
        TabView(selection: $tab) {
            AppsView()
                .tabItem {
                    Label("Apps", systemImage: "app.badge.fill")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(1)
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
