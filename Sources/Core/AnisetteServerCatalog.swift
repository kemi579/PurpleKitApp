import Foundation

struct AnisetteServer: Codable, Identifiable, Hashable {
    var name: String
    var address: String
    var id: String { address }
}

@MainActor
final class AnisetteServerCatalog: ObservableObject {
    static let shared = AnisetteServerCatalog()

    @Published private(set) var servers: [AnisetteServer] = []
    @Published var sourceURL: String {
        didSet { UserDefaults.standard.set(sourceURL, forKey: Self.sourceKey) }
    }
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private static let sourceKey = "PurpleKit.anisetteCatalogSource"
    private static let serversKey = "PurpleKit.anisetteServers"

    private init() {
        sourceURL = UserDefaults.standard.string(forKey: Self.sourceKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.serversKey),
           let decoded = try? JSONDecoder().decode([AnisetteServer].self, from: data) {
            servers = decoded
        }
    }

    func refresh() async {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            lastError = "Enter a valid HTTPS URL to a SideStore-compatible JSON server catalog."
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw CatalogError.httpStatus(code)
            }

            let decoded = try Self.decodeCatalog(data)
            guard !decoded.isEmpty else { throw CatalogError.emptyCatalog }
            servers = decoded
            if let saved = try? JSONEncoder().encode(decoded) {
                UserDefaults.standard.set(saved, forKey: Self.serversKey)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func decodeCatalog(_ data: Data) throws -> [AnisetteServer] {
        let decoder = JSONDecoder()
        let parsed: [AnisetteServer]
        if let direct = try? decoder.decode([AnisetteServer].self, from: data) {
            parsed = direct
        } else if let wrapper = try? decoder.decode(ServerEnvelope.self, from: data) {
            parsed = wrapper.servers
        } else {
            throw CatalogError.invalidJSON
        }

        var seen = Set<String>()
        return parsed.filter { item in
            let address = item.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: address),
                  url.scheme?.lowercased() == "https",
                  url.host != nil,
                  !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(address).inserted else { return false }
            return true
        }
    }

    private struct ServerEnvelope: Decodable {
        let servers: [AnisetteServer]
    }

    private enum CatalogError: LocalizedError {
        case httpStatus(Int)
        case invalidJSON
        case emptyCatalog

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code): return "Catalog request failed (HTTP \(code))."
            case .invalidJSON: return "The URL did not return a supported JSON catalog."
            case .emptyCatalog: return "The catalog contained no valid HTTPS server entries."
            }
        }
    }
}
