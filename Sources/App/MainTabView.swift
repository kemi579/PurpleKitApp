import SwiftUI

private enum PurpleKitTab: Hashable {
    case tools, notes, device, settings
}

struct MainTabView: View {
    @State private var tab: PurpleKitTab = .tools
    @ObservedObject private var certs = CertificateStore.shared

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Инструменты", systemImage: "square.grid.2x2") }
                .tag(PurpleKitTab.tools)
            NavigationStack {
                NotesView()
                    .navigationTitle("Заметки")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("Заметки", systemImage: "note.text") }
            .tag(PurpleKitTab.notes)
            NavigationStack {
                DeviceInfoView()
                    .navigationTitle("Устройство")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("Устройство", systemImage: "iphone") }
            .tag(PurpleKitTab.device)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(PurpleKitTab.settings)
        }
        .environmentObject(certs)
        .tint(Theme.accent)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
    }
}
