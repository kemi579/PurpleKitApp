import SwiftUI

@main
struct PurpleKitApp: App {
    @StateObject private var certs = CertificateStore.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(certs)
                .preferredColorScheme(.dark)
        }
    }
}
