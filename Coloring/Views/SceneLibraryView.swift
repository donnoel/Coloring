import SwiftUI

struct SceneLibraryView: View {
    @ObservedObject var viewModel: ColoringBookViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick a scene")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.scenes) { scene in
                    Button {
                        viewModel.selectScene(scene.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(scene.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(scene.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(cardBackground(isSelected: scene.id == viewModel.selectedSceneID))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    scene.id == viewModel.selectedSceneID ? Color.white.opacity(0.95) : Color.white.opacity(0.35),
                                    lineWidth: scene.id == viewModel.selectedSceneID ? 2.0 : 1.0
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(.ultraThinMaterial)
        .navigationTitle("Coloring Book")
    }

    @ViewBuilder
    private func cardBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.46), Color.white.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.16))
        }
    }
}
