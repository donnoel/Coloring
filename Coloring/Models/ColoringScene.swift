import CoreGraphics
import Foundation

struct SceneRegion: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let shape: SceneShape
}

struct SceneStroke: Identifiable, Hashable, Sendable {
    let id: String
    let shape: SceneShape
    let normalizedLineWidth: Double

    func lineWidth(in rect: CGRect) -> CGFloat {
        max(1.5, CGFloat(normalizedLineWidth) * min(rect.width, rect.height))
    }
}

struct ColoringScene: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let canvasAspectRatio: Double
    let regions: [SceneRegion]
    let detailStrokes: [SceneStroke]

    func drawingRect(in availableSize: CGSize, padding: CGFloat = 18) -> CGRect {
        let safeWidth = max(0, availableSize.width - (padding * 2))
        let safeHeight = max(0, availableSize.height - (padding * 2))
        guard safeWidth > 0, safeHeight > 0 else {
            return CGRect(origin: .zero, size: .zero)
        }

        let targetAspect = max(0.1, canvasAspectRatio)
        let safeAspect = safeWidth / safeHeight

        let fittedSize: CGSize
        if safeAspect > targetAspect {
            let height = safeHeight
            let width = height * targetAspect
            fittedSize = CGSize(width: width, height: height)
        } else {
            let width = safeWidth
            let height = width / targetAspect
            fittedSize = CGSize(width: width, height: height)
        }

        let origin = CGPoint(
            x: ((availableSize.width - fittedSize.width) / 2).rounded(.toNearestOrEven),
            y: ((availableSize.height - fittedSize.height) / 2).rounded(.toNearestOrEven)
        )

        return CGRect(origin: origin, size: fittedSize)
    }

    static let defaultExportSize = CGSize(width: 2200, height: 1650)
}
