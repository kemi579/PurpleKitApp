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

                    if !certs.isLoggedIn {
                        Spacer()
                        EmptyStateView(
                            icon: "apple.logo",
                            title: "Connect Apple ID",
                            message: "Open Settings and sign in with your free Apple ID."
                        )
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                EmptyStateView(
                                    icon: "app.dashed",
                                    title: "No apps",
                                    message: "Sideloaded apps will appear here."
                                )
                                .padding(.top, 40)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}
