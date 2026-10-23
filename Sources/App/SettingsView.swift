import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var certs: CertificateStore
    @State private var showSignIn = false
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

                        // ── Apple ID — always on top ──
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
                                    if !certs.teamName.isEmpty {
                                        row("Team", certs.teamName)
                                    }
                                    row("Certificate", certs.certName.isEmpty ? "Not issued yet" : certs.certName)
                                    if let exp = certs.certExpires {
                                        row("Expires", exp.formatted(date: .abbreviated, time: .omitted))
                                    }
                                    row("Status", certs.certStatusText)
                                }

                                Button {
                                    showSignIn = true
                                } label: {
                                    Label("Manage sign-in & certificate", systemImage: "person.crop.circle.badge.checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .foregroundColor(Theme.textPrimary)
                                        .background {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.white.opacity(0.06))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .strokeBorder(Theme.glassStroke, lineWidth: 1)
                                                }
                                        }
                                }
                                .buttonStyle(.plain)

                                PurpleButton(
                                    title: "Disconnect",
                                    icon: "rectangle.portrait.and.arrow.right",
                                    style: .secondary
                                ) {
                                    showLogout = true
                                }
                            } else {
                                Text("Sign in with a free Apple ID to request a development certificate for sideloading. Password is never saved.")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)

                                Button {
                                    showSignIn = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "apple.logo")
                                        Text("Sign in with Apple ID")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .foregroundColor(.white)
                                    .background(Theme.primaryGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: Theme.primary.opacity(0.4), radius: 12, x: 0, y: 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 20)

                        // Sideloading info
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Sideloading", icon: "shippingbox.fill", color: Theme.neon)

                            infoLine(icon: "info.circle", text: "Free Apple ID = 7-day certificate, max 3 apps, 10 app IDs.")
                            infoLine(icon: "arrow.triangle.2.circlepath", text: "Refresh before expiry or apps stop launching.")
                            infoLine(icon: "lock.shield", text: "Auth uses SideSign + Anisette. Pick a server from the list on the sign-in screen.")
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
            .sheet(isPresented: $showSignIn) {
                AppleDeveloperPortalSignInView()
            }
            .confirmationDialog("Disconnect Apple ID?", isPresented: $showLogout, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    // Clear local store; SideSign session is cleared inside the sign-in view on next open or via shared sign-out.
                    certs.logout()
                    // Also wipe Keychain session so next open is clean
                    try? KeychainVault.delete(account: "sidesign-auth-session")
                    try? KeychainVault.delete(account: "sidesign-development-certificate-p12")
                    try? KeychainVault.delete(account: "sidesign-development-certificate-password")
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
