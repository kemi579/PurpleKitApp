import SwiftUI

private enum PurpleKitTab: String, Identifiable {
    case files, apps, catalog, downloads, settings
    var id: String { rawValue }
}

struct MainTabView: View {
    @State private var tab: PurpleKitTab = .apps
    @ObservedObject private var certs = CertificateStore.shared

    var body: some View {
        TabView(selection: $tab) {
            FilesPlaceholderView()
                .tabItem { Label("Файлы", systemImage: "folder") }
                .tag(PurpleKitTab.files)

            LibraryView(onOpenSettings: { tab = .settings })
                .tabItem { Label("Приложения", systemImage: "square.stack.3d.up") }
                .tag(PurpleKitTab.apps)

            AppStorePlaceholderView()
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }
                .tag(PurpleKitTab.catalog)

            DownloadsPlaceholderView()
                .tabItem { Label("Загрузки", systemImage: "arrow.down.circle") }
                .tag(PurpleKitTab.downloads)

            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(PurpleKitTab.settings)
        }
        .environmentObject(certs)
        .tint(Theme.primaryLight)
        .toolbarBackground(Theme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
    }
}

struct FilesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("Файлы")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("Добавляй IPA кнопкой «Импортировать IPA» во вкладке «Приложения».")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct AppStorePlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("Каталог")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("Каталог скоро.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct DownloadsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("Загрузки")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("Активные загрузки появятся здесь.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationBarHidden(true)
        }
    }
}
