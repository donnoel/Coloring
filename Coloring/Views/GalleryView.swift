import SwiftUI

struct GalleryView: View {
    @ObservedObject var viewModel: GalleryViewModel
    @State private var selectedEntry: ArtworkEntry?
    @State private var carouselIndex = 0
    private let cardCornerRadius: CGFloat = 30

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    galleryBackground

                    if viewModel.entries.isEmpty {
                        if viewModel.isLoading {
                            ProgressView("Loading Artwork…")
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.52), lineWidth: 1)
                                )
                        } else {
                            ContentUnavailableView(
                                "No Artwork Yet",
                                systemImage: "photo.on.rectangle.angled",
                                description: Text("Export drawings from the Studio to see them here.")
                            )
                            .padding(.top, 60)
                        }
                    } else {
                        galleryContent(in: geometry.size)
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

    private func galleryContent(in size: CGSize) -> some View {
        VStack(spacing: 16) {
            galleryHeader

            TabView(selection: $carouselIndex) {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    artworkCard(entry: entry, in: size)
                        .tag(index)
                        .padding(.horizontal, horizontalInset(for: size))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: carouselHeight(for: size))

            carouselMeta

            thumbnailRail
        }
        .padding(.horizontal, horizontalContentPadding(for: size))
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private var galleryBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.96, blue: 1.00),
                    Color(red: 0.93, green: 0.92, blue: 0.99),
                    Color(red: 0.99, green: 0.93, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.33, green: 0.63, blue: 0.98).opacity(0.20),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color(red: 0.77, green: 0.55, blue: 0.93).opacity(0.18),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 24,
                endRadius: 560
            )
        }
    }

    private var galleryHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Artwork Gallery")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.82))

                Text(activeEntry?.sourceTemplateName ?? "Browse your exported drawings")
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "photo.stack")
                Text("\(carouselIndex + 1) / \(viewModel.entries.count)")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.66), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.66), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private var carouselMeta: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(viewModel.entries.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index == carouselIndex
                                ? Color.white.opacity(0.96)
                                : Color.white.opacity(0.50)
                        )
                        .frame(width: index == carouselIndex ? 26 : 9, height: 9)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: carouselIndex)

            Spacer(minLength: 0)

            if let activeEntry {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption2.weight(.semibold))
                    Text(activeEntry.createdAt, style: .date)
                        .font(.footnote)
                }
                .foregroundStyle(Color.black.opacity(0.64))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        )
    }

    private var thumbnailRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            carouselIndex = index
                        }
                    } label: {
                        thumbnailButton(entry: entry, isSelected: index == carouselIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.64), lineWidth: 1)
        )
    }

    private func thumbnailButton(entry: ArtworkEntry, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.58) : Color.white.opacity(0.34))

            if let thumbnail = viewModel.thumbnailImage(for: entry) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            } else {
                Image(systemName: "photo")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 94, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(0.96) : Color.white.opacity(0.50),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.05), radius: 10, x: 0, y: 6)
    }

    private func artworkCard(entry: ArtworkEntry, in size: CGSize) -> some View {
        let previewHeight = previewHeight(for: size)

        return Button {
            selectedEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: cardCornerRadius - 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.88),
                                    Color(red: 0.97, green: 0.99, blue: 1.00).opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.40),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius - 6, style: .continuous))
                        )

                    if let thumbnail = viewModel.thumbnailImage(for: entry) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(22)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                }
                .frame(height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius - 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius - 6, style: .continuous)
                        .stroke(Color.white.opacity(0.74), lineWidth: 1)
                )
                .padding(12)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.66), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 12)
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
        let widthFactor: CGFloat = isLandscape ? 0.90 : 0.94
        return max(360, min(1160, size.width * widthFactor))
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        let heightFactor: CGFloat = isLandscape ? 0.60 : 0.54
        return max(360, min(800, size.height * heightFactor))
    }

    private func carouselHeight(for size: CGSize) -> CGFloat {
        previewHeight(for: size) + 36
    }

    private func horizontalContentPadding(for size: CGSize) -> CGFloat {
        size.width > size.height ? 20 : 14
    }

    private func horizontalInset(for size: CGSize) -> CGFloat {
        let usableWidth = size.width - (horizontalContentPadding(for: size) * 2)
        return max((usableWidth - cardWidth(for: size)) * 0.5, 6)
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

    private var activeEntry: ArtworkEntry? {
        guard viewModel.entries.indices.contains(carouselIndex) else {
            return nil
        }
        return viewModel.entries[carouselIndex]
    }
}
