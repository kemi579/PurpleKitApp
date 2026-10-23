import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var certs: CertificateStore
    @State private var email = ""
    @State private var showLogout = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Settings")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.primaryGradient)
                            .padding(.top, 8)

                        // Apple ID card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.title2)
                                    .foregroundColor(Theme.textPrimary)
                                Text("Apple ID")
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                if certs.isLoggedIn {
                                    Text("Connected")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(Theme.success)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Theme.success.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }

                            if certs.isLoggedIn {
                                VStack(alignment: .leading, spacing: 10) {
                                    row("Account", certs.appleID)
                                    row("Certificate", certs.certName.isEmpty ? "—" : certs.certName)
                                    if let exp = certs.certExpires {
                                        row("Expires", exp.formatted(date: .abbreviated, time: .omitted))
                                    }
                                    row("Status", certs.certStatusText)
                                }

                                PurpleButton(title: "Refresh certificate", icon: "arrow.clockwise") {
                                    certs.refreshCert()
                                }

                                PurpleButton(title: "Disconnect", icon: "rectangle.portrait.and.arrow.right", style: .secondary) {
                                    showLogout = true
                                }
                            } else {
                                Text("Sign in with a free Apple ID. Certificate lasts ~7 days — refresh from here or via AltStore/SideStore.")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)

                                PurpleTextField(placeholder: "Apple ID (email)", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)

                                PurpleButton(title: "Connect", icon: "link") {
                                    certs.login(email: email.isEmpty ? certs.appleID : email)
                                    email = ""
                                }

                                if !certs.appleID.isEmpty {
                                    Button {
                                        email = certs.appleID
                                    } label: {
                                        Text("Use saved: \(certs.appleID)")
                                            .font(.caption)
                                            .foregroundColor(Theme.primaryLight)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Theme.cardGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )

                        NavigationLink {
                            AnisetteServerSettingsView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "server.rack")
                                    .font(.title3)
                                    .foregroundColor(Theme.neon)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Anisette servers")
                                        .font(.headline)
                                        .foregroundColor(Theme.textPrimary)
                                    Text("Configure a SideStore-compatible catalog URL")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .padding(16)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        // About sideload
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Sideloading", icon: "shippingbox.fill", color: Theme.neon)

                            infoLine(icon: "info.circle", text: "Free Apple ID = 7-day certificate, max 3 apps, 10 app IDs.")
                            infoLine(icon: "arrow.triangle.2.circlepath", text: "Refresh before expiry or apps stop launching.")
                            infoLine(icon: "lock.shield", text: "Password is never stored in PurpleKit. Sign only in AltStore / SideStore / Sideloadly.")
                        }

                        // App info
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "About", icon: "info.circle", color: Theme.textSecondary)

                            row("Version", "1.0.0")
                            row("Bundle", "com.kemi579.PurpleKit")
                            row("Min iOS", "16.0")
                        }
                        .padding(16)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                if email.isEmpty { email = certs.appleID }
            }
            .confirmationDialog("Disconnect Apple ID?", isPresented: $showLogout, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    certs.logout()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(Theme.textSecondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .foregroundColor(Theme.textPrimary)
                .font(.system(size: 14, design: .monospaced))
                .lineLimit(1)
        }
    }

    private func infoLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Theme.primaryLight)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
    }
}
