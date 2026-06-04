import SwiftUI
import SwiftData

/// 앱 탭 식별자. AppStorage 키 "selected_tab"에 raw value로 저장한다.
enum AppTab: String {
    case home = "home"
    case create = "create"
    case myCourse = "myCourse"
}

struct ContentView: View {
    @State private var savedSession: TravelSession?
    @State private var showRestoreSheet = false
    @State private var resumeCourse: Course?
    @State private var resumeTransport = "car"
    @State private var navigateToExplore = false

    @AppStorage("selected_tab") private var selectedTabRaw: String = AppTab.home.rawValue
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .home },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTabBinding) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("홈", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                TasteDiscoveryView()
            }
            .tabItem { Label("코스 만들기", systemImage: "sparkles") }
            .tag(AppTab.create)

            NavigationStack {
                MyCourseListView()
            }
            .tabItem { Label("내 코스", systemImage: "bookmark.fill") }
            .tag(AppTab.myCourse)
        }
        .tint(.orange)
        // SessionRestore 경로: 이전에는 NavigationStack push였지만, 탭별 NavigationStack 분리 이후
        // 어떤 탭에 push할지 모호해서 fullScreenCover로 띄운다. ExploreView 내부 navigationDestination을
        // 위해 자체 NavigationStack 감싸기.
        .fullScreenCover(isPresented: $navigateToExplore) {
            if let course = resumeCourse {
                NavigationStack {
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
            selectedTabRaw = AppTab.myCourse.rawValue
        }
        // Firestore 동기화 트리거: 로그인 ↔ 로그아웃에 따라 listener 시작/종료
        .onChange(of: authManager.currentUser?.uid, initial: true) { _, newUid in
            if let uid = newUid {
                FirestoreSyncService.shared.startListening(uid: uid, modelContext: modelContext)
            } else {
                FirestoreSyncService.shared.stopListening()
            }
        }
    }
}
