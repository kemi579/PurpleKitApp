# Apple sign-in integration assessment

## Upstream code review

Reviewed the SideSign implementation through the GitHub connector:

- `Sources/DeveloperPortal/Authentication.swift` starts a real SRP client, builds the Apple GSA client dictionary from Anisette values, and drives the GrandSlam authentication exchange. It also contains the two-factor continuation logic.
- `Sources/DeveloperPortal/DeveloperPortalAPI.swift` defines typed verification requests and responses for trusted-device prompts, SMS, voice calls, verification codes, and cancellation. SMS/voice selection carries a phone-number identifier; it is not just a generic code-entry screen.
- `Package.swift` pins `swift-crypto` to 4.3.1 but follows moving branches for CodeSignKit, GSACryptoKit, libdeflate, and AnisetteKit. Integrating it unchanged would not provide a fully reproducible dependency graph.
- The upstream package is GPL-3.0 according to its repository metadata. Linking/redistributing it in PurpleKit requires an explicit licensing decision and compliance review. This is a technical risk summary, not legal advice.

SideStore's Anisette documentation describes Anisette as request metadata used when talking to Apple. The Anisette server is not the Apple ID authentication provider: the app still sends the authentication exchange to Apple, then handles 2FA and receives a real session. A server catalog or an HTTP request to a listed URL alone does not implement this protocol.

## PurpleKit state

The app currently has:
- `AppleDeveloperPortalAuthFlow.swift`: typed credentials, verification challenge/response, provider protocol, session boundary, and sanitized errors.
- `KeychainVault.swift`: generic Keychain storage for opaque session data; it must never store the Apple ID password.
- `AnisetteServerCatalog.swift`: server-list/configuration support, not a full Anisette protocol client.
- `AppleAccountAuthenticating.swift`: an older, simpler placeholder abstraction that should be consolidated when the real provider is selected.
- `SettingsView.swift`: currently saves an email for convenience and explicitly does not claim that this authenticates.

No real Apple login is wired up yet. No certificate or signing operation should be presented as successful until Apple has returned a real session and the certificate/profile have been verified.

## Implementation decision and safe order

The clean-room direction is to use upstream code as a behavioral reference, not copy source files or add SideSign as an unreviewed dependency. However, a clean-room implementation still needs a vetted, tested SRP/GrandSlam implementation and a supported Anisette source; cryptographic protocol code must not be improvised from a high-level description.

1. Select a compatible, maintained implementation for Apple GSA/SRP and review its license and test vectors.
2. Select and pin an Anisette implementation/provider. Treat custom server lists as untrusted configuration; validate HTTPS and never send the Apple ID/password to an Anisette server.
3. Implement the provider behind `AppleDeveloperPortalAuthenticating`, including actual Apple HTTP exchanges, trusted-device verification, SMS/voice delivery selection, code retry, cancellation, rate limiting, and sanitized errors.
4. Add a SwiftUI sign-in view that clears the password after each attempt/cancel and never logs or persists it. Do not report authenticated state before the provider returns a valid session.
5. Store only minimum resumable session material in Keychain, with explicit logout/expiry behavior.
6. Add tests for challenge transitions, wrong codes, cancellation, rate limiting, transport failures, malformed responses, and session persistence.
7. Only after authentication is verified, connect team discovery, certificate creation, provisioning profiles, and IPA signing.

## Current behavior remains intentionally limited

PurpleKit currently saves an Apple ID email as a convenience only. It does not authenticate with Apple, generate Anisette data, request a certificate, sign an IPA, pair with a device, or install apps. The unsigned IPA CI job validates packaging only, not installability.
