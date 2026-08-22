import SwiftUI
import SwiftData

/// 앱 탭 식별자. AppStorage 키 "selected_tab"에 raw value로 저장한다.
///
/// `docs/공고.md` §2의 탭 구성. **지도 탭은 다음 묶음에서 들어온다** — 빈 탭을 미리
/// 띄우면 눌렀을 때 아무것도 없어 고장난 앱으로 보인다.
///
/// 예전에 쓰던 값("explore"·"create"·"myCourse")이 기기에 저장돼 있으면
/// `AppTab(rawValue:)`가 nil이 되어 홈으로 떨어진다 — 앱이 깨지지는 않는다.
enum AppTab: String {
    case home = "home"
    case course = "course"
    case profile = "profile"
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

    /// 탭 하나를 그린다. 안 보이는 탭도 계층에 남겨 상태를 보존한다.
    @ViewBuilder
    private func tabContent<C: View>(_ tab: AppTab, @ViewBuilder _ content: () -> C) -> some View {
        let on = (AppTab(rawValue: selectedTabRaw) ?? .home) == tab
        NavigationStack { content() }
            .opacity(on ? 1 : 0)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
    }

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
        // ⚠️ SwiftUI TabView를 쓰지 않는다. 시안의 탭바(4px 테두리·위쪽 그림자·
        // 선택 탭 채움)를 TabView로는 만들 수 없다 → PixelTabBar.
        //
        // 대신 탭별 NavigationStack을 전부 살려두고 보이는 것만 바꾼다.
        // 지우고 다시 만들면 각 탭의 스크롤·화면 이동 상태가 날아간다.
        VStack(spacing: 0) {
            ZStack {
                tabContent(.home)    { HomeView() }
                tabContent(.course)  { CourseHubView() }
                tabContent(.profile) { ProfileTabView().environmentObject(authManager) }
            }
            PixelTabBar(items: [
                .init(tab: .home,    title: "홈",     icon: .home),
                // 코스 = 여러 곳을 이은 길이라 경로선 그림을 쓴다.
                .init(tab: .course,  title: "코스",   icon: .map),
                .init(tab: .profile, title: "프로필", icon: .person),
            ], selection: selectedTabBinding)
        }
        .background(PixelColor.background.ignoresSafeArea())
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
