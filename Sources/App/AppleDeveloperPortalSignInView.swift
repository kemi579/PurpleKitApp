import SwiftUI

/// Credential and 2FA UI for the provider boundary. The default app build has
/// no real Apple GSA provider, so it fails closed instead of simulating login.
@MainActor
final class AppleDeveloperPortalSignInModel: ObservableObject {
    @Published var appleID = ""
    @Published var password = ""
    @Published var verificationCode = ""
    @Published private(set) var step: AppleAuthenticationStep = .credentials
    @Published private(set) var isBusy = false

    private let provider: (any AppleDeveloperPortalAuthenticating)?

    init(provider: (any AppleDeveloperPortalAuthenticating)? = nil) {
        self.provider = provider
    }

    var canSubmit: Bool {
        !isBusy &&
        appleID.contains("@") &&
        !password.isEmpty &&
        provider != nil
    }

    func signIn() async {
        guard !isBusy else { return }
        guard let provider else {
            password = ""
            step = .failed(message: AppleDeveloperPortalAuthError.providerUnavailable.localizedDescription)
            return
        }

        let trimmedID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedID.contains("@") else {
            step = .failed(message: AppleDeveloperPortalAuthError.invalidCredentials.localizedDescription)
            return
        }

        isBusy = true
        step = .preparingAnisette
        defer {
            // Never keep a password in the view model after an attempt.
            password = ""
            isBusy = false
        }

        do {
            let credentials = AppleAuthenticationCredentials(appleID: trimmedID, password: password)
            let session = try await provider.authenticate(credentials: credentials) { [weak self] challenge in
                guard let self else { return .cancel }
                return await self.respond(to: challenge)
            }
            try KeychainVault.save(session.opaqueSessionData)
            step = .authenticated(accountEmail: session.accountEmail)
        } catch is CancellationError {
            step = .failed(message: AppleDeveloperPortalAuthError.cancelled.localizedDescription)
        } catch let error as AppleDeveloperPortalAuthError {
            step = .failed(message: error.localizedDescription)
        } catch {
            // Do not display arbitrary provider/server errors; they may contain
            // response details or sensitive authentication material.
            step = .failed(message: "Apple sign-in failed. Check the connection and try again.")
        }
    }

    func clear() {
        password = ""
        verificationCode = ""
        step = .credentials
    }

    private func respond(to challenge: AppleVerificationChallenge) async -> AppleVerificationResponse {
        switch challenge {
        case .chooseMethod(let methods):
            step = .selectingVerificationMethod(methods)
            // The UI currently has no continuation presenter wired into this
            // provider-independent model. Cancel rather than guessing a method.
            return .cancel
        case .enterCode(let method, let destination):
            step = .awaitingVerificationCode(method: method, destination: destination)
            // A production provider adapter must bridge this async callback to
            // a user-presented continuation. Never submit an empty/fake code.
            return .cancel
        }
    }
}

struct AppleDeveloperPortalSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AppleDeveloperPortalSignInModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Theme.primaryGradient)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)

                        Text("Apple Developer sign-in")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)

                        Text("The login and 2FA interface is prepared, but this build does not yet include a real Apple GSA/GrandSlam provider. No credentials are sent or stored.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Apple ID email", text: $model.appleID)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            SecureField("Apple ID password", text: $model.password)
                                .textContentType(.password)
                                .padding(14)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Button {
                                Task { await model.signIn() }
                            } label: {
                                HStack {
                                    if model.isBusy { ProgressView().tint(.white) }
                                    Text("Sign in")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(Theme.primaryGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(model.isBusy || model.appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.password.isEmpty)
                        }

                        statusView
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Apple ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        model.clear()
                        dismiss()
                    }
                }
            }
            .onDisappear { model.clear() }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.step {
        case .credentials:
            EmptyView()
        case .preparingAnisette:
            Label("Preparing secure sign-in…", systemImage: "lock.shield")
                .foregroundStyle(Theme.textSecondary)
        case .selectingVerificationMethod:
            Label("Apple verification method selection is waiting for the real provider.", systemImage: "checkmark.shield")
                .foregroundStyle(Theme.textSecondary)
        case .awaitingVerificationCode:
            Label("2FA code entry becomes available when a provider is connected.", systemImage: "number")
                .foregroundStyle(Theme.textSecondary)
        case .authenticating:
            Label("Authenticating with Apple…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.textSecondary)
        case .authenticated(let accountEmail):
            Label("Authenticated: \(accountEmail)", systemImage: "checkmark.shield.fill")
                .foregroundStyle(Theme.success)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.warning)
                .font(.subheadline)
        }
    }
}
