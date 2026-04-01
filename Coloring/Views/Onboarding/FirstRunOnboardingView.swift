import SwiftUI

struct FirstRunOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentPage = 0
    let onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to Studio",
            subtitle: "Browse built-in and imported drawings, then open one and start coloring.",
            detailBadges: [
                .init(icon: "paintpalette.fill", title: "Studio Workspace", tint: Color(red: 0.25, green: 0.64, blue: 0.98)),
                .init(icon: "rectangle.stack.fill", title: "Built-In + Imported", tint: Color(red: 0.18, green: 0.76, blue: 0.58))
            ],
            visual: .studio
        ),
        OnboardingPage(
            title: "Import and Color",
            subtitle: "Add outlines from Photos or Files. Draw, fill, undo, redo, and clear strokes or fills any time.",
            detailBadges: [
                .init(icon: "photo.on.rectangle.angled", title: "Photos + Files", tint: Color(red: 0.23, green: 0.68, blue: 0.95)),
                .init(icon: "pencil.and.scribble", title: "Apple Pencil + PencilKit", tint: Color(red: 0.12, green: 0.75, blue: 0.62)),
                .init(icon: "drop.fill", title: "Fill, Undo, Redo, Clear", tint: Color(red: 0.96, green: 0.58, blue: 0.22))
            ],
            visual: .coloring
        ),
        OnboardingPage(
            title: "Organize and Sync",
            subtitle: "Use categories and hidden management, plus quick drawing actions from long-press menus. Imported drawings and progress sync with iCloud when available.",
            detailBadges: [
                .init(icon: "folder.badge.gearshape", title: "Folders + Categories", tint: Color(red: 0.95, green: 0.53, blue: 0.21)),
                .init(icon: "eye.slash", title: "Hidden Management", tint: Color(red: 0.64, green: 0.57, blue: 0.94)),
                .init(icon: "icloud", title: "iCloud Restore", tint: Color(red: 0.30, green: 0.62, blue: 0.95))
            ],
            visual: .organize
        ),
        OnboardingPage(
            title: "Gallery and Share",
            subtitle: "Send finished artwork to Gallery, open details, share exports, and manage saved pieces.",
            detailBadges: [
                .init(icon: "square.and.arrow.up", title: "Send to Gallery", tint: Color(red: 0.17, green: 0.73, blue: 0.57)),
                .init(icon: "photo.stack", title: "Browse Finished Artwork", tint: Color(red: 0.29, green: 0.66, blue: 0.96)),
                .init(icon: "trash", title: "Share and Delete", tint: Color(red: 0.93, green: 0.36, blue: 0.38))
            ],
            visual: .gallery
        )
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                onboardingBackground

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 26)
                        .padding(.top, 18)

                    TabView(selection: $currentPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingPageView(
                                page: page,
                                colorScheme: colorScheme,
                                reduceMotion: reduceMotion,
                                isCurrentPage: index == currentPage
                            )
                            .frame(maxWidth: min(geometry.size.width * 0.92, 860))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: currentPage)

                    footer
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 18)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var topBar: some View {
        HStack {
            Text("Coloring")
                .font(.headline.weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : Color.primary.opacity(0.82))

            Spacer()

            Button("Skip") {
                completeOnboarding()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : Color.primary.opacity(0.78))
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
            pageDots

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
                            Color(red: 0.14, green: 0.64, blue: 0.97),
                            Color(red: 0.18, green: 0.80, blue: 0.65),
                            Color(red: 0.96, green: 0.57, blue: 0.18)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentPage
                        ? Color.white.opacity(colorScheme == .dark ? 0.93 : 0.98)
                        : Color.white.opacity(colorScheme == .dark ? 0.36 : 0.56))
                    .frame(width: index == currentPage ? 30 : 9, height: 9)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentPage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.25 : 0.38), lineWidth: 1)
        )
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
                        Color(red: 0.94, green: 0.97, blue: 1.00),
                        Color(red: 0.93, green: 0.97, blue: 0.98),
                        Color(red: 0.97, green: 0.95, blue: 0.99)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.98, green: 0.39, blue: 0.37).opacity(colorScheme == .dark ? 0.22 : 0.12))
                .frame(width: 460, height: 460)
                .blur(radius: 56)
                .offset(x: 320, y: -280)

            Circle()
                .fill(Color(red: 0.99, green: 0.72, blue: 0.31).opacity(colorScheme == .dark ? 0.20 : 0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 56)
                .offset(x: -250, y: -260)

            Circle()
                .fill(Color(red: 0.15, green: 0.80, blue: 0.63).opacity(colorScheme == .dark ? 0.20 : 0.12))
                .frame(width: 560, height: 560)
                .blur(radius: 60)
                .offset(x: -280, y: 320)

            Circle()
                .fill(Color(red: 0.30, green: 0.62, blue: 0.95).opacity(colorScheme == .dark ? 0.20 : 0.11))
                .frame(width: 520, height: 520)
                .blur(radius: 60)
                .offset(x: 280, y: 300)
        }
        .ignoresSafeArea()
    }

    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    private func continueOrComplete() {
        guard !isLastPage else {
            completeOnboarding()
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

    private func completeOnboarding() {
        onComplete()
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let isCurrentPage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingVisualCard(visual: page.visual, colorScheme: colorScheme)
                .frame(maxWidth: .infinity)
                .frame(height: 330)
                .scaleEffect(!reduceMotion && isCurrentPage ? 1 : 0.985)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isCurrentPage)

            VStack(alignment: .leading, spacing: 8) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.96) : Color.primary)
                    .minimumScaleFactor(0.85)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.80) : Color.primary.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            }

            WrapHStack(spacing: 8, lineSpacing: 8) {
                ForEach(page.detailBadges, id: \.title) { badge in
                    OnboardingBadgeView(badge: badge, colorScheme: colorScheme)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.25 : 0.48), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10), radius: 16, x: 0, y: 10)
        )
    }
}

private struct OnboardingVisualCard: View {
    let visual: OnboardingVisual
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.13 : 0.42),
                            Color.white.opacity(colorScheme == .dark ? 0.07 : 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.44), lineWidth: 1)
                )

            switch visual {
            case .studio:
                studioPanel
            case .coloring:
                coloringPanel
            case .organize:
                organizePanel
            case .gallery:
                galleryPanel
            }
        }
    }

    private var studioPanel: some View {
        HStack(spacing: 16) {
            VStack(spacing: 10) {
                visualTile(icon: "paintbrush.pointed.fill", text: "Studio")
                visualTile(icon: "square.grid.2x2.fill", text: "Browse")
            }

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.white.opacity(0.58))
                            .frame(height: 12)
                            .padding(.trailing, 80)

                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.36))
                                .frame(height: 42)
                        }
                    }
                    .padding(16)
                )
        }
        .padding(22)
    }

    private var coloringPanel: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            visualPill(icon: "photo")
                            visualPill(icon: "folder")
                        }

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 92)
                            .overlay(
                                Image(systemName: "pencil.tip.crop.circle.badge.plus")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            )
                    }
                    .padding(16)
                )

            VStack(spacing: 10) {
                visualTile(icon: "drop.fill", text: "Fill")
                visualTile(icon: "arrow.uturn.backward", text: "Undo")
                visualTile(icon: "arrow.uturn.forward", text: "Redo")
            }
        }
        .padding(22)
    }

    private var organizePanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                visualPill(icon: "folder.badge.gearshape")
                visualPill(icon: "eye.slash")
                visualPill(icon: "star.fill")
                visualPill(icon: "checkmark.seal.fill")
            }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: 78)
                .overlay(
                    HStack(spacing: 12) {
                        Image(systemName: "icloud")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(red: 0.30, green: 0.62, blue: 0.95))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud when available")
                                .font(.subheadline.weight(.semibold))
                            Text("Imported drawings and progress can restore on this device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(14)
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(height: 68)
                .overlay(
                    HStack(spacing: 10) {
                        Image(systemName: "ellipsis.bubble")
                            .font(.title3.weight(.semibold))
                        Text("Long-press drawings for quick actions")
                            .font(.subheadline.weight(.medium))
                    }
                )
        }
        .padding(22)
    }

    private var galleryPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                visualPill(icon: "square.and.arrow.up")
                visualPill(icon: "photo.stack")
                visualPill(icon: "square.and.arrow.up.on.square")
                visualPill(icon: "trash")
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: 140)
                .overlay(
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { idx in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.20 + Double(idx) * 0.08))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(14)
                )
        }
        .padding(22)
    }

    private func visualTile(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func visualPill(icon: String) -> some View {
        Image(systemName: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 38, height: 38)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct OnboardingBadgeView: View {
    let badge: OnboardingBadge
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: badge.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(badge.tint, in: Circle())

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
    let detailBadges: [OnboardingBadge]
    let visual: OnboardingVisual
}

private struct OnboardingBadge {
    let icon: String
    let title: String
    let tint: Color
}

private enum OnboardingVisual {
    case studio
    case coloring
    case organize
    case gallery
}

#Preview {
    FirstRunOnboardingView(onComplete: {})
}
