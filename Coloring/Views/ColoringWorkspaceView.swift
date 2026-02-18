import SwiftUI

struct ColoringWorkspaceView: View {
    @ObservedObject var viewModel: ColoringBookViewModel

    var body: some View {
        Group {
            if let scene = viewModel.selectedScene {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sceneHeader(scene)

                        ColoringCanvasView(
                            scene: scene,
                            regionColors: viewModel.currentSceneRegionColors,
                            isInteractive: true,
                            onRegionTapped: { regionID in
                                viewModel.applyColor(to: regionID)
                            }
                        )
                        .frame(minHeight: 420)
                        .background(
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )

                        palettePanel
                        exportPanel
                    }
                    .padding(20)
                }
                .navigationTitle(scene.title)
            } else {
                ContentUnavailableView(
                    "No Scenes Available",
                    systemImage: "scribble.variable",
                    description: Text("Add scenes to start coloring.")
                )
            }
        }
    }

    @ViewBuilder
    private func sceneHeader(_ scene: ColoringScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scene.title)
                .font(.largeTitle.weight(.bold))

            Text(scene.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Choose a color, then tap any outlined area to paint it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.40), lineWidth: 1)
        )
    }

    private var palettePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rich Palette")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.palette) { color in
                        PaletteSwatchButton(
                            color: color,
                            isSelected: color.id == viewModel.selectedColorID,
                            action: {
                                viewModel.selectColor(color.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            if let selectedColor = viewModel.selectedColor {
                Text("Selected color: \(selectedColor.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.clearCurrentScene()
            } label: {
                Label("Clear This Scene", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canClearCurrentScene)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.headline)

            Button {
                Task {
                    await viewModel.exportCurrentScene()
                }
            } label: {
                Label("Export PNG", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isExporting)

            if viewModel.isExporting {
                ProgressView("Preparing image…")
                    .font(.subheadline)
            }

            if let exportStatusMessage = viewModel.exportStatusMessage {
                Text(exportStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let exportedFileURL = viewModel.exportedFileURL {
                ShareLink(item: exportedFileURL) {
                    Label("Share Export", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
            }

            if let exportErrorMessage = viewModel.exportErrorMessage {
                Text(exportErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct PaletteSwatchButton: View {
    let color: ColoringColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.22), lineWidth: 0.8)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                )
                .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(color.name))
    }
}
