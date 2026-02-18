import Foundation

protocol SceneCatalogProviding: Sendable {
    func loadScenes() -> [ColoringScene]
}

struct SceneCatalogService: SceneCatalogProviding {
    func loadScenes() -> [ColoringScene] {
        [
            birdsAtSunriseScene,
            raceDayScene,
            oceanReefScene
        ]
    }
}

private extension SceneCatalogService {
    var birdsAtSunriseScene: ColoringScene {
        ColoringScene(
            id: "birds-sunrise",
            title: "Birds at Sunrise",
            subtitle: "Mountains, clouds, and birds gliding above the valley.",
            canvasAspectRatio: 4.0 / 3.0,
            regions: [
                SceneRegion(id: "sky", name: "Sky", shape: .polygon([
                    p(0.0, 0.0), p(1.0, 0.0), p(1.0, 0.62), p(0.0, 0.62)
                ])),
                SceneRegion(id: "sun", name: "Sun", shape: .ellipse(center: p(0.15, 0.18), radius: s(0.10, 0.12))),
                SceneRegion(id: "cloud-left", name: "Left Cloud", shape: .ellipse(center: p(0.34, 0.22), radius: s(0.12, 0.07))),
                SceneRegion(id: "cloud-right", name: "Right Cloud", shape: .ellipse(center: p(0.78, 0.18), radius: s(0.12, 0.07))),
                SceneRegion(id: "mountain-far", name: "Far Mountain", shape: .polygon([
                    p(0.07, 0.62), p(0.31, 0.29), p(0.54, 0.62)
                ])),
                SceneRegion(id: "mountain-near", name: "Near Mountain", shape: .polygon([
                    p(0.34, 0.62), p(0.62, 0.24), p(0.90, 0.62)
                ])),
                SceneRegion(id: "meadow", name: "Meadow", shape: .polygon([
                    p(0.0, 0.58), p(1.0, 0.58), p(1.0, 1.0), p(0.0, 1.0)
                ])),
                SceneRegion(id: "lake", name: "Lake", shape: .polygon([
                    p(0.22, 0.68), p(0.82, 0.66), p(0.74, 0.84), p(0.28, 0.86)
                ])),
                SceneRegion(id: "tree-trunk", name: "Tree Trunk", shape: .roundedRect(
                    origin: p(0.84, 0.60),
                    size: s(0.05, 0.25),
                    cornerRadius: 0.012
                )),
                SceneRegion(id: "tree-canopy", name: "Tree Canopy", shape: .ellipse(center: p(0.86, 0.55), radius: s(0.12, 0.13))),
                SceneRegion(id: "bird-1", name: "Bird One", shape: .polygon([
                    p(0.56, 0.18), p(0.60, 0.15), p(0.64, 0.18), p(0.60, 0.17)
                ])),
                SceneRegion(id: "bird-2", name: "Bird Two", shape: .polygon([
                    p(0.66, 0.24), p(0.70, 0.21), p(0.74, 0.24), p(0.70, 0.23)
                ])),
                SceneRegion(id: "bird-3", name: "Bird Three", shape: .polygon([
                    p(0.72, 0.14), p(0.76, 0.11), p(0.80, 0.14), p(0.76, 0.13)
                ]))
            ],
            detailStrokes: [
                SceneStroke(id: "horizon", shape: .line([p(0.0, 0.58), p(1.0, 0.58)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "ridge-far", shape: .line([p(0.16, 0.49), p(0.31, 0.29), p(0.43, 0.47)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "ridge-near", shape: .line([p(0.43, 0.54), p(0.62, 0.24), p(0.78, 0.49)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "tree-branch", shape: .line([p(0.87, 0.72), p(0.92, 0.68)]), normalizedLineWidth: 0.0022)
            ]
        )
    }

    var raceDayScene: ColoringScene {
        ColoringScene(
            id: "race-day",
            title: "Race Day Sprint",
            subtitle: "Two race cars speeding through the finish line.",
            canvasAspectRatio: 4.0 / 3.0,
            regions: [
                SceneRegion(id: "sky", name: "Sky", shape: .polygon([
                    p(0.0, 0.0), p(1.0, 0.0), p(1.0, 0.46), p(0.0, 0.46)
                ])),
                SceneRegion(id: "cloud", name: "Cloud", shape: .ellipse(center: p(0.22, 0.16), radius: s(0.12, 0.08))),
                SceneRegion(id: "grandstand", name: "Grandstand", shape: .polygon([
                    p(0.0, 0.34), p(1.0, 0.26), p(1.0, 0.50), p(0.0, 0.56)
                ])),
                SceneRegion(id: "infield", name: "Infield", shape: .polygon([
                    p(0.0, 0.56), p(1.0, 0.48), p(1.0, 0.73), p(0.0, 0.79)
                ])),
                SceneRegion(id: "track", name: "Track", shape: .polygon([
                    p(0.0, 0.70), p(1.0, 0.60), p(1.0, 1.0), p(0.0, 1.0)
                ])),
                SceneRegion(id: "lane-stripe", name: "Lane Stripe", shape: .polygon([
                    p(0.0, 0.79), p(1.0, 0.69), p(1.0, 0.74), p(0.0, 0.84)
                ])),
                SceneRegion(id: "car-a-body", name: "Car A Body", shape: .roundedRect(origin: p(0.14, 0.60), size: s(0.30, 0.12), cornerRadius: 0.02)),
                SceneRegion(id: "car-a-cabin", name: "Car A Cabin", shape: .roundedRect(origin: p(0.25, 0.57), size: s(0.12, 0.06), cornerRadius: 0.015)),
                SceneRegion(id: "car-a-wheel-front", name: "Car A Front Wheel", shape: .ellipse(center: p(0.20, 0.74), radius: s(0.04, 0.05))),
                SceneRegion(id: "car-a-wheel-rear", name: "Car A Rear Wheel", shape: .ellipse(center: p(0.38, 0.72), radius: s(0.04, 0.05))),
                SceneRegion(id: "car-b-body", name: "Car B Body", shape: .roundedRect(origin: p(0.52, 0.51), size: s(0.31, 0.12), cornerRadius: 0.02)),
                SceneRegion(id: "car-b-cabin", name: "Car B Cabin", shape: .roundedRect(origin: p(0.63, 0.48), size: s(0.12, 0.06), cornerRadius: 0.015)),
                SceneRegion(id: "car-b-wheel-front", name: "Car B Front Wheel", shape: .ellipse(center: p(0.58, 0.65), radius: s(0.04, 0.05))),
                SceneRegion(id: "car-b-wheel-rear", name: "Car B Rear Wheel", shape: .ellipse(center: p(0.77, 0.63), radius: s(0.04, 0.05))),
                SceneRegion(id: "finish-pole", name: "Finish Pole", shape: .roundedRect(origin: p(0.88, 0.20), size: s(0.02, 0.40), cornerRadius: 0.006)),
                SceneRegion(id: "finish-flag", name: "Finish Flag", shape: .roundedRect(origin: p(0.74, 0.22), size: s(0.22, 0.12), cornerRadius: 0.009))
            ],
            detailStrokes: [
                SceneStroke(id: "finish-grid-1", shape: .line([p(0.74, 0.26), p(0.96, 0.26)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "finish-grid-2", shape: .line([p(0.74, 0.30), p(0.96, 0.30)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "finish-grid-3", shape: .line([p(0.82, 0.22), p(0.82, 0.34)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "finish-grid-4", shape: .line([p(0.90, 0.22), p(0.90, 0.34)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "speed-line-a", shape: .line([p(0.06, 0.64), p(0.14, 0.62)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "speed-line-b", shape: .line([p(0.46, 0.56), p(0.53, 0.54)]), normalizedLineWidth: 0.0022)
            ]
        )
    }

    var oceanReefScene: ColoringScene {
        ColoringScene(
            id: "ocean-reef",
            title: "Ocean Reef",
            subtitle: "Fish, coral, and a turtle drifting over the reef.",
            canvasAspectRatio: 4.0 / 3.0,
            regions: [
                SceneRegion(id: "water", name: "Water", shape: .polygon([
                    p(0.0, 0.0), p(1.0, 0.0), p(1.0, 0.74), p(0.0, 0.74)
                ])),
                SceneRegion(id: "seabed", name: "Seabed", shape: .polygon([
                    p(0.0, 0.72), p(1.0, 0.68), p(1.0, 1.0), p(0.0, 1.0)
                ])),
                SceneRegion(id: "reef-left", name: "Left Reef", shape: .polygon([
                    p(0.08, 0.74), p(0.22, 0.56), p(0.35, 0.78), p(0.30, 0.96), p(0.12, 0.94)
                ])),
                SceneRegion(id: "reef-right", name: "Right Reef", shape: .polygon([
                    p(0.70, 0.72), p(0.86, 0.52), p(0.95, 0.74), p(0.90, 0.94), p(0.74, 0.94)
                ])),
                SceneRegion(id: "turtle-shell", name: "Turtle Shell", shape: .ellipse(center: p(0.50, 0.56), radius: s(0.12, 0.08))),
                SceneRegion(id: "turtle-head", name: "Turtle Head", shape: .ellipse(center: p(0.64, 0.56), radius: s(0.04, 0.04))),
                SceneRegion(id: "fish-1-body", name: "Fish One Body", shape: .ellipse(center: p(0.31, 0.40), radius: s(0.09, 0.05))),
                SceneRegion(id: "fish-1-tail", name: "Fish One Tail", shape: .polygon([
                    p(0.21, 0.40), p(0.15, 0.35), p(0.15, 0.45)
                ])),
                SceneRegion(id: "fish-2-body", name: "Fish Two Body", shape: .ellipse(center: p(0.72, 0.36), radius: s(0.09, 0.05))),
                SceneRegion(id: "fish-2-tail", name: "Fish Two Tail", shape: .polygon([
                    p(0.82, 0.36), p(0.88, 0.31), p(0.88, 0.41)
                ])),
                SceneRegion(id: "seaweed-left", name: "Seaweed Left", shape: .polygon([
                    p(0.36, 0.92), p(0.39, 0.74), p(0.43, 0.92)
                ])),
                SceneRegion(id: "seaweed-right", name: "Seaweed Right", shape: .polygon([
                    p(0.60, 0.92), p(0.63, 0.72), p(0.67, 0.92)
                ])),
                SceneRegion(id: "bubble-1", name: "Bubble One", shape: .ellipse(center: p(0.23, 0.25), radius: s(0.03, 0.03))),
                SceneRegion(id: "bubble-2", name: "Bubble Two", shape: .ellipse(center: p(0.27, 0.18), radius: s(0.02, 0.02))),
                SceneRegion(id: "bubble-3", name: "Bubble Three", shape: .ellipse(center: p(0.74, 0.20), radius: s(0.025, 0.025)))
            ],
            detailStrokes: [
                SceneStroke(id: "waterline", shape: .line([p(0.0, 0.72), p(1.0, 0.68)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "turtle-shell-detail-1", shape: .line([p(0.42, 0.56), p(0.58, 0.56)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "turtle-shell-detail-2", shape: .line([p(0.50, 0.49), p(0.50, 0.63)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "fish-1-fin", shape: .line([p(0.31, 0.40), p(0.31, 0.34)]), normalizedLineWidth: 0.0022),
                SceneStroke(id: "fish-2-fin", shape: .line([p(0.72, 0.36), p(0.72, 0.30)]), normalizedLineWidth: 0.0022)
            ]
        )
    }

    func p(_ x: Double, _ y: Double) -> UnitPoint2D {
        UnitPoint2D(x: x, y: y)
    }

    func s(_ width: Double, _ height: Double) -> UnitSize2D {
        UnitSize2D(width: width, height: height)
    }
}
