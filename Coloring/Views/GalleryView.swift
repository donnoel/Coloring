import SwiftUI

struct GalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: GalleryViewModel
    @State private var selectedEntry: ArtworkEntry?
    @State private var carouselIndex = 0
    private let cardCornerRadius: CGFloat = 32

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    galleryBackground

                    if viewModel.entries.isEmpty {
                        if viewModel.isLoading {
                            galleryLoadingState
                        } else if let errorMessage = viewModel.errorMessage {
                            galleryErrorState(message: errorMessage)
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
                .accessibilityIdentifier("gallery.root")
                .ignoresSafeArea()
            }
            .navigationTitle("Gallery")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.loadEntries()
                syncCarouselIndex()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    return
                }

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
        VStack(spacing: 18) {
            galleryHeader

            if let errorMessage = viewModel.errorMessage {
                galleryInlineError(message: errorMessage)
            }

            artworkStage(in: size)

            carouselMeta

            thumbnailRail
        }
        .padding(.horizontal, horizontalContentPadding(for: size))
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    private var galleryLoadingState: some View {
        ProgressView("Loading Artwork…")
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.52), lineWidth: 1)
            )
    }

    private func galleryErrorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Gallery Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button {
                retryGalleryLoad()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 60)
    }

    private func galleryInlineError(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.88) : Color.primary.opacity(0.82))

            Spacer(minLength: 8)

            Button {
                retryGalleryLoad()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry Gallery Load")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(glassStrokeSoft, lineWidth: 1)
        )
    }

    private func artworkStage(in size: CGSize) -> some View {
        TabView(selection: $carouselIndex) {
            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                artworkCard(entry: entry, in: size)
                    .tag(index)
                    .padding(.horizontal, horizontalInset(for: size))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: carouselHeight(for: size))
    }

    private var galleryBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.03, green: 0.04, blue: 0.06),
                        Color(red: 0.05, green: 0.06, blue: 0.09),
                        Color(red: 0.08, green: 0.09, blue: 0.13)
                    ]
                    : [
                        Color(red: 0.72, green: 0.75, blue: 0.81),
                        Color(red: 0.63, green: 0.67, blue: 0.73),
                        Color(red: 0.56, green: 0.60, blue: 0.67)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.34, green: 0.49, blue: 0.69).opacity(colorScheme == .dark ? 0.20 : 0.13),
                    .clear
                ],
                center: .top,
                startRadius: 60,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(red: 0.38, green: 0.41, blue: 0.57).opacity(colorScheme == .dark ? 0.16 : 0.11),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 90,
                endRadius: 540
            )

            RadialGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.36 : 0.20),
                    .clear
                ],
                center: .bottom,
                startRadius: 40,
                endRadius: 460
            )
        }
    }

    private var galleryHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Artwork Gallery")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.95) : Color.primary)

                Text(activeEntry?.sourceTemplateName ?? "Browse your exported drawings")
                    .font(.subheadline)
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.74) : Color.primary.opacity(0.74))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(glassStrokeSoft, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 8, x: 0, y: 4)
    }

    private var carouselMeta: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(viewModel.entries.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index == carouselIndex
                                ? Color.white.opacity(colorScheme == .dark ? 0.84 : 0.94)
                                : Color.white.opacity(colorScheme == .dark ? 0.30 : 0.46)
                        )
                        .frame(width: index == carouselIndex ? 26 : 9, height: 9)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: carouselIndex)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(glassStrokeSoft, lineWidth: 1)
            )

            Spacer(minLength: 10)

            if let activeEntry {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                    Text(activeEntry.createdAt, style: .date)
                        .font(.footnote)
                }
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.80) : Color.primary.opacity(0.72))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(glassStrokeSoft, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var thumbnailRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(glassStrokeSoft, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 10, x: 0, y: 6)
    }

    private func thumbnailButton(entry: ArtworkEntry, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    isSelected
                        ? Color.white.opacity(colorScheme == .dark ? 0.24 : 0.50)
                        : Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06)
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
        .frame(width: 90, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(colorScheme == .dark ? 0.90 : 0.84) : Color.white.opacity(colorScheme == .dark ? 0.24 : 0.42),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.28 : 0), lineWidth: 1)
                .blur(radius: 2.0)
        )
        .shadow(
            color: Color.black.opacity(isSelected ? (colorScheme == .dark ? 0.38 : 0.18) : (colorScheme == .dark ? 0.12 : 0.04)),
            radius: isSelected ? 10 : 6,
            x: 0,
            y: isSelected ? 6 : 3
        )
        .scaleEffect(isSelected ? 1.015 : 0.985)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
    }

    private func artworkCard(entry: ArtworkEntry, in size: CGSize) -> some View {
        let previewHeight = previewHeight(for: size)

        return Button {
            selectedEntry = entry
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.42 : 0.18))
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))

                if let fullImage = viewModel.fullImage(for: entry) {
                    Image(uiImage: fullImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                } else if let thumbnail = viewModel.thumbnailImage(for: entry) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                RoundedRectangle(cornerRadius: cardCornerRadius - 6, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.24 : 0.40), lineWidth: 1)
                    .padding(4)
            }
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.16), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.34 : 0.50), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.48 : 0.24), radius: 34, x: 0, y: 20)
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
        let widthFactor: CGFloat = isLandscape ? 0.94 : 0.96
        return max(420, min(1240, size.width * widthFactor))
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        let heightFactor: CGFloat = isLandscape ? 0.66 : 0.60
        return max(380, min(860, size.height * heightFactor))
    }

    private func carouselHeight(for size: CGSize) -> CGFloat {
        previewHeight(for: size) + 18
    }

    private func horizontalContentPadding(for size: CGSize) -> CGFloat {
        size.width > size.height ? 20 : 14
    }

    private func horizontalInset(for size: CGSize) -> CGFloat {
        let usableWidth = size.width - (horizontalContentPadding(for: size) * 2)
        return max((usableWidth - cardWidth(for: size)) * 0.5, 6)
    }

    private var glassStrokeSoft: Color {
        Color.white.opacity(colorScheme == .dark ? 0.28 : 0.44)
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

    private func retryGalleryLoad() {
        Task {
            await viewModel.loadEntries()
            syncCarouselIndex()
        }
    }

    private var activeEntry: ArtworkEntry? {
        guard viewModel.entries.indices.contains(carouselIndex) else {
            return nil
        }
        return viewModel.entries[carouselIndex]
    }
}
