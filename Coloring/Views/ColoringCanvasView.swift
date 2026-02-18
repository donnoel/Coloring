import SwiftUI

struct ColoringCanvasView: View {
    let scene: ColoringScene
    let regionColors: [String: ColoringColor]
    var isInteractive: Bool = true
    var onRegionTapped: ((String) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let drawingRect = scene.drawingRect(in: geometry.size, padding: 20)

            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.95))

                ForEach(scene.regions) { region in
                    let regionPath = region.shape.path(in: drawingRect)
                    let fillColor = regionColors[region.id]?.swiftUIColor ?? .white

                    regionPath
                        .fill(fillColor)
                        .overlay(regionPath.stroke(Color.black, lineWidth: 2.2))
                        .onTapGesture {
                            guard isInteractive, let onRegionTapped else {
                                return
                            }

                            onRegionTapped(region.id)
                        }
                }

                ForEach(scene.detailStrokes) { stroke in
                    stroke.shape
                        .path(in: drawingRect)
                        .stroke(
                            Color.black,
                            style: StrokeStyle(
                                lineWidth: stroke.lineWidth(in: drawingRect),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.black, lineWidth: 2.6)
            }
            .padding(6)
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
        }
        .drawingGroup()
    }
}
