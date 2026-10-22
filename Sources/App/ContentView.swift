import SwiftUI

// Legacy entry kept for reference — app uses MainTabView.
// Tool detail sheet host.

struct ToolDetailView: View {
    let tool: AnyTool
    @EnvironmentObject var registry: ToolRegistry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.primaryLight)
                    }
                    Spacer()
                    Text(tool.name)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Button {
                        registry.toggleFavorite(tool.id)
                    } label: {
                        Image(systemName: registry.isFavorite(tool.id) ? "star.fill" : "star")
                            .foregroundColor(registry.isFavorite(tool.id) ? Theme.warning : Theme.textSecondary)
                    }
                }
                .padding()
                .background(Theme.surface.opacity(0.9))

                tool.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
    }
}

extension AnyTool: Hashable {
    static func == (lhs: AnyTool, rhs: AnyTool) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
