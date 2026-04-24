import Foundation
import UIKit

struct RecentColorToken: Codable, Hashable, Identifiable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    var id: String {
        hexString
    }

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(uiColor: UIColor, traitCollection: UITraitCollection? = UITraitCollection(userInterfaceStyle: .light)) {
        let stableColor = uiColor.stableResolvedColor(using: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard stableColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        self.init(
            red: Self.quantizedChannel(red),
            green: Self.quantizedChannel(green),
            blue: Self.quantizedChannel(blue),
            alpha: Self.quantizedChannel(alpha)
        )
    }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }

    var hexString: String {
        String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    private static func quantizedChannel(_ value: CGFloat) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}
