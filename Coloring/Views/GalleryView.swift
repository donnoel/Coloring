import SwiftUI

struct GalleryView: View {
    @ObservedObject var viewModel: GalleryViewModel
    @State private var selectedEntry: ArtworkEntry?

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Artwork Yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Export drawings from the Studio to see them here.")
                    )
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.entries) { entry in
                            artworkCard(entry)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Gallery")
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                HStack {
                    Text("Gallery")
                        .font(.largeTitle.weight(.bold))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .task {
                await viewModel.loadEntries()
            }
            .onAppear {
                Task {
                    await viewModel.loadEntries()
                }
            }
            .sheet(item: $selectedEntry) { entry in
                ArtworkDetailView(entry: entry, viewModel: viewModel)
            }
        }
    }

    private func artworkCard(_ entry: ArtworkEntry) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            VStack(spacing: 0) {
                if let thumbnail = viewModel.thumbnailImage(for: entry) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 160)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sourceTemplateName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text(entry.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
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
}
