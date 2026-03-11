import SwiftUI
import UIKit

struct ColoringColor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: opacity)
    }
}

extension ColoringColor {
    static let palette: [ColoringColor] = [
        ColoringColor(id: "sunset-red", name: "Sunset Red", red: 0.93, green: 0.28, blue: 0.27, opacity: 1.0),
        ColoringColor(id: "coral", name: "Coral", red: 0.98, green: 0.49, blue: 0.36, opacity: 1.0),
        ColoringColor(id: "amber", name: "Amber", red: 0.98, green: 0.68, blue: 0.19, opacity: 1.0),
        ColoringColor(id: "lemon", name: "Lemon", red: 0.99, green: 0.85, blue: 0.35, opacity: 1.0),
        ColoringColor(id: "mint", name: "Mint", red: 0.53, green: 0.83, blue: 0.58, opacity: 1.0),
        ColoringColor(id: "emerald", name: "Emerald", red: 0.14, green: 0.67, blue: 0.44, opacity: 1.0),
        ColoringColor(id: "teal", name: "Teal", red: 0.11, green: 0.67, blue: 0.66, opacity: 1.0),
        ColoringColor(id: "aqua", name: "Aqua", red: 0.28, green: 0.83, blue: 0.91, opacity: 1.0),
        ColoringColor(id: "ocean", name: "Ocean", red: 0.17, green: 0.51, blue: 0.89, opacity: 1.0),
        ColoringColor(id: "indigo", name: "Indigo", red: 0.27, green: 0.35, blue: 0.78, opacity: 1.0),
        ColoringColor(id: "violet", name: "Violet", red: 0.50, green: 0.36, blue: 0.86, opacity: 1.0),
        ColoringColor(id: "rose", name: "Rose", red: 0.88, green: 0.40, blue: 0.71, opacity: 1.0),
        ColoringColor(id: "fuchsia", name: "Fuchsia", red: 0.84, green: 0.20, blue: 0.53, opacity: 1.0),
        ColoringColor(id: "cocoa", name: "Cocoa", red: 0.55, green: 0.36, blue: 0.24, opacity: 1.0),
        ColoringColor(id: "sand", name: "Sand", red: 0.82, green: 0.70, blue: 0.54, opacity: 1.0),
        ColoringColor(id: "slate", name: "Slate", red: 0.43, green: 0.50, blue: 0.58, opacity: 1.0),
        ColoringColor(id: "charcoal", name: "Charcoal", red: 0.22, green: 0.24, blue: 0.30, opacity: 1.0),
        ColoringColor(id: "black", name: "Black", red: 0.00, green: 0.00, blue: 0.00, opacity: 1.0),
        ColoringColor(id: "white", name: "White", red: 1.00, green: 1.00, blue: 1.00, opacity: 1.0)
    ]

    static let defaultColorID = "sunset-red"
}
