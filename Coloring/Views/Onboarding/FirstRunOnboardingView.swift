import SwiftUI

struct FirstRunOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentPage = 0
    let onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Pick a Page, Start Fast",
            subtitle: "Browse built-in scenes or imports, choose a page, and jump straight into coloring in Studio.",
            badges: [
                .init(icon: "rectangle.stack.fill", title: "Built-In + Imported"),
                .init(icon: "sparkles", title: "Fun Scenes"),
                .init(icon: "play.fill", title: "Open in One Tap")
            ],
            palette: .init(
                primary: Color(red: 0.16, green: 0.60, blue: 0.97),
                secondary: Color(red: 0.18, green: 0.80, blue: 0.66),
                tertiary: Color(red: 0.98, green: 0.67, blue: 0.20),
                quaternary: Color(red: 0.95, green: 0.37, blue: 0.41)
            ),
            hero: .studio
        ),
        OnboardingPage(
            title: "Coloring Feels Instant",
            subtitle: "Import from Photos or Files, color with Apple Pencil, and blend draw + fill to bring each page to life.",
            badges: [
                .init(icon: "photo.on.rectangle.angled", title: "Photos + Files"),
                .init(icon: "applepencil", title: "Apple Pencil + PencilKit"),
                .init(icon: "drop.fill", title: "Draw + Fill"),
                .init(icon: "arrow.uturn.backward.circle.fill", title: "Undo + Redo")
            ],
            palette: .init(
                primary: Color(red: 0.09, green: 0.67, blue: 0.97),
                secondary: Color(red: 0.17, green: 0.84, blue: 0.63),
                tertiary: Color(red: 0.99, green: 0.58, blue: 0.20),
                quaternary: Color(red: 0.99, green: 0.39, blue: 0.38)
            ),
            hero: .importColor
        ),
        OnboardingPage(
            title: "Keep Every Page Organized",
            subtitle: "Sort by Favorites, In Progress, and Completed. Hide what you do not need, and keep imports + progress synced with iCloud.",
            badges: [
                .init(icon: "folder.badge.gearshape", title: "Categories"),
                .init(icon: "eye.slash", title: "Hidden Management"),
                .init(icon: "icloud", title: "iCloud")
            ],
            palette: .init(
                primary: Color(red: 0.37, green: 0.60, blue: 0.98),
                secondary: Color(red: 0.54, green: 0.49, blue: 0.92),
                tertiary: Color(red: 0.97, green: 0.62, blue: 0.26),
                quaternary: Color(red: 0.16, green: 0.74, blue: 0.63)
            ),
            hero: .organize
        ),
        OnboardingPage(
            title: "Gallery and Share",
            subtitle: "Send finished artwork to Gallery, open details, share what you made, and remove pieces anytime.",
            badges: [
                .init(icon: "square.and.arrow.up", title: "Send to Gallery"),
                .init(icon: "photo.stack", title: "Browse Finished Artwork"),
                .init(icon: "trash", title: "Share + Delete")
            ],
            palette: .init(
                primary: Color(red: 0.14, green: 0.66, blue: 0.97),
                secondary: Color(red: 0.19, green: 0.80, blue: 0.65),
                tertiary: Color(red: 0.97, green: 0.57, blue: 0.22),
                quaternary: Color(red: 0.93, green: 0.35, blue: 0.40)
            ),
            hero: .gallery
        )
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                onboardingBackground

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 26)
                        .padding(.top, 16)

                    TabView(selection: $currentPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingPageView(
                                page: page,
                                colorScheme: colorScheme,
                                isCurrentPage: index == currentPage,
                                reduceMotion: reduceMotion
                            )
                            .frame(maxWidth: min(geometry.size.width * 0.93, 880))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: currentPage)

                    footer
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                        .padding(.bottom, 18)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [currentPageData.palette.primary, currentPageData.palette.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "paintpalette.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    )

                Text("Coloring")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.94) : Color.primary.opacity(0.90))

            Spacer()

            Button("Skip") {
                onComplete()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.90) : Color.primary.opacity(0.76))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.30 : 0.44), lineWidth: 1)
            )
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            progressPanel

            Button {
                continueOrComplete()
            } label: {
                HStack(spacing: 8) {
                    Text(isLastPage ? "Get Started" : "Continue")
                        .font(.headline.weight(.semibold))
                    Image(systemName: isLastPage ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [
                            currentPageData.palette.primary,
                            currentPageData.palette.secondary,
                            currentPageData.palette.tertiary
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.46), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var progressPanel: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(currentPage + 1) of \(pages.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.78) : Color.primary.opacity(0.66))

                Text(currentPageData.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : Color.primary.opacity(0.86))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(progressFill(for: index))
                        .frame(width: index == currentPage ? 34 : 11, height: 10)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentPage)
                }
            }

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [currentPageData.palette.primary, currentPageData.palette.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("\(currentPage + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.30),
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.44), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 8, x: 0, y: 4)
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.05, green: 0.06, blue: 0.10),
                        Color(red: 0.07, green: 0.09, blue: 0.14),
                        Color(red: 0.10, green: 0.08, blue: 0.13)
                    ]
                    : [
                        Color(red: 0.95, green: 0.97, blue: 1.00),
                        Color(red: 0.94, green: 0.97, blue: 0.99),
                        Color(red: 0.98, green: 0.96, blue: 0.99)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(currentPageData.palette.primary.opacity(colorScheme == .dark ? 0.30 : 0.20))
                .frame(width: 520, height: 520)
                .blur(radius: 58)
                .offset(x: 310, y: -300)

            Circle()
                .fill(currentPageData.palette.tertiary.opacity(colorScheme == .dark ? 0.26 : 0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 54)
                .offset(x: -280, y: -240)

            Circle()
                .fill(currentPageData.palette.secondary.opacity(colorScheme == .dark ? 0.30 : 0.19))
                .frame(width: 560, height: 560)
                .blur(radius: 60)
                .offset(x: -250, y: 320)

            Circle()
                .fill(currentPageData.palette.quaternary.opacity(colorScheme == .dark ? 0.24 : 0.14))
                .frame(width: 480, height: 480)
                .blur(radius: 58)
                .offset(x: 290, y: 320)
        }
        .ignoresSafeArea()
    }

    private var currentPageData: OnboardingPage {
        pages[currentPage]
    }

    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    private func continueOrComplete() {
        guard !isLastPage else {
            onComplete()
            return
        }

        let next = min(currentPage + 1, pages.count - 1)
        if reduceMotion {
            currentPage = next
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                currentPage = next
            }
        }
    }

    private func progressFill(for index: Int) -> AnyShapeStyle {
        if index == currentPage {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [currentPageData.palette.primary, currentPageData.palette.secondary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }

        return AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? 0.30 : 0.50))
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let colorScheme: ColorScheme
    let isCurrentPage: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeroCard(page: page, colorScheme: colorScheme)
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .scaleEffect(!reduceMotion && isCurrentPage ? 1 : 0.986)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: isCurrentPage)

            VStack(alignment: .leading, spacing: 8) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.96) : Color.primary)
                    .minimumScaleFactor(0.84)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.80) : Color.primary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            WrapHStack(spacing: 8, lineSpacing: 8) {
                ForEach(page.badges, id: \.title) { badge in
                    OnboardingBadgeView(
                        badge: badge,
                        palette: page.palette,
                        colorScheme: colorScheme
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.30 : 0.62), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.11), radius: 16, x: 0, y: 10)
        )
    }

    private var heroHeight: CGFloat {
        switch page.hero {
        case .importColor:
            return 388
        case .gallery:
            return 372
        default:
            return 344
        }
    }
}

private struct OnboardingHeroCard: View {
    let page: OnboardingPage
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            page.palette.primary.opacity(colorScheme == .dark ? 0.62 : 0.54),
                            page.palette.secondary.opacity(colorScheme == .dark ? 0.58 : 0.48),
                            page.palette.tertiary.opacity(colorScheme == .dark ? 0.48 : 0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .fill(page.palette.quaternary.opacity(colorScheme == .dark ? 0.30 : 0.20))
                        .frame(width: 220, height: 220)
                        .blur(radius: 22)
                        .offset(x: 160, y: -120)
                }
                .overlay {
                    Circle()
                        .fill(page.palette.primary.opacity(colorScheme == .dark ? 0.25 : 0.16))
                        .frame(width: 240, height: 240)
                        .blur(radius: 24)
                        .offset(x: -140, y: 110)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.42), lineWidth: 1)
                )

            Group {
                switch page.hero {
                case .studio:
                    studioHero
                case .importColor:
                    importColorHero
                case .organize:
                    organizeHero
                case .gallery:
                    galleryHero
                }
            }
            .padding(22)
        }
    }

    private var studioHero: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                heroLabel("Drawing Library", icon: "rectangle.stack.fill")

                VStack(spacing: 9) {
                    studioLibraryRow(
                        title: "Rainy Window Cat",
                        subtitle: "Built-in · Easy",
                        tint: page.palette.secondary,
                        accent: page.palette.tertiary
                    )
                    studioLibraryRow(
                        title: "Winter Cabin",
                        subtitle: "Selected · Easy",
                        tint: page.palette.primary,
                        accent: page.palette.quaternary,
                        isSelected: true
                    )
                    studioLibraryRow(
                        title: "Sunflower Path",
                        subtitle: "Built-in · Easy",
                        tint: page.palette.tertiary,
                        accent: page.palette.primary
                    )
                }
            }
            .frame(maxWidth: 240)

            VStack(spacing: 10) {
                heroLabel("Studio Canvas", icon: "paintbrush.pointed.fill")

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                Color.white.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        VStack(spacing: 9) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Selected Drawing")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("Winter Cabin")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary.opacity(0.90))
                                }
                                Spacer(minLength: 0)
                                heroMiniPill(title: "Ready")
                            }

                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.92),
                                            page.palette.primary.opacity(0.18),
                                            page.palette.secondary.opacity(0.14)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 108)
                                .overlay(
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.84))
                                            .frame(width: 130, height: 84)
                                            .overlay(
                                                halfColoredArtworkPreview(
                                                    imageName: "OnboardingWinterCabin",
                                                    cornerRadius: 9
                                                )
                                                .padding(6)
                                            )

                                        VStack(alignment: .leading, spacing: 7) {
                                            Text("File")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Capsule(style: .continuous)
                                                .fill(page.palette.primary.opacity(0.44))
                                                .frame(width: 156, height: 9)
                                            Capsule(style: .continuous)
                                                .fill(page.palette.secondary.opacity(0.38))
                                                .frame(width: 144, height: 9)

                                            Text("Winter Cabin")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)

                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(page.palette.primary)
                                                    .frame(width: 9, height: 9)
                                                Circle()
                                                    .fill(page.palette.secondary)
                                                    .frame(width: 9, height: 9)
                                                Circle()
                                                    .fill(page.palette.tertiary)
                                                    .frame(width: 9, height: 9)
                                                Spacer(minLength: 0)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                )

                            HStack(spacing: 8) {
                                heroChip(title: "Browse", icon: "square.grid.2x2")
                                heroChip(title: "Open Drawing", icon: "play.fill")
                            }
                        }
                        .padding(12)
                    )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var importColorHero: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                heroChip(title: "Photos", icon: "photo.on.rectangle.angled")
                heroChip(title: "Files", icon: "folder.fill")
                Spacer(minLength: 0)
                heroMiniPill(title: "Import")
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            toolOrb(icon: "applepencil", tint: page.palette.primary)
                            toolOrb(icon: "drop.fill", tint: page.palette.secondary)
                            toolOrb(icon: "arrow.uturn.backward", tint: page.palette.tertiary)
                            toolOrb(icon: "arrow.uturn.forward", tint: page.palette.quaternary)
                            toolOrb(icon: "trash", tint: page.palette.primary.opacity(0.90))
                        }

                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.40),
                                        Color.white.opacity(0.24)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 214)
                            .overlay(
                                VStack(spacing: 10) {
                                    HStack(spacing: 8) {
                                        heroMiniPill(title: "Photos")
                                        Image(systemName: "arrow.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        heroMiniPill(title: "Canvas")
                                        Spacer(minLength: 0)
                                        heroMiniPill(title: "Fill On")
                                    }

                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.84))
                                        .frame(height: 168)
                                        .overlay(
                                            halfColoredArtworkPreview(
                                                imageName: "OnboardingGalleryVenice",
                                                cornerRadius: 10
                                            )
                                                .padding(.horizontal, 8)
                                        )
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            )

                        HStack(spacing: 10) {
                            ForEach(0..<6, id: \.self) { index in
                                Circle()
                                    .fill(heroPaletteColor(index))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.50), lineWidth: 1)
                                    )
                            }
                            Spacer(minLength: 0)
                            HStack(spacing: 8) {
                                heroMiniPill(title: "Draw")
                                heroMiniPill(title: "Undo")
                                heroMiniPill(title: "Clear")
                            }
                        }
                    }
                    .padding(14)
                )
        }
    }

    private var organizeHero: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                heroLabel("Collections", icon: "folder.badge.gearshape")
                categoryRow(title: "In Progress", icon: "paintpalette.fill", tint: page.palette.primary, detail: "8")
                categoryRow(title: "Favorites", icon: "star.fill", tint: page.palette.tertiary, detail: "14")
                categoryRow(title: "Completed", icon: "checkmark.seal.fill", tint: page.palette.secondary, detail: "26")
                categoryRow(title: "Hidden", icon: "eye.slash.fill", tint: page.palette.quaternary, detail: "5")
            }
            .frame(maxWidth: 248)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.86))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    halfColoredArtworkPreview(
                                        imageName: "OnboardingAlienAstronaut",
                                        cornerRadius: 8
                                    )
                                    .padding(3)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Astronaut on Alien Planet")
                                    .font(.subheadline.weight(.semibold))
                                Text("In Progress · Synced")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(page.palette.primary.opacity(0.92))
                        }

                        Text("Long-press for quick actions")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            heroMiniPill(title: "Move")
                            heroMiniPill(title: "Hide")
                            heroMiniPill(title: "Rename")
                        }

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.24))
                            .overlay(
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text("Progress")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text("62%")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(page.palette.primary)
                                    }

                                    GeometryReader { geometry in
                                        let width = max(0, geometry.size.width)
                                        ZStack(alignment: .leading) {
                                            Capsule(style: .continuous)
                                                .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.54))
                                            Capsule(style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [page.palette.primary, page.palette.secondary],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: width * 0.62)
                                        }
                                    }
                                    .frame(height: 9)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            )

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28))
                            .overlay(
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(page.palette.primary.opacity(0.22))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: "icloud.fill")
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(page.palette.primary)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text("iCloud")
                                                .font(.subheadline.weight(.semibold))
                                            Circle()
                                                .fill(page.palette.secondary)
                                                .frame(width: 7, height: 7)
                                            Text("Connected")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(page.palette.secondary)
                                        }
                                        Text("Imported drawings and progress sync and auto-restore on your iPad.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(10)
                            )
                    }
                    .padding(12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.24 : 0.40), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
        }
    }

    private var galleryHero: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                heroChip(title: "Send to Gallery", icon: "square.and.arrow.up")
                Spacer(minLength: 0)
                heroChip(title: "Share", icon: "square.and.arrow.up.on.square")
            }

            ZStack {
                galleryArtworkCard(
                    imageName: "OnboardingGalleryPet",
                    size: CGSize(width: 236, height: 148),
                    rotation: -6.5
                )
                .offset(x: -124, y: -34)

                galleryArtworkCard(
                    imageName: "OnboardingGalleryForest",
                    size: CGSize(width: 236, height: 148),
                    rotation: 5.8
                )
                .offset(x: 124, y: -34)

                galleryArtworkCard(
                    imageName: "OnboardingGalleryVenice",
                    size: CGSize(width: 360, height: 218),
                    rotation: 0.0
                )
                .offset(y: 20)
            }
            .frame(height: 272)

            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(heroPaletteColor(index).opacity(0.9))
                        .frame(width: index == 1 ? 64 : 38, height: 10)
                }
                Spacer(minLength: 0)
                heroChip(title: "Delete", icon: "trash")
            }
        }
    }

    private func heroLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
    }

    private func heroMiniPill(title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.primary)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
    }

    private func heroChip(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(.primary)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
    }

    private func toolOrb(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(tint, in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
            )
    }

    private func categoryRow(title: String, icon: String, tint: Color, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint, in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.35), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func studioLibraryRow(
        title: String,
        subtitle: String,
        tint: Color,
        accent: Color,
        isSelected: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.98), accent.opacity(0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? tint.opacity(0.90) : .secondary)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.84) : Color.white.opacity(0.26), lineWidth: isSelected ? 1.6 : 1)
        )
    }

    private func galleryArtworkCard(
        imageName: String,
        size: CGSize,
        rotation: Double
    ) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.44 : 0.56), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16), radius: 10, x: 0, y: 6)
            .rotationEffect(.degrees(rotation))
    }

    private func halfColoredArtworkPreview(imageName: String, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.90))
            .overlay {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = geometry.size.height

                    ZStack {
                        Image(imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)

                        Image(imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .saturation(0)
                            .contrast(1.38)
                            .brightness(0.20)
                            .opacity(0.96)
                            .mask(
                                Rectangle()
                                    .frame(width: width * 0.48, height: height)
                                    .offset(x: width * 0.26)
                            )

                        Rectangle()
                            .fill(Color.white.opacity(0.30))
                            .frame(width: width * 0.024, height: height)
                            .position(x: width * 0.52, y: height * 0.50)

                        Path { path in
                            path.move(to: CGPoint(x: width * 0.52, y: 0))
                            path.addLine(to: CGPoint(x: width * 0.52, y: height))
                        }
                        .stroke(Color.black.opacity(0.22), lineWidth: max(1.0, width * 0.008))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
            )
    }

    private func heroPaletteColor(_ index: Int) -> Color {
        let palette = [
            page.palette.primary,
            page.palette.secondary,
            page.palette.tertiary,
            page.palette.quaternary
        ]
        return palette[index % palette.count]
    }
}

private struct OnboardingBadgeView: View {
    let badge: OnboardingBadge
    let palette: OnboardingPalette
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: badge.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 21, height: 21)
                .background(
                    LinearGradient(
                        colors: [palette.primary, palette.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )

            Text(badge.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.90) : Color.primary.opacity(0.82))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.24 : 0.42), lineWidth: 1)
        )
    }
}

private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: spacing) {
                    content
                }
                VStack(alignment: .leading, spacing: lineSpacing) {
                    content
                }
            }
        } else {
            VStack(alignment: .leading, spacing: lineSpacing) {
                content
            }
        }
    }
}

private struct OnboardingPage {
    let title: String
    let subtitle: String
    let badges: [OnboardingBadge]
    let palette: OnboardingPalette
    let hero: OnboardingHeroKind
}

private struct OnboardingBadge {
    let icon: String
    let title: String
}

private struct OnboardingPalette {
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let quaternary: Color
}

private enum OnboardingHeroKind {
    case studio
    case importColor
    case organize
    case gallery
}

#Preview {
    FirstRunOnboardingView(onComplete: {})
}
