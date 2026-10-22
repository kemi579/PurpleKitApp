import SwiftUI

@main
struct PurpleKitApp: App {
    @StateObject private var registry = ToolRegistry.shared
    @StateObject private var certs = CertificateStore.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(registry)
                .environmentObject(certs)
                .preferredColorScheme(.dark)
        }
    }
}
