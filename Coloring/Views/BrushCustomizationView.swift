import SwiftUI

struct BrushCustomizationView: View {
    @ObservedObject var viewModel: TemplateStudioViewModel
    @State private var isSavePresetAlertPresented = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            presetGrid
            Divider()
            sliders
        }
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        )
        .alert("Save Custom Brush", isPresented: $isSavePresetAlertPresented) {
            TextField("Brush name", text: $newPresetName)
            Button("Cancel", role: .cancel) {
                newPresetName = ""
            }
            Button("Save") {
                saveCustomPreset()
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for your custom brush preset.")
        }
    }

    private var header: some View {
        HStack {
            Text("Brushes")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                newPresetName = ""
                isSavePresetAlertPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save Custom Brush")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var presetGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72, maximum: 90), spacing: 8)],
                spacing: 8
            ) {
                ForEach(viewModel.allBrushPresets) { preset in
                    presetButton(preset)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 200)
    }

    private func presetButton(_ preset: BrushPreset) -> some View {
        let isSelected = preset.id == viewModel.activeBrushPreset.id

        return Button {
            viewModel.selectBrushPreset(preset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.inkType.systemImage)
                    .font(.title3)
                    .frame(height: 24)

                Text(preset.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !preset.isBuiltIn {
                Button(role: .destructive) {
                    viewModel.deleteCustomPreset(preset.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var sliders: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "lineweight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text("Width")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: $viewModel.customBrushWidth,
                    in: 1...50,
                    step: 0.5
                )

                Text(String(format: "%.1f", viewModel.customBrushWidth))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text("Opacity")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: $viewModel.customBrushOpacity,
                    in: 0.05...1.0,
                    step: 0.05
                )

                Text(String(format: "%.0f%%", viewModel.customBrushOpacity * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            // Brush preview stroke
            brushPreview
        }
        .padding(14)
    }

    private var brushPreview: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let startX: CGFloat = 10
            let endX = size.width - 10
            let brushWidth = min(viewModel.customBrushWidth, size.height - 4)

            var path = Path()
            path.move(to: CGPoint(x: startX, y: midY))
            // Gentle S-curve
            path.addCurve(
                to: CGPoint(x: endX, y: midY),
                control1: CGPoint(x: size.width * 0.35, y: midY - 10),
                control2: CGPoint(x: size.width * 0.65, y: midY + 10)
            )

            context.opacity = viewModel.customBrushOpacity
            context.stroke(
                path,
                with: .color(.primary),
                style: StrokeStyle(lineWidth: brushWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func saveCustomPreset() {
        let trimmedName = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        viewModel.saveCurrentAsPreset(name: trimmedName)
        newPresetName = ""
    }
}
