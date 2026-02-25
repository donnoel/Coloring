import SwiftUI

struct GalleryView: View {
    @ObservedObject var viewModel: GalleryViewModel
    @State private var selectedEntry: ArtworkEntry?
    @State private var carouselIndex = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    galleryBackground

                    if viewModel.entries.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            "No Artwork Yet",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Export drawings from the Studio to see them here.")
                        )
                        .padding(.top, 60)
                    } else {
                        VStack(spacing: 14) {
                            TabView(selection: $carouselIndex) {
                                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                                    artworkCard(entry: entry, in: geometry.size)
                                        .tag(index)
                                        .padding(.horizontal, horizontalInset(for: geometry.size))
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(height: carouselHeight(for: geometry.size))

                            carouselMeta

                            thumbnailRail
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 14)
                    }
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Gallery")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.loadEntries()
                syncCarouselIndex()
            }
            .onAppear {
                Task {
                    await viewModel.loadEntries()
                    syncCarouselIndex()
                }
            }
            .onChange(of: viewModel.entries.map(\.id)) { _, _ in
                syncCarouselIndex()
            }
            .fullScreenCover(item: $selectedEntry) { entry in
                ArtworkDetailView(entry: entry, viewModel: viewModel)
            }
        }
    }

    private var galleryBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.80, green: 0.88, blue: 0.96),
                    Color(red: 0.76, green: 0.84, blue: 0.93),
                    Color(red: 0.85, green: 0.78, blue: 0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.37, green: 0.56, blue: 0.84).opacity(0.32),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 500
            )

            RadialGradient(
                colors: [
                    Color(red: 0.98, green: 0.57, blue: 0.66).opacity(0.24),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 380
            )
        }
    }

    private var carouselMeta: some View {
        VStack(spacing: 10) {
            if !viewModel.entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                    Text("\(carouselIndex + 1) of \(viewModel.entries.count)")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.70))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.44), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                )
            }

            HStack(spacing: 6) {
                ForEach(viewModel.entries.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index == carouselIndex
                                ? Color.white.opacity(0.94)
                                : Color.white.opacity(0.44)
                        )
                        .frame(width: index == carouselIndex ? 24 : 8, height: 8)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: carouselIndex)
        }
    }

    private var thumbnailRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            carouselIndex = index
                        }
                    } label: {
                        thumbnailButton(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                index == carouselIndex
                                    ? Color.white.opacity(0.95)
                                    : Color.white.opacity(0.44),
                                lineWidth: index == carouselIndex ? 2 : 1
                            )
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func thumbnailButton(entry: ArtworkEntry) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.30))

            if let thumbnail = viewModel.thumbnailImage(for: entry) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Image(systemName: "photo")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 72, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func artworkCard(entry: ArtworkEntry, in size: CGSize) -> some View {
        let previewHeight = previewHeight(for: size)

        return Button {
            selectedEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.90),
                                    Color(red: 0.94, green: 0.96, blue: 1.00)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let thumbnail = viewModel.thumbnailImage(for: entry) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(14)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGray5))
                    }
                }
                .frame(height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.70), lineWidth: 1)
                )
                .padding(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.sourceTemplateName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(entry.createdAt, style: .date)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.11), radius: 18, x: 0, y: 10)
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

    private func cardWidth(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        let widthFactor: CGFloat = isLandscape ? 0.60 : 0.88
        return max(320, min(860, size.width * widthFactor))
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        return isLandscape ? 300 : 380
    }

    private func carouselHeight(for size: CGSize) -> CGFloat {
        previewHeight(for: size) + 98
    }

    private func horizontalInset(for size: CGSize) -> CGFloat {
        max((size.width - cardWidth(for: size)) * 0.5, 16)
    }

    private func syncCarouselIndex() {
        guard !viewModel.entries.isEmpty else {
            carouselIndex = 0
            return
        }

        if carouselIndex >= viewModel.entries.count {
            carouselIndex = viewModel.entries.count - 1
        }
    }
}
