import SwiftUI

struct AppsView: View {
    @EnvironmentObject var certs: CertificateStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Apps")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.primaryGradient)
                            .padding(.top, 8)

                        // Install card
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "plus.app.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.primaryGradient)
                                Text("Install IPA")
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                            }
                            Text("Sideload any .ipa with your free Apple ID certificate. Use AltStore, SideStore or Sideloadly — then manage refreshes here.")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)

                            if certs.isLoggedIn {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(Theme.success)
                                    Text(certs.certStatusText)
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                            } else {
                                Text("Connect Apple ID in Settings first")
                                    .font(.caption)
                                    .foregroundColor(Theme.warning)
                            }
                        }
                        .padding(16)
                        .background(Theme.cardGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )

                        // How to
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "How to sideload", icon: "list.number", color: Theme.primaryLight)

                            step(1, "Settings → enter free Apple ID")
                            step(2, "Download IPA (GitHub Release / artifact)")
                            step(3, "AltStore / SideStore / Sideloadly → sign with same Apple ID")
                            step(4, "Refresh every 7 days (free cert limit)")
                        }

                        // Placeholder library
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Library", icon: "square.stack.3d.up.fill", color: Theme.accent)

                            EmptyStateView(
                                icon: "app.dashed",
                                title: "No apps yet",
                                message: "Installed sideloaded apps will show up here in a future update."
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Theme.primaryGradient)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
