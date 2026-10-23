import SwiftUI

struct AppsView: View {
    @EnvironmentObject var certs: CertificateStore

    var body: some View {
        NavigationStack {
            ZStack {
                // Ambient is already drawn by MainTabView; keep local fallback transparent
                Color.clear

                VStack(spacing: 0) {
                    // Header
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PurpleKit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                            Text("Apps")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Theme.primaryGradient)
                        }

                        Spacer()

                        StatusPill(
                            text: certs.isLoggedIn ? certs.certStatusText : "No Apple ID",
                            color: certs.isCertHealthy
                                ? Theme.success
                                : (certs.isLoggedIn ? Theme.warning : Theme.textTertiary)
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            NavigationLink {
                                IPAImportView()
                            } label: {
                                GlassLinkCard(
                                    icon: "square.and.arrow.down.fill",
                                    title: "IPA Library",
                                    subtitle: "Import and manage IPA files",
                                    iconColor: Theme.primaryLight
                                )
                            }
                            .buttonStyle(.plain)

                            // Quick tip card
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.neon)

                                Text("Sign in via Settings → Apple ID to request a development certificate for signing.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .glassCard(cornerRadius: 16, intensity: 0.75)

                            EmptyStateView(
                                icon: certs.isLoggedIn ? "app.dashed" : "apple.logo",
                                title: certs.isLoggedIn ? "No installed apps" : "Ready to sideload",
                                message: certs.isLoggedIn
                                    ? "Installed-app discovery and device installation are not implemented yet."
                                    : "Import an IPA now. Apple ID authentication and certificate requests live in Settings."
                            )
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 110)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}
