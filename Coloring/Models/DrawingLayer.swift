import SwiftUI
import Foundation

struct DrawingLayer: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var isVisible: Bool
    var drawingData: Data
    var order: Int

    init(id: UUID = UUID(), name: String, isVisible: Bool = true, drawingData: Data = Data(), order: Int = 0) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.drawingData = drawingData
        self.order = order
    }
}

struct LayerStack: Codable, Sendable, Equatable {
    var layers: [DrawingLayer]
    var activeLayerID: UUID

    init(layers: [DrawingLayer], activeLayerID: UUID) {
        self.layers = layers
        self.activeLayerID = activeLayerID
    }

    static func singleLayer(name: String = "Layer 1", drawingData: Data = Data()) -> LayerStack {
        let layer = DrawingLayer(name: name, drawingData: drawingData, order: 0)
        return LayerStack(layers: [layer], activeLayerID: layer.id)
    }

    var activeLayer: DrawingLayer? {
        layers.first { $0.id == activeLayerID }
    }

    var sortedLayers: [DrawingLayer] {
        layers.sorted { $0.order < $1.order }
    }

    var visibleLayers: [DrawingLayer] {
        sortedLayers.filter(\.isVisible)
    }

    mutating func addLayer(name: String) -> DrawingLayer {
        let maxOrder = layers.map(\.order).max() ?? -1
        let newLayer = DrawingLayer(name: name, order: maxOrder + 1)
        layers.append(newLayer)
        activeLayerID = newLayer.id
        return newLayer
    }

    mutating func removeLayer(_ id: UUID) {
        guard layers.count > 1 else {
            return
        }

        let wasActive = activeLayerID == id
        layers.removeAll { $0.id == id }

        if wasActive {
            activeLayerID = layers.first?.id ?? UUID()
        }

        reindexOrders()
    }

    mutating func toggleVisibility(_ id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else {
            return
        }
        layers[index].isVisible.toggle()
    }

    mutating func renameLayer(_ id: UUID, to name: String) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else {
            return
        }
        layers[index].name = name
    }

    mutating func updateDrawingData(_ data: Data, for layerID: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else {
            return
        }
        layers[index].drawingData = data
    }

    mutating func moveLayer(from source: IndexSet, to destination: Int) {
        var sorted = sortedLayers
        sorted.move(fromOffsets: source, toOffset: destination)

        for (index, layer) in sorted.enumerated() {
            if let layerIndex = layers.firstIndex(where: { $0.id == layer.id }) {
                layers[layerIndex].order = index
            }
        }
    }

    mutating func mergeDown(_ id: UUID) -> (upper: DrawingLayer, lower: DrawingLayer)? {
        let sorted = sortedLayers
        guard let upperIndex = sorted.firstIndex(where: { $0.id == id }),
              upperIndex + 1 < sorted.count
        else {
            return nil
        }

        let upper = sorted[upperIndex]
        let lower = sorted[upperIndex + 1]
        return (upper, lower)
    }

    private mutating func reindexOrders() {
        let sorted = sortedLayers
        for (index, layer) in sorted.enumerated() {
            if let layerIndex = layers.firstIndex(where: { $0.id == layer.id }) {
                layers[layerIndex].order = index
            }
        }
    }
}
