import Foundation
import PencilKit

enum InkType: String, Codable, CaseIterable, Sendable {
    case pen
    case marker
    case pencil
    case monoline
    case watercolor
    case crayon

    var pkInkType: PKInk.InkType {
        switch self {
        case .pen:
            return .pen
        case .marker:
            return .marker
        case .pencil:
            return .pencil
        case .monoline:
            return .monoline
        case .watercolor:
            return .watercolor
        case .crayon:
            return .crayon
        }
    }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .pencil: return "Pencil"
        case .monoline: return "Monoline"
        case .watercolor: return "Watercolor"
        case .crayon: return "Crayon"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .pencil: return "pencil"
        case .monoline: return "pencil.line"
        case .watercolor: return "paintbrush.pointed"
        case .crayon: return "paintbrush"
        }
    }
}

struct BrushPreset: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var inkType: InkType
    var width: CGFloat
    var opacity: CGFloat
    var isBuiltIn: Bool

    func makePKTool(color: UIColor = .black) -> PKInkingTool {
        let adjustedColor = color.withAlphaComponent(opacity)
        return PKInkingTool(inkType.pkInkType, color: adjustedColor, width: width)
    }

    static let builtInPresets: [BrushPreset] = [
        BrushPreset(
            id: "builtin-fine-pen",
            name: "Fine Pen",
            inkType: .pen,
            width: 2,
            opacity: 1.0,
            isBuiltIn: true
        ),
        BrushPreset(
            id: "builtin-marker",
            name: "Marker",
            inkType: .marker,
            width: 12,
            opacity: 1.0,
            isBuiltIn: true
        ),
        BrushPreset(
            id: "builtin-thick-marker",
            name: "Thick Marker",
            inkType: .marker,
            width: 28,
            opacity: 1.0,
            isBuiltIn: true
        ),
        BrushPreset(
            id: "builtin-crayon",
            name: "Crayon",
            inkType: .crayon,
            width: 18,
            opacity: 1.0,
            isBuiltIn: true
        ),
        BrushPreset(
            id: "builtin-watercolor",
            name: "Watercolor",
            inkType: .watercolor,
            width: 20,
            opacity: 0.5,
            isBuiltIn: true
        ),
        BrushPreset(
            id: "builtin-pencil",
            name: "Pencil",
            inkType: .pencil,
            width: 4,
            opacity: 1.0,
            isBuiltIn: true
        ),
        BrushPreset(
            id: "builtin-chalk",
            name: "Chalk",
            inkType: .pencil,
            width: 16,
            opacity: 0.6,
            isBuiltIn: true
        )
    ]

    static let defaultPresetID = "builtin-marker"
}
