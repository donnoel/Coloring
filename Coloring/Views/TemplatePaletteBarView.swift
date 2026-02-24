import SwiftUI

struct TemplatePaletteBarView: View {
    @Binding var isFillModeActive: Bool
    @Binding var selectedColorID: String
    var onClearFills: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                fillToggle

                Divider()
                    .frame(height: 28)

                if isFillModeActive {
                    colorPalette
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.26), lineWidth: 1)
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
    }

    private var fillToggle: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFillModeActive = false
                }
            } label: {
                Image(systemName: "pencil.tip")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFillModeActive ? .secondary : .primary)
                    .padding(8)
                    .background(
                        isFillModeActive ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Draw Mode")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFillModeActive = true
                }
            } label: {
                Image(systemName: "drop.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFillModeActive ? .primary : .secondary)
                    .padding(8)
                    .background(
                        isFillModeActive ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fill Mode")

            if isFillModeActive {
                Button {
                    onClearFills()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Fills")
            }
        }
    }

    private var colorPalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ColoringColor.palette) { color in
                    Button {
                        selectedColorID = color.id
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if color.id == selectedColorID {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2.5)
                                        .frame(width: 34, height: 34)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.name)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
