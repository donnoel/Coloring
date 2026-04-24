import SwiftUI

struct TemplatePaletteBarView: View {
    @Binding var isFillModeActive: Bool
    var canUndo: Bool
    var canRedo: Bool
    var recentColors: [RecentColorToken]
    var activeColorToken: RecentColorToken?
    var isPaletteAtTop: Bool
    var isLibraryVisible: Bool
    var onToggleLibrary: () -> Void
    var onTogglePalettePlacement: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSelectRecentColor: (RecentColorToken) -> Void

    var body: some View {
        VStack(spacing: 8) {
            fillToggle

            if !recentColors.isEmpty {
                Divider()
                    .frame(width: 220)
                    .opacity(0.55)

                recentColorSwatches
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

    private var recentColorSwatches: some View {
        HStack(spacing: 8) {
            ForEach(recentColors) { token in
                recentColorButton(token)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func recentColorButton(_ token: RecentColorToken) -> some View {
        let isSelected = token == activeColorToken

        return Button {
            onSelectRecentColor(token)
        } label: {
            Circle()
                .fill(Color(uiColor: token.uiColor))
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                }
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.85), lineWidth: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent Color")
        .accessibilityValue(token.hexString)
        .accessibilityHint("Sets this as the active drawing color.")
    }

    private var fillToggle: some View {
        HStack(spacing: 8) {
            Button {
                onToggleLibrary()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isLibraryVisible ? .primary : .secondary)
                    .padding(8)
                    .background(
                        isLibraryVisible ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Library")

            Button {
                onTogglePalettePlacement()
            } label: {
                Image(systemName: isPaletteAtTop ? "arrow.down.circle" : "arrow.up.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(
                        AnyShapeStyle(.regularMaterial),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaletteAtTop ? "Move Toolbar to Bottom" : "Move Toolbar to Top")

            Divider()
                .frame(height: 20)

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

            Button {
                onUndo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(canUndo ? .secondary : .tertiary)
                    .padding(8)
                    .background(
                        canUndo ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)
            .contentShape(Rectangle())
            .accessibilityLabel("Undo")

            Button {
                onRedo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(canRedo ? .secondary : .tertiary)
                    .padding(8)
                    .background(
                        canRedo ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canRedo)
            .contentShape(Rectangle())
            .accessibilityLabel("Redo")
        }
    }
}
