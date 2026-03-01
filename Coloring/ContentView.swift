import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum RootTab {
        case studio
        case gallery
    }

    @StateObject private var templateViewModel = TemplateStudioViewModel()
    @StateObject private var galleryViewModel = GalleryViewModel()
    @State private var selectedTab: RootTab = .studio

    var body: some View {
        ZStack {
            backgroundGradient

            TabView(selection: $selectedTab) {
                TemplateStudioView(viewModel: templateViewModel)
                    .tabItem {
                        Label("Studio", systemImage: "paintbrush.pointed")
                    }
                    .tag(RootTab.studio)

                GalleryView(viewModel: galleryViewModel)
                    .tabItem {
                        Label("Gallery", systemImage: "photo.on.rectangle.angled")
                    }
                    .tag(RootTab.gallery)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color("InkBlack"),
                    Color.black.opacity(0.95),
                    Color(red: 0.07, green: 0.07, blue: 0.09)
                ]
                : [
                    Color(red: 0.95, green: 0.98, blue: 1.00),
                    Color(red: 0.96, green: 0.98, blue: 0.97),
                    Color(red: 0.99, green: 0.98, blue: 0.99)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Circle()
                .fill(Color("SprayRed").opacity(colorScheme == .dark ? 0.23 : 0.14))
                .frame(width: 430, height: 430)
                .blur(radius: 44)
                .offset(x: 330, y: -250)
        }
        .overlay {
            Circle()
                .fill(Color("SprayOrange").opacity(colorScheme == .dark ? 0.18 : 0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 54)
                .offset(x: 80, y: -280)
        }
        .overlay {
            Circle()
                .fill(Color("SprayYellow").opacity(colorScheme == .dark ? 0.15 : 0.08))
                .frame(width: 380, height: 380)
                .blur(radius: 58)
                .offset(x: -210, y: -250)
        }
        .overlay {
            Circle()
                .fill(Color("SprayGreen").opacity(colorScheme == .dark ? 0.16 : 0.09))
                .frame(width: 560, height: 560)
                .blur(radius: 60)
                .offset(x: -330, y: 260)
        }
        .overlay {
            Circle()
                .fill(Color("SprayBlue").opacity(colorScheme == .dark ? 0.16 : 0.09))
                .frame(width: 510, height: 510)
                .blur(radius: 60)
                .offset(x: 40, y: 300)
        }
        .overlay {
            Circle()
                .fill(Color("SprayViolet").opacity(colorScheme == .dark ? 0.18 : 0.10))
                .frame(width: 500, height: 500)
                .blur(radius: 62)
                .offset(x: 350, y: 210)
        }
    }
}

#Preview {
    ContentView()
}
