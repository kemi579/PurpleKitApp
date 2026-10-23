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
    private var verificationContinuation: CheckedContinuation<AppleVerificationResponse, Never>?

    init(provider: (any AppleDeveloperPortalAuthenticating)? = nil) {
        self.provider = provider
    }

    var canSubmit: Bool {
        !isBusy && appleID.contains("@") && !password.isEmpty && provider != nil
    }

    var availableVerificationMethods: [AppleVerificationMethod] {
        guard case .selectingVerificationMethod(let methods) = step else { return [] }
        return methods
    }

    var canSubmitVerificationCode: Bool {
        guard case .awaitingVerificationCode = step else { return false }
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !code.isEmpty && verificationContinuation != nil
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
            step = .failed(message: "Apple sign-in failed. Check the connection and try again.")
        }
    }

    func chooseVerificationMethod(_ method: AppleVerificationMethod) {
        guard availableVerificationMethods.contains(method),
              let continuation = verificationContinuation else { return }
        verificationContinuation = nil
        continuation.resume(returning: .choose(method))
    }

    func submitVerificationCode() {
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let continuation = verificationContinuation else { return }
        verificationCode = ""
        verificationContinuation = nil
        continuation.resume(returning: .code(code))
    }

    func cancelVerification() {
        guard let continuation = verificationContinuation else { return }
        verificationContinuation = nil
        verificationCode = ""
        continuation.resume(returning: .cancel)
    }

    func clear() {
        cancelVerification()
        password = ""
        verificationCode = ""
        step = .credentials
    }

    private func respond(to challenge: AppleVerificationChallenge) async -> AppleVerificationResponse {
        await withCheckedContinuation { continuation in
            // Only one verification prompt may be active for a provider attempt.
            guard verificationContinuation == nil else {
                continuation.resume(returning: .cancel)
                return
            }
            verificationContinuation = continuation
            switch challenge {
            case .chooseMethod(let methods):
                guard !methods.isEmpty else {
                    verificationContinuation = nil
                    continuation.resume(returning: .cancel)
                    return
                }
                step = .selectingVerificationMethod(methods)
            case .enterCode(let method, let destination):
                verificationCode = ""
                step = .awaitingVerificationCode(method: method, destination: destination)
            }
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
                                    Text("Sign in").fontWeight(.semibold)
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
        case .selectingVerificationMethod(let methods):
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose a verification method").font(.headline)
                ForEach(methods) { method in
                    Button(method.title) {
                        model.chooseVerificationMethod(method)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Cancel verification", role: .cancel) {
                    model.cancelVerification()
                }
                .foregroundStyle(Theme.warning)
            }
        case .awaitingVerificationCode(let method, let destination):
            VStack(alignment: .leading, spacing: 10) {
                Text(method.title).font(.headline)
                if let destination, !destination.isEmpty {
                    Text("Code destination: \(destination)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                TextField("Verification code", text: $model.verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(14)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("Submit code") { model.submitVerificationCode() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubmitVerificationCode)
                Button("Cancel verification", role: .cancel) {
                    model.cancelVerification()
                }
                .foregroundStyle(Theme.warning)
            }
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
