import SwiftUI

struct ContentView: View {
    @EnvironmentObject var registry: ToolRegistry
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
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        searchBar

                        if !registry.favoriteTools().isEmpty && searchText.isEmpty && !showFavoritesOnly {
                            favoritesSection
                        }

                        if showFavoritesOnly {
                            favoritesOnlySection
                        } else if searchText.isEmpty {
                            categoriesSection
                        } else {
                            searchResults
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedTool) { tool in
                ToolDetailView(tool: tool)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PurpleKit")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.primaryGradient)
                Text("Multi-tool utility")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                Haptic.light()
                showFavoritesOnly.toggle()
            } label: {
                Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                    .font(.system(size: 20))
                    .foregroundColor(showFavoritesOnly ? Theme.warning : Theme.textSecondary)
                    .padding(10)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
        }
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textSecondary)
            TextField("Search tools…", text: $searchText)
                .foregroundColor(Theme.textPrimary)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Favorites", icon: "star.fill", color: Theme.warning)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(registry.favoriteTools()) { tool in
                    toolButton(tool)
                }
            }
        }
    }

    private var favoritesOnlySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Favorites", icon: "star.fill", color: Theme.warning)
            if registry.favoriteTools().isEmpty {
                EmptyStateView(icon: "star", title: "No favorites", message: "Tap the star on any tool to add it here.")
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(registry.favoriteTools()) { tool in
                        toolButton(tool)
                    }
                }
            }
        }
    }

    private var categoriesSection: some View {
        ForEach(ToolCategory.allCases.filter { $0 != .future }) { category in
            let items = registry.tools(for: category)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: category.rawValue, icon: category.icon, color: category.color)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { tool in
                            toolButton(tool)
                        }
                    }
                }
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Results", icon: "magnifyingglass")
            let results = registry.search(searchText)
            if results.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Nothing found", message: "Try a different search term.")
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(results) { tool in
                        toolButton(tool)
                    }
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

struct ToolDetailView: View {
    let tool: AnyTool
    @EnvironmentObject var registry: ToolRegistry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.primaryLight)
                    }
                    Spacer()
                    Text(tool.name)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Button {
                        registry.toggleFavorite(tool.id)
                    } label: {
                        Image(systemName: registry.isFavorite(tool.id) ? "star.fill" : "star")
                            .foregroundColor(registry.isFavorite(tool.id) ? Theme.warning : Theme.textSecondary)
                    }
                }
                .padding()
                .background(Theme.surface.opacity(0.8))

                tool.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
    }
}

extension AnyTool: Hashable {
    static func == (lhs: AnyTool, rhs: AnyTool) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
