import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("지도", systemImage: "map.fill") }
            CourseRecommendView()
                .tabItem { Label("코스 추천", systemImage: "sparkles") }
            MyCourseListView()
                .tabItem { Label("내 코스", systemImage: "bookmark.fill") }
            ChatView()
                .tabItem { Label("챗봇", systemImage: "bubble.left.and.bubble.right.fill") }
        }
        .tint(.orange)
    }
}
