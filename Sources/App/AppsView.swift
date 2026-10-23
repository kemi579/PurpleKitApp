import SwiftUI

struct AppsView: View {
    @EnvironmentObject var certs: CertificateStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Text("Apps")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.primaryGradient)
                        Spacer()
                        // status pill
                        HStack(spacing: 6) {
                            Circle()
                                .fill(certs.isCertHealthy ? Theme.success : (certs.isLoggedIn ? Theme.warning : Theme.textSecondary))
                                .frame(width: 8, height: 8)
                            Text(certs.isLoggedIn ? certs.certStatusText : "No Apple ID")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceElevated)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    ScrollView {
                        VStack(spacing: 16) {
                            NavigationLink {
                                IPAImportView()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.title2.weight(.semibold))
                                        .foregroundColor(Theme.primaryLight)
                                        .frame(width: 46, height: 46)
                                        .background(Theme.primaryLight.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("IPA Library")
                                            .font(.headline)
                                            .foregroundColor(Theme.textPrimary)
                                        Text("Import and manage IPA files")
                                            .font(.caption)
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(16)
                                .background(Theme.cardGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)

                            EmptyStateView(
                                icon: certs.isLoggedIn ? "app.dashed" : "apple.logo",
                                title: certs.isLoggedIn ? "No installed apps" : "Apple sign-in unavailable",
                                message: certs.isLoggedIn
                                    ? "Installed-app discovery and device installation are not implemented yet."
                                    : "You can import IPA files now. Apple ID authentication and signing are not implemented yet; saving an email in Settings does not sign you in."
                            )
                            .padding(.top, 24)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}
