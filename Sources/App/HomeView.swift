import SwiftUI

struct HomeView: View {
    @EnvironmentObject var registry: ToolRegistry
    @EnvironmentObject var certs: CertificateStore
    @State private var searchText = ""
    @State private var selectedTool: AnyTool?
    @State private var showFavoritesOnly = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        certBanner
                        searchBar

                        if !registry.favoriteTools().isEmpty && searchText.isEmpty && !showFavoritesOnly {
                            sectionFavorites
                        }

                        if showFavoritesOnly {
                            sectionFavoritesOnly
                        } else if searchText.isEmpty {
                            sectionCategories
                        } else {
                            sectionSearch
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedTool) { tool in
                NavigationStack {
                    ToolDetailView(tool: tool)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PurpleKit")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.primaryGradient)
                Text("Tools · Sideload")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                Haptic.light()
                showFavoritesOnly.toggle()
            } label: {
                Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundColor(showFavoritesOnly ? Theme.warning : Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
        }
        .padding(.top, 8)
    }

    private var certBanner: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(certs.isCertHealthy ? Theme.success : (certs.isLoggedIn ? Theme.warning : Theme.textSecondary))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(certs.isLoggedIn ? certs.certStatusText : "Apple ID not connected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                if certs.isLoggedIn, let exp = certs.certExpires {
                    Text("Until \(exp, style: .date)")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                } else {
                    Text("Settings → connect free Apple ID")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textSecondary)
            TextField("Search tools…", text: $searchText)
                .foregroundColor(Theme.textPrimary)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sectionFavorites: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Favorites", icon: "star.fill", color: Theme.warning)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(registry.favoriteTools()) { toolButton($0) }
            }
        }
    }

    private var sectionFavoritesOnly: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Favorites", icon: "star.fill", color: Theme.warning)
            if registry.favoriteTools().isEmpty {
                EmptyStateView(icon: "star", title: "No favorites", message: "Tap ★ on any tool.")
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(registry.favoriteTools()) { toolButton($0) }
                }
            }
        }
    }

    private var sectionCategories: some View {
        ForEach(ToolCategory.allCases.filter { $0 != .future }) { category in
            let items = registry.tools(for: category)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: category.rawValue, icon: category.icon, color: category.color)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { toolButton($0) }
                    }
                }
            }
        }
    }

    private var sectionSearch: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Results", icon: "magnifyingglass")
            let results = registry.search(searchText)
            if results.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Nothing found", message: "Try another query.")
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(results) { toolButton($0) }
                }
            }
        }
    }

    private func toolButton(_ tool: AnyTool) -> some View {
        Button {
            Haptic.light()
            selectedTool = tool
        } label: {
            ToolCard(
                tool: tool,
                isFavorite: registry.isFavorite(tool.id),
                onFavorite: { registry.toggleFavorite(tool.id) }
            )
        }
        .buttonStyle(.plain)
    }
}
