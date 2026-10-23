import SwiftUI

/// Classic bottom tab bar (like screenshot): Files · Library · App Store · Downloads · Settings
struct MainTabView: View {
    @State private var tab = 1 // Library selected by default
    @StateObject private var certs = CertificateStore.shared

    var body: some View {
        TabView(selection: $tab) {
            FilesPlaceholderView()
                .tabItem {
                    Label("Файлы", systemImage: "folder")
                }
                .tag(0)

            LibraryView()
                .tabItem {
                    Label("Библиотека", systemImage: "square.grid.2x2.fill")
                }
                .tag(1)

            AppStorePlaceholderView()
                .tabItem {
                    Label("App Store", systemImage: "apple.logo")
                }
                .tag(2)

            DownloadsPlaceholderView()
                .tabItem {
                    Label("Загрузки", systemImage: "arrow.down.circle")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(4)
        }
        .tint(Theme.primaryLight)
        .environmentObject(certs)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Placeholders for extra tabs (wired for layout parity)

struct FilesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("Файлы")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("IPA import lives in Library for now.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationTitle("Файлы")
        }
    }
}

struct AppStorePlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("App Store")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("Catalog coming later.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationTitle("App Store")
        }
    }
}

struct DownloadsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("Загрузки")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("Active downloads will show here.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationTitle("Загрузки")
        }
    }
}
