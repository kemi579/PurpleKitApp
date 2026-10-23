import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var certs: CertificateStore
    @StateObject private var signer = IPASigningService.shared
    @State private var showSignIn = false
    @State private var showLogout = false
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PurpleKit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                            Text("Settings")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Theme.primaryGradient)
                        }
                        .padding(.top, 8)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                        appleIDCard
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 16)

                        deviceCard
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 18)

                        preferencesCard
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 20)

                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Sideloading", icon: "shippingbox.fill", color: Theme.neon)

                            infoLine(icon: "info.circle", text: "Free Apple ID = 7-day certificate, max 3 apps, 10 app IDs.")
                            infoLine(icon: "arrow.triangle.2.circlepath", text: "Refresh before expiry or apps stop launching.")
                            infoLine(icon: "iphone", text: "UDID is required to register this device on the portal before signing.")
                            infoLine(icon: "lock.shield", text: "If Anisette returns 434 — switch to another server.")
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 18, intensity: 0.8)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 24)

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "About", icon: "info.circle", color: Theme.textSecondary)

                            row("Version", "1.0.0")
                            row("Bundle", "com.kemi579.PurpleKit")
                            row("Min iOS", "16.0")
                            row("Engine", "SideSign")
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 18, intensity: 0.75)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 28)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                    appear = true
                }
            }
            .sheet(isPresented: $showSignIn) {
                AppleDeveloperPortalSignInView()
            }
            .confirmationDialog("Disconnect Apple ID?", isPresented: $showLogout, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    certs.logout()
                    try? KeychainVault.delete(account: "sidesign-auth-session")
                    try? KeychainVault.delete(account: "sidesign-development-certificate-p12")
                    try? KeychainVault.delete(account: "sidesign-development-certificate-password")
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var appleIDCard: some View {
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
                Text("Sign in with a free Apple ID to request a development certificate. Password is never saved.")
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
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "This device", icon: "iphone", color: Theme.primaryLight)

            Text("UDID (required to sign & install)")
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.textSecondary)

            TextField("00008110-001A2B3C4D5E6F70", text: $signer.deviceUDID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, design: .monospaced))
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.glassStroke, lineWidth: 1)
                        }
                }
                .foregroundColor(Theme.textPrimary)

            Text("Find UDID: Finder → iPhone → click serial until UDID appears, or Xcode → Devices, or SideStore.")
                .font(.caption2)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Preferences", icon: "slider.horizontal.3", color: Theme.accent)

            NavigationLink {
                AnisetteServerSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.accent.opacity(0.14))
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anisette catalog")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Servers list & health check")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Label("Appearance", systemImage: "moon.fill")
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("Dark")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Label("Haptics", systemImage: "hand.tap.fill")
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("On")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
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
