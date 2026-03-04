import PencilKit
import UIKit

extension UIColor {
    nonisolated func stableResolvedColor(using traitCollection: UITraitCollection?) -> UIColor {
        let resolvedColor = traitCollection.map { self.resolvedColor(with: $0) } ?? self
        let stableSRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        if let normalizedColor = resolvedColor.cgColor.converted(
            to: stableSRGBColorSpace,
            intent: .defaultIntent,
            options: nil
        ) {
            return UIColor(cgColor: normalizedColor)
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        var white: CGFloat = 0
        if resolvedColor.getWhite(&white, alpha: &alpha) {
            return UIColor(white: white, alpha: alpha)
        }

        return resolvedColor
    }
}

extension PKInkingTool {
    nonisolated func stableResolvedTool(using traitCollection: UITraitCollection?) -> PKInkingTool {
        let normalizedColor = color.stableResolvedColor(using: traitCollection)
        if color.isEqual(normalizedColor) {
            return self
        }

        return PKInkingTool(inkType, color: normalizedColor, width: width)
    }
}

extension PKDrawing {
    nonisolated func stableColorDrawing(using traitCollection: UITraitCollection?) -> PKDrawing {
        guard !strokes.isEmpty else {
            return self
        }

        var didChangeStrokeColor = false
        let normalizedStrokes = strokes.map { stroke in
            let normalizedColor = stroke.ink.color.stableResolvedColor(using: traitCollection)
            guard !stroke.ink.color.isEqual(normalizedColor) else {
                return stroke
            }

            didChangeStrokeColor = true
            return PKStroke(
                ink: PKInk(stroke.ink.inkType, color: normalizedColor),
                path: stroke.path,
                transform: stroke.transform,
                mask: stroke.mask
            )
        }

        guard didChangeStrokeColor else {
            return self
        }

        return PKDrawing(strokes: normalizedStrokes)
    }
}
