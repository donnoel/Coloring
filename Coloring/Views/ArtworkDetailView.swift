import SwiftUI

struct ArtworkDetailView: View {
    let entry: ArtworkEntry
    @ObservedObject var viewModel: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    if let image = viewModel.fullImage(for: entry) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                minWidth: geometry.size.width,
                                minHeight: geometry.size.height
                            )
                    } else {
                        ContentUnavailableView(
                            "Image Not Found",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The artwork file could not be loaded.")
                        )
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                    }
                }
            }
            .navigationTitle(entry.sourceTemplateName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        if viewModel.fullImage(for: entry) != nil {
                            let url = URL(fileURLWithPath: entry.fullImagePath)
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }

                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete Artwork",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteEntry(entry.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This artwork will be permanently removed.")
            }
        }
    }
}
