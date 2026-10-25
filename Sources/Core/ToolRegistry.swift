import SwiftUI

@MainActor
final class ToolRegistry: ObservableObject {
    static let shared = ToolRegistry()

    @Published private(set) var tools: [AnyTool] = []
    @Published var favorites: Set<String> = [] {
        didSet { saveFavorites() }
    }

    private let favoritesKey = "PurpleKit.favorites"

    private init() {
        loadFavorites()
        registerAll()
    }

    private func registerAll() {
        let list: [any Tool] = [
            // Text
            Base64Tool(),
            URLEncodeTool(),
            JSONFormatterTool(),
            CharacterCounterTool(),
            CaseConverterTool(),
            // Hash
            HashTool(),
            // Generator
            PasswordGeneratorTool(),
            UUIDGeneratorTool(),
            RandomNumberTool(),
            // QR
            QRGeneratorTool(),
            // Converter
            UnitConverterTool(),
            // Network
            MyIPTool(),
            DNSLookupTool(),
            PortCheckerTool(),
            HTTPStatusTool(),
            // Device
            DeviceInfoTool(),
            // Notes
            NotesTool(),
            ClipboardHistoryTool()
        ]
        tools = list.map { AnyTool($0) }
    }

    func tools(for category: ToolCategory) -> [AnyTool] {
        tools.filter { $0.category == category }
    }

    func favoriteTools() -> [AnyTool] {
        tools.filter { favorites.contains($0.id) }
    }

    func toggleFavorite(_ id: String) {
        Haptic.light()
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    private func loadFavorites() {
        if let data = UserDefaults.standard.array(forKey: favoritesKey) as? [String] {
            favorites = Set(data)
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    func search(_ query: String) -> [AnyTool] {
        guard !query.isEmpty else { return tools }
        let q = query.lowercased()
        return tools.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.category.rawValue.lowercased().contains(q)
        }
    }
}
