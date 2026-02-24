import SwiftUI

struct LayerPanelView: View {
    @ObservedObject var viewModel: TemplateStudioViewModel
    @State private var editingLayerID: UUID?
    @State private var editingName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            layerList
        }
        .frame(width: 260, height: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("Layers")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                viewModel.addLayer()
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Layer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var layerList: some View {
        List {
            ForEach(viewModel.currentLayerStack.sortedLayers) { layer in
                layerRow(layer)
            }
            .onMove { source, destination in
                viewModel.moveLayer(from: source, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func layerRow(_ layer: DrawingLayer) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleLayerVisibility(layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.caption)
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? "Hide Layer" : "Show Layer")

            if editingLayerID == layer.id {
                TextField("Name", text: $editingName, onCommit: {
                    viewModel.renameLayer(layer.id, to: editingName)
                    editingLayerID = nil
                })
                .textFieldStyle(.plain)
                .font(.caption)
            } else {
                Text(layer.name)
                    .font(.caption)
                    .foregroundStyle(
                        layer.id == viewModel.currentLayerStack.activeLayerID ? .primary : .secondary
                    )
                    .lineLimit(1)
                    .onTapGesture {
                        viewModel.selectActiveLayer(layer.id)
                    }
                    .onLongPressGesture {
                        editingLayerID = layer.id
                        editingName = layer.name
                    }
            }

            Spacer()

            if layer.id == viewModel.currentLayerStack.activeLayerID {
                Image(systemName: "pencil.tip")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(
            layer.id == viewModel.currentLayerStack.activeLayerID
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
        .contextMenu {
            Button {
                editingLayerID = layer.id
                editingName = layer.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                viewModel.mergeDown(layer.id)
            } label: {
                Label("Merge Down", systemImage: "arrow.down.doc")
            }
            .disabled(isBottomLayer(layer))

            Divider()

            Button(role: .destructive) {
                viewModel.deleteLayer(layer.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(viewModel.currentLayerStack.layers.count <= 1)
        }
    }

    private func isBottomLayer(_ layer: DrawingLayer) -> Bool {
        let sorted = viewModel.currentLayerStack.sortedLayers
        return sorted.last?.id == layer.id
    }
}
