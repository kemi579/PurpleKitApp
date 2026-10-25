import SwiftUI

struct HomeView: View {
    @ObservedObject private var registry = ToolRegistry.shared
    @State private var query = ""

    private var categories: [ToolCategory] {
        ToolCategory.allCases.filter { $0 != .future && !registry.tools(for: $0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ToolLayout {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !registry.favoriteTools().isEmpty {
                        SectionHeading(title: "Избранное")
                        toolGroup(registry.favoriteTools())
                    }
                    SectionHeading(title: "Категории")
                    SettingsGroup {
                        ForEach(categories) { category in
                            NavigationLink {
                                CategoryToolsView(category: category)
                            } label: {
                                SettingsRow(title: category.rawValue,
                                            value: "\(registry.tools(for: category).count)",
                                            icon: category.icon)
                            }
                            .buttonStyle(.plain)
                            if category.id != categories.last?.id { SettingsDivider(leading: 56) }
                        }
                    }
                } else {
                    let results = registry.search(query)
                    if results.isEmpty {
                        EmptyStateView(title: "Ничего не найдено", message: "Попробуй другое название инструмента.")
                    } else {
                        toolGroup(results)
                    }
                }
            }
            .navigationTitle("Инструменты")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Поиск инструментов")
        }
    }

    private func toolGroup(_ tools: [AnyTool]) -> some View {
        SettingsGroup {
            ForEach(tools) { tool in
                ToolNavigationRow(tool: tool)
                if tool.id != tools.last?.id { SettingsDivider(leading: 56) }
            }
        }
    }
}

private struct CategoryToolsView: View {
    @ObservedObject private var registry = ToolRegistry.shared
    let category: ToolCategory

    var body: some View {
        ToolLayout {
            SettingsGroup {
                ForEach(registry.tools(for: category)) { tool in
                    ToolNavigationRow(tool: tool)
                    if tool.id != registry.tools(for: category).last?.id { SettingsDivider(leading: 56) }
                }
            }
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ToolNavigationRow: View {
    @ObservedObject private var registry = ToolRegistry.shared
    let tool: AnyTool

    var body: some View {
        NavigationLink {
            tool.content
                .navigationTitle(tool.name)
                .navigationBarTitleDisplayMode(.large)
        } label: {
            SettingsRow(title: tool.name, icon: tool.icon)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                registry.toggleFavorite(tool.id)
            } label: {
                Label(registry.isFavorite(tool.id) ? "Убрать из избранного" : "В избранное",
                      systemImage: registry.isFavorite(tool.id) ? "star.slash" : "star")
            }
        }
    }
}
