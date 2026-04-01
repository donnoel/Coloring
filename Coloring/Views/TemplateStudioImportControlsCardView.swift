import SwiftUI

struct TemplateStudioImportControlsCardView: View {
    let onPhotosTap: () -> Void
    let onFilesTap: () -> Void
    let elevatedSidebarFill: AnyShapeStyle
    let controlSidebarFill: AnyShapeStyle
    let sidebarControlStroke: Color
    let liquidImportAccent: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(liquidImportAccent)
                    .padding(10)
                    .background(.regularMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add New Coloring Page")
                        .font(.headline.weight(.semibold))
                    Text("Import line-art from Photos or Files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: onPhotosTap) {
                    liquidImportButtonLabel(
                        title: "Photos",
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
                .buttonStyle(.plain)

                Button(action: onFilesTap) {
                    liquidImportButtonLabel(
                        title: "Files",
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(elevatedSidebarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(liquidImportAccent.opacity(0.75), lineWidth: 1)
                )
        }
    }

    private func liquidImportButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(controlSidebarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(sidebarControlStroke, lineWidth: 1)
                )
        }
    }
}
