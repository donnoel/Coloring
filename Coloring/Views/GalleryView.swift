import SwiftUI

struct GalleryView: View {
    @ObservedObject var viewModel: GalleryViewModel
    @State private var selectedEntry: ArtworkEntry?
    private let cardSpacing: CGFloat = 18

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let cardWidth = carouselCardWidth(for: geometry.size)
                let sideInset = max((geometry.size.width - cardWidth) * 0.5, 20)

                ScrollView(.horizontal) {
                    if viewModel.entries.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            "No Artwork Yet",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Export drawings from the Studio to see them here.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 80)
                    } else {
                        LazyHStack(alignment: .top, spacing: cardSpacing) {
                            ForEach(viewModel.entries) { entry in
                                artworkCard(entry)
                                    .frame(width: cardWidth)
                                    .scrollTransition(axis: .horizontal) { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                                            .opacity(phase.isIdentity ? 1.0 : 0.86)
                                    }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, sideInset)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    }
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Gallery")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.loadEntries()
            }
            .onAppear {
                Task {
                    await viewModel.loadEntries()
                }
            }
            .fullScreenCover(item: $selectedEntry) { entry in
                ArtworkDetailView(entry: entry, viewModel: viewModel)
            }
        }
    }

    private func carouselCardWidth(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        let widthFactor: CGFloat = isLandscape ? 0.46 : 0.74
        return max(280, min(560, size.width * widthFactor))
    }

    private func artworkCard(_ entry: ArtworkEntry) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                let aspectRatio = previewAspectRatio(for: entry)

                if let thumbnail = viewModel.thumbnailImage(for: entry) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sourceTemplateName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(entry.createdAt, style: .date)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteEntry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func previewAspectRatio(for entry: ArtworkEntry) -> CGFloat {
        guard let image = viewModel.thumbnailImage(for: entry), image.size.height > 0 else {
            return 4 / 3
        }

        let ratio = image.size.width / image.size.height
        return min(max(ratio, 0.72), 1.6)
    }
}
