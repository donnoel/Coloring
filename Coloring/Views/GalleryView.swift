import SwiftUI

struct GalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: GalleryViewModel
    @State private var selectedEntry: ArtworkEntry?
    @State private var carouselIndex = 0
    private let cardCornerRadius: CGFloat = 38

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
        VStack(spacing: 14) {
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
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private var galleryBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.05, green: 0.07, blue: 0.09),
                        Color(red: 0.08, green: 0.10, blue: 0.12),
                        Color(red: 0.10, green: 0.11, blue: 0.14)
                    ]
                    : [
                        Color(red: 0.96, green: 0.97, blue: 0.99),
                        Color(red: 0.95, green: 0.96, blue: 0.98),
                        Color(red: 0.95, green: 0.95, blue: 0.97)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16),
                    .clear
                ],
                center: .top,
                startRadius: 64,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(red: 0.38, green: 0.54, blue: 0.75).opacity(colorScheme == .dark ? 0.17 : 0.10),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 52,
                endRadius: 640
            )

            RadialGradient(
                colors: [
                    Color(red: 0.58, green: 0.63, blue: 0.82).opacity(colorScheme == .dark ? 0.16 : 0.10),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 80,
                endRadius: 600
            )
        }
    }

    private var galleryHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Artwork Gallery")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(activeEntry?.sourceTemplateName ?? "Browse your exported drawings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            floatingCounter
        }
    }

    private var floatingCounter: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.stack")
            Text("\(carouselIndex + 1) / \(viewModel.entries.count)")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.16 : 0.36), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(glassStrokeStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 10, x: 0, y: 5)
    }

    private var carouselMeta: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(viewModel.entries.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index == carouselIndex
                                ? Color.white.opacity(colorScheme == .dark ? 0.82 : 0.96)
                                : Color.white.opacity(colorScheme == .dark ? 0.28 : 0.50)
                        )
                        .frame(width: index == carouselIndex ? 26 : 9, height: 9)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: carouselIndex)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(glassStrokeSoft, lineWidth: 1)
            )

            Spacer(minLength: 0)

            if let activeEntry {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                    Text(activeEntry.createdAt, style: .date)
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(glassStrokeSoft, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 2)
    }

    private var thumbnailRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        let updateSelection = {
                            carouselIndex = index
                        }

                        if reduceMotion {
                            updateSelection()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2), updateSelection)
                        }
                    } label: {
                        thumbnailButton(entry: entry, isSelected: index == carouselIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.13 : 0.34),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(glassStrokeStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07), radius: 14, x: 0, y: 8)
    }

    private func thumbnailButton(entry: ArtworkEntry, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    isSelected
                        ? Color.white.opacity(colorScheme == .dark ? 0.28 : 0.62)
                        : Color.white.opacity(colorScheme == .dark ? 0.10 : 0.33)
                )

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
        .frame(width: 96, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(colorScheme == .dark ? 0.98 : 0.92) : glassStrokeSoft,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.24 : 0), lineWidth: 1)
                .blur(radius: 1.8)
        )
        .shadow(
            color: Color.black.opacity(isSelected ? (colorScheme == .dark ? 0.30 : 0.14) : (colorScheme == .dark ? 0.12 : 0.04)),
            radius: isSelected ? 16 : 8,
            x: 0,
            y: isSelected ? 10 : 4
        )
        .scaleEffect(isSelected ? 1.02 : 0.98)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
    }

    private func artworkCard(entry: ArtworkEntry, in size: CGSize) -> some View {
        let previewHeight = previewHeight(for: size)

        return Button {
            selectedEntry = entry
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.34),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                RoundedRectangle(cornerRadius: cardCornerRadius - 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [
                                    Color(red: 0.16, green: 0.18, blue: 0.23).opacity(0.78),
                                    Color(red: 0.09, green: 0.10, blue: 0.13).opacity(0.90)
                                ]
                                : [
                                    Color(red: 0.99, green: 1.00, blue: 1.00).opacity(0.95),
                                    Color(red: 0.95, green: 0.97, blue: 0.99).opacity(0.90)
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
                        .padding(30)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                RoundedRectangle(cornerRadius: cardCornerRadius - 8, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.50), lineWidth: 1)
            }
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(glassStrokeStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.13), radius: 34, x: 0, y: 20)
            .padding(.horizontal, 6)
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
        let widthFactor: CGFloat = isLandscape ? 0.92 : 0.95
        return max(360, min(1160, size.width * widthFactor))
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        let heightFactor: CGFloat = isLandscape ? 0.63 : 0.58
        return max(360, min(800, size.height * heightFactor))
    }

    private func carouselHeight(for size: CGSize) -> CGFloat {
        previewHeight(for: size) + 12
    }

    private func horizontalContentPadding(for size: CGSize) -> CGFloat {
        size.width > size.height ? 20 : 14
    }

    private func horizontalInset(for size: CGSize) -> CGFloat {
        let usableWidth = size.width - (horizontalContentPadding(for: size) * 2)
        return max((usableWidth - cardWidth(for: size)) * 0.5, 6)
    }

    private var glassStrokeSoft: Color {
        Color.white.opacity(colorScheme == .dark ? 0.32 : 0.62)
    }

    private var glassStrokeStrong: Color {
        Color.white.opacity(colorScheme == .dark ? 0.50 : 0.76)
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
