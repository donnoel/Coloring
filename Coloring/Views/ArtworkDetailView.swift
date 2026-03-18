import SwiftUI
import UIKit

struct ArtworkDetailView: View {
    let entry: ArtworkEntry
    @ObservedObject var viewModel: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        let fullImage = viewModel.fullImage(for: entry)

        NavigationStack {
            GeometryReader { geometry in
                if let image = fullImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
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
            .navigationTitle(entry.sourceTemplateName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if fullImage != nil {
                        Button {
                            presentShareSheet()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Image(systemName: "trash")
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

    private func presentShareSheet() {
        let activityItems: [Any]
        if let image = viewModel.fullImage(for: entry) {
            activityItems = [image]
        } else {
            activityItems = [URL(fileURLWithPath: entry.fullImagePath)]
        }

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let keyWindow = windowScene.windows.first(where: \.isKeyWindow),
              let rootViewController = keyWindow.rootViewController
        else {
            return
        }

        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(
                x: rootViewController.view.bounds.midX,
                y: rootViewController.view.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }

        topViewController.present(activityViewController, animated: true)
    }
}
