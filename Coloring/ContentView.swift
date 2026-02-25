import SwiftUI

struct ContentView: View {
    private enum RootTab {
        case studio
        case gallery
    }

    @StateObject private var templateViewModel = TemplateStudioViewModel()
    @StateObject private var galleryViewModel = GalleryViewModel()
    @State private var selectedTab: RootTab = .gallery

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
            colors: [
                Color("InkBlack"),
                Color.black.opacity(0.95),
                Color(red: 0.07, green: 0.07, blue: 0.09)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Circle()
                .fill(Color("SprayRed").opacity(0.23))
                .frame(width: 430, height: 430)
                .blur(radius: 44)
                .offset(x: 330, y: -250)
        }
        .overlay {
            Circle()
                .fill(Color("SprayOrange").opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 54)
                .offset(x: 80, y: -280)
        }
        .overlay {
            Circle()
                .fill(Color("SprayYellow").opacity(0.15))
                .frame(width: 380, height: 380)
                .blur(radius: 58)
                .offset(x: -210, y: -250)
        }
        .overlay {
            Circle()
                .fill(Color("SprayGreen").opacity(0.16))
                .frame(width: 560, height: 560)
                .blur(radius: 60)
                .offset(x: -330, y: 260)
        }
        .overlay {
            Circle()
                .fill(Color("SprayBlue").opacity(0.16))
                .frame(width: 510, height: 510)
                .blur(radius: 60)
                .offset(x: 40, y: 300)
        }
        .overlay {
            Circle()
                .fill(Color("SprayViolet").opacity(0.18))
                .frame(width: 500, height: 500)
                .blur(radius: 62)
                .offset(x: 350, y: 210)
        }
    }
}

#Preview {
    ContentView()
}
