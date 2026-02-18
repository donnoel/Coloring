import CoreGraphics
import SwiftUI

struct UnitPoint2D: Hashable, Sendable {
    let x: Double
    let y: Double

    func resolved(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (CGFloat(x) * rect.width),
            y: rect.minY + (CGFloat(y) * rect.height)
        )
    }
}

struct UnitSize2D: Hashable, Sendable {
    let width: Double
    let height: Double
}

enum SceneShape: Hashable, Sendable {
    case polygon([UnitPoint2D])
    case ellipse(center: UnitPoint2D, radius: UnitSize2D)
    case roundedRect(origin: UnitPoint2D, size: UnitSize2D, cornerRadius: Double)
    case line([UnitPoint2D])

    func path(in rect: CGRect) -> Path {
        switch self {
        case .polygon(let points):
            return polygonPath(points: points, in: rect)
        case let .ellipse(center, radius):
            return ellipsePath(center: center, radius: radius, in: rect)
        case let .roundedRect(origin, size, cornerRadius):
            return roundedRectPath(origin: origin, size: size, cornerRadius: cornerRadius, in: rect)
        case .line(let points):
            return linePath(points: points, in: rect)
        }
    }
}

private extension SceneShape {
    func polygonPath(points: [UnitPoint2D], in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        var path = Path()
        path.move(to: first.resolved(in: rect))

        for point in points.dropFirst() {
            path.addLine(to: point.resolved(in: rect))
        }

        path.closeSubpath()
        return path
    }

    func linePath(points: [UnitPoint2D], in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        var path = Path()
        path.move(to: first.resolved(in: rect))

        for point in points.dropFirst() {
            path.addLine(to: point.resolved(in: rect))
        }

        return path
    }

    func ellipsePath(center: UnitPoint2D, radius: UnitSize2D, in rect: CGRect) -> Path {
        let centerPoint = center.resolved(in: rect)
        let radiusWidth = CGFloat(radius.width) * rect.width
        let radiusHeight = CGFloat(radius.height) * rect.height

        let ellipseRect = CGRect(
            x: centerPoint.x - radiusWidth,
            y: centerPoint.y - radiusHeight,
            width: radiusWidth * 2,
            height: radiusHeight * 2
        )

        return Path(ellipseIn: ellipseRect)
    }

    func roundedRectPath(origin: UnitPoint2D, size: UnitSize2D, cornerRadius: Double, in rect: CGRect) -> Path {
        let originPoint = origin.resolved(in: rect)
        let width = CGFloat(size.width) * rect.width
        let height = CGFloat(size.height) * rect.height
        let radius = CGFloat(cornerRadius) * min(rect.width, rect.height)

        let roundedRect = CGRect(x: originPoint.x, y: originPoint.y, width: width, height: height)
        return Path(roundedRect: roundedRect, cornerRadius: radius)
    }
}
