import SwiftUI

/// 앱 탭 식별자. AppStorage 키 "selected_tab"에 raw value로 저장한다.
enum AppTab: String {
    case create = "create"
    case myCourse = "myCourse"
#if DEBUG
    case debug = "debug"
#endif
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
#if DEBUG
                DebugExploreView()
                    .tabItem { Label("테스트", systemImage: "ladybug.fill") }
                    .tag(AppTab.debug)
#endif
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
    }
}

#if DEBUG
private let debugCourse = Course(
    id: "debug-course",
    title: "테스트 코스 (성산 → 섭지 → 협재)",
    durationDays: 1,
    places: [
        CoursePlace(name: "성산일출봉", lat: 33.4580, lng: 126.9425, day: 1),
        CoursePlace(name: "섭지코지",   lat: 33.4270, lng: 126.9307, day: 1),
        CoursePlace(name: "협재해수욕장", lat: 33.3942, lng: 126.2390, day: 1),
    ],
    estimatedMinutes: 180
)

struct DebugExploreView: View {
    @State private var started = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("고정 테스트 코스")
                        .font(.headline)
                    ForEach(debugCourse.places) { place in
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundColor(.orange)
                            Text(place.name)
                            Spacer()
                            Text("(\(String(format: "%.4f", place.lat)), \(String(format: "%.4f", place.lng)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("시뮬레이터 테스트 방법")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("Features > Location > Custom Location\n위 좌표를 순서대로 입력하세요.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                NavigationLink("탐험 시작") {
                    ExploreView(course: debugCourse, transport: "car", categoryScores: [:])
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .navigationTitle("🐞 디버그")
        }
    }
}
#endif
