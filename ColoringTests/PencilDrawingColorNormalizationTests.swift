import PencilKit
import UIKit
import XCTest

@testable import Coloring

final class PencilDrawingColorNormalizationTests: XCTestCase {
    func testNormalizingTexturedInkPreservesSeedMaskAndGeometry() throws {
        for inkType in [PKInk.InkType.crayon, .watercolor, .pencil] {
            let original = makeDrawing(inkType: inkType)
            let normalized = original.stableColorDrawing(using: UITraitCollection(userInterfaceStyle: .light))
            let restored = try PKDrawing(data: normalized.dataRepresentation())
            let before = try XCTUnwrap(original.strokes.first)
            let after = try XCTUnwrap(restored.strokes.first)

            XCTAssertEqual(after.randomSeed, before.randomSeed, "Color normalization must preserve \(inkType) texture.")
            XCTAssertEqual(after.transform, before.transform)
            XCTAssertEqual(after.mask, before.mask)
            XCTAssertEqual(after.path.count, before.path.count)
            for (point, restoredPoint) in zip(before.path, after.path) {
                XCTAssertEqual(restoredPoint.location, point.location)
                XCTAssertEqual(restoredPoint.size, point.size)
                XCTAssertEqual(restoredPoint.opacity, point.opacity)
                XCTAssertEqual(restoredPoint.force, point.force)
            }
        }
    }

    func testNormalizingConcreteCrayonColorPreservesRenderedArtwork() throws {
        let original = makeDrawing(inkType: .crayon)
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let normalized = original.stableColorDrawing(using: lightTraits)
        var beforeImage: UIImage?
        var afterImage: UIImage?
        lightTraits.performAsCurrent {
            beforeImage = original.image(from: CGRect(x: 0, y: 0, width: 128, height: 96), scale: 1)
            afterImage = normalized.image(from: CGRect(x: 0, y: 0, width: 128, height: 96), scale: 1)
        }
        let before = try pixels(XCTUnwrap(beforeImage))
        let after = try pixels(XCTUnwrap(afterImage))
        let changedChannels = zip(before, after).filter { abs(Int($0) - Int($1)) > 1 }.count
        XCTAssertEqual(changedChannels, 0, "Resolving an unchanged color must not redraw the crayon texture differently.")
    }

    #if compiler(>=6.4)
    func testNormalizingPreservesStrokeIdentityAndWetInkGroup() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Stroke identity requires iOS 27.") }
        var stroke = try XCTUnwrap(makeDrawing(inkType: .watercolor).strokes.first)
        stroke.renderGroupID = UUID()
        let drawing = PKDrawing(strokes: [stroke])
        XCTAssertEqual(drawing.strokes.first?.renderGroupID, stroke.renderGroupID)
        let normalized = drawing.stableColorDrawing(using: UITraitCollection(userInterfaceStyle: .light))
        let after = try XCTUnwrap(normalized.strokes.first)

        XCTAssertEqual(after.id, stroke.id)
        XCTAssertEqual(after.path.id, stroke.path.id)
        XCTAssertEqual(after.renderGroupID, stroke.renderGroupID)
    }
    #endif

    private func makeDrawing(inkType: PKInk.InkType) -> PKDrawing {
        let points = [CGPoint(x: 20, y: 40), CGPoint(x: 90, y: 40)].enumerated().map { index, location in
            PKStrokePoint(
                location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 22, height: 22), opacity: 0.7, force: 0.8,
                azimuth: 0.4, altitude: .pi / 3
            )
        }
        return PKDrawing(strokes: [PKStroke(
            ink: PKInk(inkType, color: UIColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 1)),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1)),
            transform: CGAffineTransform(translationX: 9, y: 7),
            mask: UIBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 45)),
            randomSeed: 123_456
        )])
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return bytes
    }
}
