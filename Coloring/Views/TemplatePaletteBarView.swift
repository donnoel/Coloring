import SwiftUI

struct TemplatePaletteBarView: View {
    @Environment(\.colorScheme) private var colorScheme

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
        VStack(spacing: 5) {
            paletteControls

            if !recentColors.isEmpty {
                Capsule()
                    .fill(paletteSeparatorColor)
                    .frame(width: 204)
                    .frame(height: 1)

                recentColorSwatches
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(paletteContainerStroke, lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.09), radius: 10, y: 3)
    }

    private var recentColorSwatches: some View {
        HStack(spacing: 6) {
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
            ZStack {
                Circle()
                    .fill(Color(uiColor: token.uiColor))
                    .frame(width: 21, height: 21)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    }
            }
            .frame(width: 36, height: 36)
            .background(
                recentColorButtonFill(isSelected: isSelected),
                in: Circle()
            )
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.62), lineWidth: 1.5)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent Color")
        .accessibilityValue(token.hexString)
        .accessibilityHint("Sets this as the active drawing color.")
    }

    private var paletteControls: some View {
        HStack(spacing: 8) {
            Button {
                onToggleLibrary()
            } label: {
                controlChrome(isSelected: isLibraryVisible) {
                    Image(systemName: "sidebar.leading")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isLibraryVisible ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Library")

            Button {
                onTogglePalettePlacement()
            } label: {
                controlChrome(isSelected: false) {
                    Image(systemName: isPaletteAtTop ? "arrow.down.circle" : "arrow.up.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaletteAtTop ? "Move Toolbar to Bottom" : "Move Toolbar to Top")

            Capsule()
                .fill(paletteSeparatorColor)
                .frame(width: 1)
                .frame(height: 20)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFillModeActive = false
                }
            } label: {
                controlChrome(isSelected: !isFillModeActive) {
                    Image(systemName: "pencil.tip")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isFillModeActive ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Draw Mode")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFillModeActive = true
                }
            } label: {
                controlChrome(isSelected: isFillModeActive) {
                    Image(systemName: "drop.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isFillModeActive ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fill Mode")

            Button {
                onUndo()
            } label: {
                controlChrome(isSelected: false, isEnabled: canUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canUndo ? .secondary : .tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)
            .contentShape(Rectangle())
            .accessibilityLabel("Undo")

            Button {
                onRedo()
            } label: {
                controlChrome(isSelected: false, isEnabled: canRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canRedo ? .secondary : .tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canRedo)
            .contentShape(Rectangle())
            .accessibilityLabel("Redo")
        }
    }

    private func controlChrome<Content: View>(
        isSelected: Bool,
        isEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: 36, height: 36)
            .background(
                controlFill(isSelected: isSelected, isEnabled: isEnabled),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(controlStroke(isSelected: isSelected, isEnabled: isEnabled), lineWidth: isSelected ? 1 : 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func controlFill(isSelected: Bool, isEnabled: Bool) -> AnyShapeStyle {
        guard isEnabled else {
            return AnyShapeStyle(Color.clear)
        }

        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.11))
        }

        return AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035))
    }

    private func controlStroke(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return Color.clear
        }

        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.26)
        }

        return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
    }

    private func recentColorButtonFill(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.08)
        }

        return Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.03)
    }

    private var paletteContainerStroke: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.14)
        }

        return Color.white.opacity(0.32)
    }

    private var paletteSeparatorColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.065)
    }
}
