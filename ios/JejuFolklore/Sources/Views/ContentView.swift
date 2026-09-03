import SwiftUI
import SwiftData

/// 앱 탭 식별자. AppStorage 키 "selected_tab"에 raw value로 저장한다.
///
/// `docs/공고.md` §2의 탭 구성 4개.
///
/// 예전에 쓰던 값("explore"·"create"·"myCourse")이 기기에 저장돼 있으면
/// `AppTab(rawValue:)`가 nil이 되어 홈으로 떨어진다 — 앱이 깨지지는 않는다.
enum AppTab: String {
    case home = "home"
    case course = "course"
    case map = "map"
    case profile = "profile"
}

/// 밀려 올라온 화면이 탭바를 숨길 수 있게 하는 신호.
///
/// **왜 화면이 직접 못 끄는가.** 탭바는 `ContentView` 의 VStack 에 붙어 있고
/// 각 탭 화면은 그 안쪽 `NavigationStack` 에 있다. SwiftUI Preference 는
/// `navigationDestination` 경계를 타고 올라오지 않아서 공용 객체로 신호를 보낸다.
///
/// **켜고 끄는 게 아니라 센다.** PLAY 상세에서 장소 상세로 밀어 올리면 두 화면의
/// `onAppear`·`onDisappear` 순서가 엇갈리는데, 「숨기길 원하는 화면이 몇 개인가」를
/// 세면 순서와 무관하게 결과가 맞는다.
@MainActor
final class TabBarVisibility: ObservableObject {
    @Published private(set) var isHidden = false
    private var requests = 0

    func hide() {
        requests += 1
        isHidden = requests > 0
    }

    func show() {
        requests = max(0, requests - 1)
        isHidden = requests > 0
    }
}

/// ⚠️ `EnvironmentObject` 가 아니라 `Environment` 다. 없으면 크래시하는 대신
/// nil 이 된다 — 개발용 `PixelGalleryView` 나 프리뷰처럼 앱 뼈대 없이 화면 하나만
/// 띄우는 경로가 있다.
private struct TabBarVisibilityKey: EnvironmentKey {
    static let defaultValue: TabBarVisibility? = nil
}

extension EnvironmentValues {
    var tabBarVisibility: TabBarVisibility? {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

struct ContentView: View {
    @State private var savedSession: TravelSession?
    @State private var showRestoreSheet = false
    @State private var resumeCourse: Course?
    @State private var resumeTransport = "car"
    @State private var navigateToExplore = false
    @StateObject private var tabBarVisibility = TabBarVisibility()

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
                tabContent(.map)     { MapTabView() }
                tabContent(.profile) { ProfileTabView().environmentObject(authManager) }
            }
            // PLAY 상세처럼 「지금 이것만 정하는」 화면은 탭바를 숨긴다.
            if !tabBarVisibility.isHidden {
                PixelTabBar(items: [
                    .init(tab: .home,    title: "퀘스트", icon: .quest),
                    // 시안 그대로다 — 코스는 나침반(explore), 지도는 접힌 지도(map).
                    // 예전에 코스=지도·지도=핀으로 바꿔 뒀던 것은 내 판단이었다(2026-09-03 정정).
                    .init(tab: .course,  title: "코스",   icon: .compass),
                    .init(tab: .map,     title: "지도",   icon: .map),
                    .init(tab: .profile, title: "프로필", icon: .person),
                ], selection: selectedTabBinding)
            }
        }
        .environment(\.tabBarVisibility, tabBarVisibility)
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
