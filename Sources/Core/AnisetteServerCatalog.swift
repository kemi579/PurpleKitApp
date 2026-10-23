import Foundation
import Combine

struct AnisetteServer: Codable, Identifiable, Hashable {
    let name: String
    let address: String
    var id: String { address }

    init(name: String, address: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case name, address, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if let address = try container.decodeIfPresent(String.self, forKey: .address) {
            self.address = address
        } else {
            self.address = try container.decode(String.self, forKey: .url)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
    }
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
            servers = Self.validated(decoded)
        }
    }

    func refresh() async {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            lastError = "Enter a valid HTTPS URL to a JSON catalog. Credentials and non-HTTPS URLs are not accepted."
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
            guard let http = response as? HTTPURLResponse else {
                throw CatalogError.invalidResponse
            }
            guard http.url?.scheme?.lowercased() == "https" else {
                throw CatalogError.insecureRedirect
            }
            guard (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw CatalogError.httpStatus(code)
            }

            let decoded = try Self.decodeCatalog(data)
            guard !decoded.isEmpty else { throw CatalogError.emptyCatalog }
            servers = decoded
            let saved = try JSONEncoder().encode(decoded)
            UserDefaults.standard.set(saved, forKey: Self.serversKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func decodeCatalog(_ data: Data) throws -> [AnisetteServer] {
        let decoder = JSONDecoder()
        let candidates: [AnisetteServer]
        if let direct = try? decoder.decode([AnisetteServer].self, from: data) {
            candidates = direct
        } else if let wrapper = try? decoder.decode(ServerEnvelope.self, from: data) {
            candidates = wrapper.servers
        } else {
            throw CatalogError.invalidJSON
        }

        return validated(candidates)
    }

    private static func validated(_ candidates: [AnisetteServer]) -> [AnisetteServer] {
        var seen = Set<String>()
        return candidates.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = item.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let url = URL(string: address),
                  url.scheme?.lowercased() == "https",
                  url.host != nil,
                  url.user == nil,
                  url.password == nil,
                  seen.insert(url.absoluteString).inserted else { return nil }
            return AnisetteServer(name: name, address: url.absoluteString)
        }
    }

    private struct ServerEnvelope: Decodable {
        let servers: [AnisetteServer]
    }

    private enum CatalogError: LocalizedError {
        case httpStatus(Int)
        case invalidJSON
        case emptyCatalog
        case invalidResponse
        case insecureRedirect

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code): return "Catalog request failed (HTTP \(code))."
            case .invalidJSON: return "Expected a JSON array of {name,address/url} entries or an object with a servers array."
            case .emptyCatalog: return "The catalog contained no valid HTTPS server entries."
            case .invalidResponse: return "The catalog server returned an invalid HTTP response."
            case .insecureRedirect: return "The catalog redirected to a non-HTTPS URL. Use an HTTPS endpoint that stays on HTTPS."
            }
        }
    }
}
