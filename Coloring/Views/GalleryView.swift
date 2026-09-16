import SwiftUI

struct GalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: GalleryViewModel
    let requestedEntryID: String?
    @State private var selectedEntry: ArtworkEntry?
    @State private var carouselIndex = 0

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
            .onChange(of: requestedEntryID) { _, _ in
                syncCarouselIndex()
            }
            .fullScreenCover(item: $selectedEntry) { entry in
                ArtworkDetailView(entry: entry, viewModel: viewModel)
            }
        }
    }

    private func galleryContent(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            galleryTopBar

            if let errorMessage = viewModel.errorMessage {
                galleryInlineError(message: errorMessage)
                    .padding(.top, 12)
            }

            artworkStage(in: size)
            galleryCaption
                .padding(.top, 2)

            thumbnailRail
                .padding(.horizontal, 46)
                .padding(.top, 16)
        }
        .padding(.horizontal, horizontalContentPadding(for: size))
        .padding(.top, 24)
        .padding(.bottom, 18)
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
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func artworkStage(in size: CGSize) -> some View {
        ZStack {
            TabView(selection: $carouselIndex) {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    artworkCard(entry: entry)
                        .tag(index)
                        .padding(.horizontal, artworkHorizontalInset(for: size))
                        .padding(.vertical, 14)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                carouselNavigationButton(direction: .previous)
                Spacer()
                carouselNavigationButton(direction: .next)
            }
            .padding(.horizontal, 2)
        }
        .frame(height: carouselHeight(for: size))
    }

    private var galleryBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.035, green: 0.045, blue: 0.065),
                        Color(red: 0.055, green: 0.050, blue: 0.075)
                    ]
                    : [
                        Color(red: 1.00, green: 0.985, blue: 0.955),
                        Color(red: 0.945, green: 0.985, blue: 1.00)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.13),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color(red: 1.00, green: 0.42, blue: 0.54).opacity(colorScheme == .dark ? 0.14 : 0.10),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 700
            )

            RadialGradient(
                colors: [
                    Color(red: 1.00, green: 0.78, blue: 0.28).opacity(colorScheme == .dark ? 0.08 : 0.07),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 540
            )
        }
    }

    private var galleryTopBar: some View {
        HStack {
            Spacer()

            Text("\(carouselIndex + 1) of \(viewModel.entries.count)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityLabel("Artwork \(carouselIndex + 1) of \(viewModel.entries.count)")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var galleryCaption: some View {
        if let activeEntry {
            Text(activeEntry.sourceTemplateName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var thumbnailRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            selectCarouselIndex(index)
                        } label: {
                            thumbnailButton(entry: entry, isSelected: index == carouselIndex)
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
            }
            .onAppear {
                scrollActiveThumbnail(using: proxy, animated: false)
            }
            .onChange(of: carouselIndex) { _, _ in
                scrollActiveThumbnail(using: proxy, animated: !reduceMotion)
            }
        }
        .frame(height: 76)
        .mask(
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .background(timelineBackdrop)
    }

    private var timelineBackdrop: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.42, blue: 0.54)
                            .opacity(colorScheme == .dark ? 0.12 : 0.10),
                        Color(red: 1.00, green: 0.78, blue: 0.28)
                            .opacity(colorScheme == .dark ? 0.10 : 0.08),
                        Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.12)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.48), lineWidth: 1)
            )
            .shadow(
                color: Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                radius: 18,
                y: 8
            )
    }

    private func thumbnailButton(entry: ArtworkEntry, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.08)
                        : Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.78 : 0.65)
                )

            if let thumbnail = viewModel.thumbnailImage(for: entry) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Image(systemName: "photo")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 78, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.90) : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(
            color: Color.black.opacity(isSelected ? (colorScheme == .dark ? 0.32 : 0.13) : 0),
            radius: isSelected ? 8 : 0,
            x: 0,
            y: isSelected ? 4 : 0
        )
        .scaleEffect(isSelected ? 1.06 : 1)
        .opacity(isSelected ? 1 : 0.90)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(entry.sourceTemplateName)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func artworkCard(entry: ArtworkEntry) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            ZStack {
                if let fullImage = viewModel.fullImage(for: entry) {
                    galleryArtworkImage(fullImage)
                } else if let thumbnail = viewModel.thumbnailImage(for: entry) {
                    galleryArtworkImage(thumbnail)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(entry.sourceTemplateName)")
        .accessibilityHint("Shows the artwork full screen")
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteEntry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func galleryArtworkImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.14),
                radius: 24,
                x: 0,
                y: 14
            )
            .shadow(
                color: Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08),
                radius: 34,
                x: 0,
                y: 8
            )
    }

    private func carouselHeight(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        let heightFactor: CGFloat = isLandscape ? 0.68 : 0.64
        return max(390, min(880, size.height * heightFactor))
    }

    private func artworkHorizontalInset(for size: CGSize) -> CGFloat {
        size.width > size.height ? 74 : 62
    }

    private func horizontalContentPadding(for size: CGSize) -> CGFloat {
        size.width > size.height ? 20 : 14
    }

    private enum CarouselDirection {
        case previous
        case next
    }

    private func carouselNavigationButton(direction: CarouselDirection) -> some View {
        let isPrevious = direction == .previous
        let isDisabled = isPrevious
            ? carouselIndex <= 0
            : carouselIndex >= viewModel.entries.count - 1

        return Button {
            moveCarousel(by: isPrevious ? -1 : 1)
        } label: {
            Image(systemName: isPrevious ? "chevron.left" : "chevron.right")
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
                .background(
                    isDisabled
                        ? Color(uiColor: .secondarySystemBackground).opacity(0.74)
                        : Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.20),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(
                            isDisabled ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.50),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isDisabled
                        ? Color.clear
                        : Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    radius: 12,
                    y: 5
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.24 : 0.92)
        .accessibilityLabel(isPrevious ? "Previous Artwork" : "Next Artwork")
    }

    private func moveCarousel(by offset: Int) {
        selectCarouselIndex(carouselIndex + offset)
    }

    private func selectCarouselIndex(_ index: Int) {
        guard viewModel.entries.indices.contains(index) else {
            return
        }

        if reduceMotion {
            carouselIndex = index
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                carouselIndex = index
            }
        }
    }

    private func scrollActiveThumbnail(using proxy: ScrollViewProxy, animated: Bool) {
        guard let activeEntry else {
            return
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(activeEntry.id, anchor: .center)
            }
        } else {
            proxy.scrollTo(activeEntry.id, anchor: .center)
        }
    }

    private func syncCarouselIndex() {
        guard !viewModel.entries.isEmpty else {
            carouselIndex = 0
            return
        }

        if let requestedEntryID,
           let requestedIndex = viewModel.entries.firstIndex(where: { $0.id == requestedEntryID })
        {
            carouselIndex = requestedIndex
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
