import SwiftUI
import UIKit
import WidgetKit

struct ColoringRoomWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ColoringWidgetSnapshot
}

struct ColoringRoomWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ColoringRoomWidgetEntry {
        ColoringRoomWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ColoringRoomWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ColoringRoomWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: entry.date)
            ?? entry.date.addingTimeInterval(3_600)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadEntry() -> ColoringRoomWidgetEntry {
        ColoringRoomWidgetEntry(
            date: Date(),
            snapshot: ColoringWidgetSnapshotStore.load(
                from: ColoringWidgetSnapshotStore.sharedFileURL()
            )
        )
    }
}

struct ColoringRoomWidgetView: View {
    let entry: ColoringRoomWidgetEntry

    var body: some View {
        GeometryReader { proxy in
            let availableCardWidth = max(proxy.size.width - 10, 0)

            HStack(spacing: 10) {
                currentArtworkCard
                    .frame(width: availableCardWidth * 0.56)

                galleryArtworkCard
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            watercolorBackground
        }
    }

    @ViewBuilder
    private var currentArtworkCard: some View {
        if let artwork = entry.snapshot.currentArtwork,
           let destinationURL = artwork.destinationURL
        {
            Link(destination: destinationURL) {
                artworkCard(
                    imageData: artwork.imageData,
                    caption: artwork.title,
                    emptySymbol: "paintbrush.pointed.fill"
                )
            }
            .accessibilityLabel("Continue coloring \(artwork.title)")
        } else {
            Link(destination: URL(string: "coloringroom://studio")!) {
                artworkCard(
                    imageData: Data(),
                    caption: "Start something colorful",
                    emptySymbol: "paintbrush.pointed.fill"
                )
            }
            .accessibilityLabel("Open Studio to start coloring")
        }
    }

    @ViewBuilder
    private var galleryArtworkCard: some View {
        if let artwork = entry.snapshot.latestGalleryArtwork,
           let destinationURL = artwork.destinationURL
        {
            Link(destination: destinationURL) {
                artworkCard(
                    imageData: artwork.imageData,
                    caption: "GALLERY · \(galleryDateDetail(artwork.createdAt).uppercased())",
                    emptySymbol: "photo.on.rectangle.angled"
                )
            }
            .accessibilityLabel("Open latest gallery artwork, \(artwork.title)")
        } else {
            Link(destination: URL(string: "coloringroom://gallery")!) {
                artworkCard(
                    imageData: Data(),
                    caption: "GALLERY · OPEN GALLERY",
                    emptySymbol: "photo.on.rectangle.angled"
                )
            }
            .accessibilityLabel("Open Gallery")
        }
    }

    private func artworkCard(
        imageData: Data,
        caption: String,
        emptySymbol: String
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 1.0, green: 0.98, blue: 0.92).opacity(0.88))

            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 38)
                    .padding(.horizontal, 5)
                    .padding(.top, 5)
            } else {
                Image(systemName: emptySymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.43, blue: 0.68))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 38)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.78), Color.black.opacity(0.50), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 50)

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 5, y: 3)
    }

    private func galleryDateDetail(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }

        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var watercolorBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.97, blue: 0.87),
                    Color(red: 1.00, green: 0.90, blue: 0.82),
                    Color(red: 0.85, green: 0.94, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.98, green: 0.45, blue: 0.37).opacity(0.26))
                .frame(width: 190, height: 190)
                .blur(radius: 30)
                .offset(x: -145, y: -60)

            Circle()
                .fill(Color(red: 0.33, green: 0.69, blue: 0.88).opacity(0.24))
                .frame(width: 180, height: 180)
                .blur(radius: 32)
                .offset(x: 150, y: 70)

            Circle()
                .fill(Color(red: 0.58, green: 0.41, blue: 0.79).opacity(0.18))
                .frame(width: 130, height: 130)
                .blur(radius: 28)
                .offset(x: 40, y: 95)
        }
    }
}

@main
struct ColoringRoomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ColoringWidgetSnapshotStore.widgetKind,
            provider: ColoringRoomWidgetProvider()
        ) { entry in
            ColoringRoomWidgetView(entry: entry)
        }
        .configurationDisplayName("Coloring Room")
        .description("Continue your latest coloring and revisit your newest gallery artwork.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    ColoringRoomWidget()
} timeline: {
    ColoringRoomWidgetEntry(date: .now, snapshot: .empty)
}
