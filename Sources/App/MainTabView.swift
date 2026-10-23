import SwiftUI

/// Custom liquid-glass tab bar with sliding indicator (like reference apps).
struct MainTabView: View {
    @State private var tab = 1
    @StateObject private var certs = CertificateStore.shared
    @Namespace private var tabNS

    private let items: [(title: String, icon: String, selected: String)] = [
        ("Файлы", "folder", "folder.fill"),
        ("Библиотека", "square.grid.2x2", "square.grid.2x2.fill"),
        ("App Store", "apple.logo", "apple.logo"),
        ("Загрузки", "arrow.down.circle", "arrow.down.circle.fill"),
        ("Настройки", "gearshape", "gearshape.fill")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Group {
                switch tab {
                case 0: FilesPlaceholderView()
                case 1: LibraryView()
                case 2: AppStorePlaceholderView()
                case 3: DownloadsPlaceholderView()
                default: SettingsView()
                }
            }
            .environmentObject(certs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 64)

            liquidBar
        }
        .preferredColorScheme(.dark)
    }

    private var liquidBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    Haptic.light()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        tab = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if tab == index {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.22),
                                                Color.white.opacity(0.08)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                                    )
                                    .matchedGeometryEffect(id: "liquidTab", in: tabNS)
                                    .frame(width: 52, height: 32)
                            }
                            Image(systemName: tab == index ? item.selected : item.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(tab == index ? Theme.primaryLight : Theme.textTertiary)
                                .scaleEffect(tab == index ? 1.08 : 1.0)
                        }
                        .frame(height: 32)

                        Text(item.title)
                            .font(.system(size: 10, weight: tab == index ? .semibold : .regular))
                            .foregroundColor(tab == index ? Theme.primaryLight : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }
                .shadow(color: .black.opacity(0.35), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct FilesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("Файлы")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("Импорт IPA — во вкладке Библиотека (+).")
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
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("App Store")
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
                Color.black.ignoresSafeArea()
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
