import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TasteDiscoveryView()
                .tabItem { Label("코스 만들기", systemImage: "sparkles") }
            MyCourseListView()
                .tabItem { Label("내 코스", systemImage: "bookmark.fill") }
            ChatView()
                .tabItem { Label("챗봇", systemImage: "bubble.left.and.bubble.right.fill") }
        }
        .tint(.orange)
    }
}
