import SwiftUI

/// 앱 탭 식별자. AppStorage 키 "selected_tab"에 raw value로 저장한다.
enum AppTab: String {
    case create = "create"
    case myCourse = "myCourse"
}

struct ContentView: View {
    @State private var savedSession: TravelSession?
    @State private var showRestoreSheet = false
    @State private var resumeCourse: Course?
    @State private var resumeTransport = "car"
    @State private var navigateToExplore = false

    @AppStorage("selected_tab") private var selectedTabRaw: String = AppTab.create.rawValue

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .create },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            TabView(selection: selectedTabBinding) {
                TasteDiscoveryView()
                    .tabItem { Label("코스 만들기", systemImage: "sparkles") }
                    .tag(AppTab.create)
                MyCourseListView()
                    .tabItem { Label("내 코스", systemImage: "bookmark.fill") }
                    .tag(AppTab.myCourse)
            }
            .tint(.orange)
            .navigationDestination(isPresented: $navigateToExplore) {
                if let course = resumeCourse {
                    ExploreView(course: course, transport: resumeTransport, categoryScores: [:])
                }
            }
        }
        .sheet(isPresented: $showRestoreSheet) {
            if let session = savedSession {
                SessionRestoreView(
                    session: session,
                    onResume: { course, transport in
                        showRestoreSheet = false
                        resumeCourse = course
                        resumeTransport = transport
                        navigateToExplore = true
                    },
                    onDiscard: {
                        TravelStore.shared.clear()
                        savedSession = nil
                        showRestoreSheet = false
                    }
                )
            }
        }
        .onAppear {
            if let session = TravelStore.shared.load() {
                savedSession = session
                showRestoreSheet = true
            }
        }
        // SessionRestore 경로(ContentView가 직접 ExploreView를 push)로 진입한 경우
        // 탐험 완료 시 navigation stack을 비워 TabView root로 복귀.
        .onReceive(NotificationCenter.default.publisher(for: .exploreDidComplete)) { _ in
            navigateToExplore = false
        }
    }
}
