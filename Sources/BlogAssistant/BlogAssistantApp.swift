import SwiftUI

@main
struct BlogAssistantApp: App {
    @StateObject private var library = PhotoLibraryStore()

    var body: some Scene {
        WindowGroup("맛집 블로그 도우미") {
            ContentView(library: library)
                .task { NaverBridge.shared.start() }
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 760)
    }
}
