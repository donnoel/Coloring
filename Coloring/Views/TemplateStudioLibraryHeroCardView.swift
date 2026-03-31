import SwiftUI

struct TemplateStudioLibraryHeroCardView: View {
    let visibleCount: Int
    let importedCount: Int
    let onCollapseTap: () -> Void
    let elevatedSidebarFill: AnyShapeStyle
    let sidebarCardStroke: Color
    let controlSidebarFill: AnyShapeStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "paintpalette.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.62, blue: 0.97),
                                    Color(red: 0.18, green: 0.82, blue: 0.62)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drawing Library")
                            .font(.headline.weight(.semibold))
                        Text("Organize, import, and color with one workspace.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
                libraryCollapseButton
            }

            HStack(spacing: 8) {
                sidebarMetricPill(value: visibleCount, label: "Visible")
                sidebarMetricPill(value: importedCount, label: "Imported")
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(elevatedSidebarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(sidebarCardStroke, lineWidth: 1)
                )
        }
    }

    private var libraryCollapseButton: some View {
        Button(action: onCollapseTap) {
            Image(systemName: "sidebar.leading")
                .font(.subheadline.weight(.semibold))
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide Library")
        .accessibilityHint("Collapse the drawing library and focus on the canvas.")
    }

    private func sidebarMetricPill(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(controlSidebarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
