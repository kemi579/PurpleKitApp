import Foundation
import CryptoKit

struct AppStoreConnectApp: Decodable, Identifiable, Sendable {
    struct Attributes: Decodable, Sendable {
        let name: String
        let bundleId: String
    }
    let id: String
    let attributes: Attributes
}

private struct AppStoreConnectAppsResponse: Decodable {
    let data: [AppStoreConnectApp]
    struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let title: String?
            let detail: String?
        }
        let errors: [APIError]?
    }
}

struct AppStoreConnectAPIKey: Codable, Sendable {
    let issuerID: String
    let keyID: String
    let privateKeyPEM: String
}

enum AppStoreConnectAPIError: LocalizedError {
    case invalidKey
    case invalidResponse
    case unauthorized
    case forbidden
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "The .p8 key could not be read. Select the original App Store Connect API private key."
        case .invalidResponse:
            return "Apple returned an unexpected response."
        case .unauthorized:
            return "Apple rejected the API key. Check the Issuer ID, Key ID, and .p8 file."
        case .forbidden:
            return "The API key lacks permission for this resource. Check its role in App Store Connect."
        case .server(let message):
            return message
        }
    }
}

/// Official App Store Connect API client. This is API-key authentication, not
/// Apple ID/password authentication and not a complete sideloading service.
enum AppStoreConnectAPI {
    static func listApps(using key: AppStoreConnectAPIKey) async throws -> [AppStoreConnectApp] {
        let token = try makeJWT(using: key)
        var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/apps?limit=200")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppStoreConnectAPIError.invalidResponse }
        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(AppStoreConnectAppsResponse.self, from: data).data
        case 401:
            throw AppStoreConnectAPIError.unauthorized
        case 403:
            throw AppStoreConnectAPIError.forbidden
        default:
            let envelope = try? JSONDecoder().decode(AppStoreConnectAppsResponse.ErrorEnvelope.self, from: data)
            let detail = envelope?.errors?.compactMap { $0.detail ?? $0.title }.first
            throw AppStoreConnectAPIError.server(detail ?? "App Store Connect API returned HTTP \(http.statusCode).")
        }
    }

    private static func makeJWT(using key: AppStoreConnectAPIKey, now: Date = Date()) throws -> String {
        let issuer = key.issuerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyID = key.keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !issuer.isEmpty, !keyID.isEmpty else { throw AppStoreConnectAPIError.invalidKey }

        let pem = key.privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: pem),
              let privateKey = try? P256.Signing.PrivateKey(derRepresentation: der) else {
            throw AppStoreConnectAPIError.invalidKey
        }

        let issuedAt = Int(now.timeIntervalSince1970)
        let header: [String: String] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": issuer,
            "iat": issuedAt,
            "exp": issuedAt + 15 * 60,
            "aud": "appstoreconnect-v1"
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signingInput = "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString())"
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(signature.rawRepresentation.base64URLEncodedString())"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
