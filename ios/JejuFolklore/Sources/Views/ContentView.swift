import SwiftUI
import SwiftData

/// 앱 탭 식별자. AppStorage 키 "selected_tab"에 raw value로 저장한다.
///
/// 설계 §1의 탭 4개. 구 값("create"·"myCourse")이 저장돼 있으면
/// `AppTab(rawValue:)`가 nil이 되어 홈으로 떨어진다 — 앱이 깨지지는 않는다.
enum AppTab: String {
    case home = "home"
    case story = "story"
    case course = "course"
    case mine = "mine"
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
        // 개발용 — 실행 인자 `-showPixelGallery YES`로 부품 화면만 띄운다.
        if UserDefaults.standard.bool(forKey: "showPixelGallery") {
            NavigationStack { PixelGalleryView() }
        } else {
            mainTabs
        }
    }

    private var mainTabs: some View {
        TabView(selection: selectedTabBinding) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label { Text("홈") } icon: { Image(uiImage: PixelIcon.uiImage(.home)) }
            }
            .tag(AppTab.home)

            NavigationStack {
                StoryListView()
            }
            .tabItem {
                Label { Text("스토리") } icon: { Image(uiImage: PixelIcon.uiImage(.photo)) }
            }
            .tag(AppTab.story)

            NavigationStack {
                CourseHubView()
            }
            .tabItem {
                Label { Text("코스") } icon: { Image(uiImage: PixelIcon.uiImage(.map)) }
            }
            .tag(AppTab.course)

            NavigationStack {
                MineView()
                    .environmentObject(authManager)
            }
            .tabItem {
                Label { Text("내 것") } icon: { Image(uiImage: PixelIcon.uiImage(.person)) }
            }
            .tag(AppTab.mine)
        }
        .tint(PixelColor.primary)
        // SessionRestore 경로: 이전에는 NavigationStack push였지만, 탭별 NavigationStack 분리 이후
        // 어떤 탭에 push할지 모호해서 fullScreenCover로 띄운다. ExploreView 내부 navigationDestination을
        // 위해 자체 NavigationStack 감싸기.
        .fullScreenCover(isPresented: $navigateToExplore) {
            if let course = resumeCourse {
                NavigationStack {
                    ExploreView(course: course, transport: resumeTransport)
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
            selectedTabRaw = AppTab.course.rawValue
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
