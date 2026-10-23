import Foundation

/// Stable UI-facing states for the future SideSign authentication adapter.
/// These states deliberately distinguish an email saved locally from an
/// authenticated Apple account. No state is persisted as authenticated.
enum AppleSignInState: Equatable {
    case signedOut
    case preparing
    case awaitingTwoFactor
    case authenticated(accountEmail: String)
    case failed(message: String)

    var title: String {
        switch self {
        case .signedOut: return "Not signed in"
        case .preparing: return "Preparing secure Apple sign-in…"
        case .awaitingTwoFactor: return "Waiting for Apple verification"
        case .authenticated: return "Authenticated"
        case .failed: return "Sign-in failed"
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

/// Boundary between PurpleKit's UI and the real Apple authentication stack.
/// A production implementation must be backed by SideSign/GSA + a supported
/// Anisette provider. This repository intentionally has no fake implementation.
protocol AppleAccountAuthenticating {
    func authenticate(appleID: String) async throws -> AppleAuthenticationSession
}

struct AppleAuthenticationSession {
    let accountEmail: String
    let sessionIdentifier: String
}

/// Errors suitable for display without leaking cookies, tokens, or credentials.
enum AppleAuthenticationError: LocalizedError {
    case providerUnavailable
    case invalidAccount
    case verificationRequired
    case rejectedByApple
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "Secure Apple sign-in is unavailable until the SideSign and Anisette provider are integrated."
        case .invalidAccount:
            return "Enter a valid Apple ID email address."
        case .verificationRequired:
            return "Apple requires additional verification. The current build cannot complete 2FA yet."
        case .rejectedByApple:
            return "Apple did not accept the sign-in request. Check the account and try again."
        case .transport:
            return "Could not reach the Apple sign-in service. Check the connection and try again."
        }
    }
}
