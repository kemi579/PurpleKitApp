import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var certs: CertificateStore
    @State private var email = ""
    @State private var showLogout = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // Header
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PurpleKit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                            Text("Settings")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Theme.primaryGradient)
                        }
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
                                        .padding(.vertical, 5)
                                        .background {
                                            Capsule()
                                                .fill(Theme.success.opacity(0.15))
                                                .overlay {
                                                    Capsule()
                                                        .strokeBorder(Theme.success.opacity(0.3), lineWidth: 1)
                                                }
                                        }
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

                                PurpleButton(title: "Certificate refresh unavailable", icon: "info.circle", style: .glass) {
                                    certs.refreshCert()
                                }

                                PurpleButton(title: "Disconnect", icon: "rectangle.portrait.and.arrow.right", style: .secondary) {
                                    showLogout = true
                                }
                            } else {
                                Text("Use Apple Developer Portal sign-in to authenticate with Apple ID, complete 2FA, load teams, and request a development certificate.")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)

                                PurpleTextField(placeholder: "Apple ID (email)", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)

                                PurpleButton(title: "Save email only", icon: "envelope", style: .glass) {
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
                        .glassCard(cornerRadius: 20)

                        // Navigation links
                        VStack(spacing: 12) {
                            NavigationLink {
                                AppleDeveloperPortalSignInView()
                            } label: {
                                GlassLinkCard(
                                    icon: "person.crop.circle.badge.checkmark",
                                    title: "Apple ID sign-in & 2FA",
                                    subtitle: "Apple ID + 2FA + development certificate",
                                    iconColor: Theme.neon
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                AnisetteServerSettingsView()
                            } label: {
                                GlassLinkCard(
                                    icon: "server.rack",
                                    title: "Anisette servers",
                                    subtitle: "Configure a SideStore-compatible catalog URL",
                                    iconColor: Theme.accent
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Sideloading info
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Sideloading", icon: "shippingbox.fill", color: Theme.neon)

                            infoLine(icon: "info.circle", text: "Free Apple ID = 7-day certificate, max 3 apps, 10 app IDs.")
                            infoLine(icon: "arrow.triangle.2.circlepath", text: "Refresh before expiry or apps stop launching.")
                            infoLine(icon: "lock.shield", text: "Auth & cert requests use SideSign; IPA signing and install are separate steps.")
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 18, intensity: 0.8)

                        // About
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "About", icon: "info.circle", color: Theme.textSecondary)

                            row("Version", "1.0.0")
                            row("Bundle", "com.kemi579.PurpleKit")
                            row("Min iOS", "16.0")
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 18, intensity: 0.75)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
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
