import SwiftUI

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
            .padding(.bottom, 78)

            floatingGlassBar
        }
        .preferredColorScheme(.dark)
    }

    /// Floating capsule tab bar — material glass + sliding liquid highlight.
    private var floatingGlassBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    Haptic.light()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        tab = index
                    }
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            if tab == index {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.28),
                                                        Theme.primary.opacity(0.35),
                                                        Color.white.opacity(0.08)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.55),
                                                        Color.white.opacity(0.12),
                                                        Color.white.opacity(0.3)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    }
                                    .shadow(color: Theme.primary.opacity(0.45), radius: 10, y: 2)
                                    .matchedGeometryEffect(id: "liquidGlassPill", in: tabNS)
                                    .frame(width: 56, height: 34)
                            }

                            Image(systemName: tab == index ? item.selected : item.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(tab == index ? Color.white : Theme.textTertiary)
                                .scaleEffect(tab == index ? 1.1 : 1.0)
                        }
                        .frame(height: 34)

                        Text(item.title)
                            .font(.system(size: 10, weight: tab == index ? .bold : .regular))
                            .foregroundColor(tab == index ? .white : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.92)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.04),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
                .shadow(color: Theme.primary.opacity(0.15), radius: 12, y: 2)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
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
