import Foundation

/// User-facing authentication flow. Secrets are passed only for the duration
/// of an authentication attempt and must never be persisted or logged.
enum AppleAuthenticationStep: Equatable {
    case credentials
    case preparingAnisette
    case selectingVerificationMethod([AppleVerificationMethod])
    case awaitingVerificationCode(method: AppleVerificationMethod, destination: String?)
    case authenticating
    case authenticated(accountEmail: String)
    case failed(message: String)
}

enum AppleVerificationMethod: String, CaseIterable, Identifiable {
    case trustedDevice
    case sms
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trustedDevice: return "Trusted Apple device"
        case .sms: return "Text message (SMS)"
        case .voice: return "Phone call"
        }
    }
}

/// A challenge returned by an Apple Developer Portal authentication provider.
/// The UI must render the challenge without inventing a successful session.
enum AppleVerificationChallenge: Equatable {
    case chooseMethod(available: [AppleVerificationMethod])
    case enterCode(method: AppleVerificationMethod, destination: String?)
}

/// Inputs for a single login attempt. Do not store this value in UserDefaults,
/// Keychain, analytics, crash reports, or view-model persistence.
struct AppleAuthenticationCredentials {
    let appleID: String
    let password: String
}

/// Provider boundary for a clean-room implementation of Apple Developer Portal
/// authentication. Implementations must use a vetted SRP/GrandSlam crypto stack
/// and a supported Anisette provider; do not implement cryptographic primitives
/// from scratch. The password must be discarded when authenticate returns.
protocol AppleDeveloperPortalAuthenticating: Sendable {
    func authenticate(
        credentials: AppleAuthenticationCredentials,
        verificationHandler: @escaping @Sendable (AppleVerificationChallenge) async throws -> String?
    ) async throws -> AppleDeveloperPortalSession
}

/// Minimal session handle exposed to the app. The provider owns the actual
/// protocol session and must serialize only the minimum resumable material.
struct AppleDeveloperPortalSession: Sendable, Equatable {
    let accountEmail: String
    let opaqueSessionData: Data
}

/// Errors are deliberately sanitized before reaching the UI. Never include
/// response bodies, cookies, passwords, tokens, or raw Anisette headers.
enum AppleDeveloperPortalAuthError: LocalizedError {
    case invalidCredentials
    case verificationRejected
    case tooManyAttempts
    case cancelled
    case anisetteUnavailable
    case providerUnavailable
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Apple did not accept these credentials. Check your Apple ID and password."
        case .verificationRejected:
            return "The verification code was not accepted. Check it and try again."
        case .tooManyAttempts:
            return "Too many verification attempts. Wait before trying again."
        case .cancelled:
            return "Sign-in was cancelled."
        case .anisetteUnavailable:
            return "Anisette data is unavailable. Configure a supported provider and try again."
        case .providerUnavailable:
            return "Apple Developer Portal authentication provider is not connected in this build yet."
        case .networkUnavailable:
            return "Could not reach Apple. Check your connection and try again."
        }
    }
}
