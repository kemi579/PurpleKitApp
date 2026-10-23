# Apple sign-in integration assessment

## Findings

The upstream SideSign package exposes an Apple Developer Portal authentication API that accepts an Apple ID, password, Anisette data, Xcode version, and a verification callback. Its authentication implementation handles SRP/GrandSlam and several two-factor flows, including a pushed-code response. This is useful upstream functionality, but it is not a drop-in PurpleKit adapter: PurpleKit currently has no Anisette data provider, no credential-entry/2FA flow, no secure session persistence, and no real account/session model.

Upstream package metadata currently declares Swift tools 6.0 and Swift language mode 6. PurpleKit's XcodeGen project currently sets Swift 5.9. The package also pulls several dependencies from moving branches (including CodeSignKit, GSACryptoKit, and AnisetteKit), so adding it without pinning and validating the complete dependency graph would make builds less reproducible.

SideSign's repository declares GPL-3.0. Before linking or redistributing it inside PurpleKit, the project owner should make an explicit license-compatibility decision and follow applicable license obligations. This note is a technical risk summary, not legal advice.

## Safe implementation order

1. Decide whether PurpleKit can comply with SideSign's GPL-3.0 terms. If not, evaluate a compatible alternative or isolate the integration in a separate process/service where appropriate; do not copy source files as a workaround.
2. Select and pin a known SideSign revision and all transitive dependencies. Test the Swift 6 toolchain and iOS 16 deployment target in CI before integrating the package into the app target.
3. Choose a supported Anisette strategy. The SideStore documentation describes a custom server-list JSON shape, but that catalog is only configuration: it does not generate Anisette headers by itself and does not authenticate an account.
4. Implement a user-initiated credential flow with password entry only in a secure UI session, never persist the password, and present the upstream verification callback for trusted-device or phone-code verification. Never log passwords, tokens, cookies, or raw authentication payloads.
5. Store any required session/key material in Keychain with a defined logout/expiry path. Persist only the minimum session material required by the upstream API.
6. Add tests for cancellation, invalid credentials, 2FA retries, rate limiting, network errors, logout, and the case where Apple sends a verification code automatically.
7. Only after successful authentication, connect account/team discovery to certificate creation and provisioning-profile management. Never show a certificate as healthy until an actual Apple-issued certificate and profile have been verified.

## Current behavior remains intentionally limited

PurpleKit currently saves an Apple ID email as a convenience only. It does not authenticate with Apple, generate Anisette data, request a certificate, sign an IPA, pair with a device, or install apps. The unsigned IPA CI job validates packaging only, not installability.
