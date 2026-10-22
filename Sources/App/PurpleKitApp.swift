import SwiftUI

@main
struct PurpleKitApp: App {
    @StateObject private var registry = ToolRegistry.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(registry)
                .preferredColorScheme(.dark)
        }
    }
}
