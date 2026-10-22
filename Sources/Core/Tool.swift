import SwiftUI

protocol Tool: Identifiable {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var category: ToolCategory { get }
    var description: String { get }
    @ViewBuilder var content: AnyView { get }
}

extension Tool {
    var content: AnyView {
        AnyView(EmptyView())
    }
}

enum ToolCategory: String, CaseIterable, Identifiable {
    case text = "Text"
    case hash = "Hash"
    case generator = "Generator"
    case qr = "QR"
    case converter = "Converter"
    case network = "Network"
    case device = "Device"
    case notes = "Notes"
    case future = "Coming Soon"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .text: return "textformat"
        case .hash: return "number"
        case .generator: return "key.fill"
        case .qr: return "qrcode"
        case .converter: return "arrow.triangle.2.circlepath"
        case .network: return "network"
        case .device: return "iphone"
        case .notes: return "note.text"
        case .future: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .text: return Color(hex: "A78BFA")
        case .hash: return Color(hex: "C084FC")
        case .generator: return Color(hex: "E879F9")
        case .qr: return Color(hex: "F0ABFC")
        case .converter: return Color(hex: "818CF8")
        case .network: return Color(hex: "67E8F9")
        case .device: return Color(hex: "34D399")
        case .notes: return Color(hex: "FBBF24")
        case .future: return Color(hex: "94A3B8")
        }
    }
}

struct AnyTool: Identifiable {
    let id: String
    let name: String
    let icon: String
    let category: ToolCategory
    let description: String
    let viewBuilder: () -> AnyView

    init<T: Tool>(_ tool: T) {
        self.id = tool.id
        self.name = tool.name
        self.icon = tool.icon
        self.category = tool.category
        self.description = tool.description
        self.viewBuilder = { tool.content }
    }

    var content: AnyView {
        viewBuilder()
    }
}
