import Foundation

enum LoadingStep: String {
    case idle = ""
    /// 권역·기간으로 코스를 찾는 동안. 목록 화면의 로딩 화면이 이 글을 쓴다.
    case searching = "최적의 코스 찾는 중 .."
    case generating = "코스 준비 중..."
}

@MainActor
final class CourseRecommendViewModel: ObservableObject {
    @Published var selectedRegion: String = ""
    @Published var durationDays: Int = 1

    @Published var courseList: [CourseListItem] = []
    @Published var currentCourseIndex: Int = 0
    @Published var isLoadingList: Bool = false


    @Published var selectedCourse: Course?
    @Published var isLoadingDetail: Bool = false

    /// 코스 탭 첫 화면의 「이런 코스는 어때요?」. 권역·기간과 무관하게 서버가
    /// 무작위로 주는 목록이라 `courseList`(추천 결과)와 섞지 않는다.
    @Published var featured: [CourseListItem] = []
    @Published var isLoadingFeatured = false

    @Published var loadingStep: LoadingStep = .idle
    @Published var errorMessage: String?

    var isLoading: Bool { isLoadingList || isLoadingDetail }

    // MARK: - 코스 찾기의 시간 규칙 (2026-09-10 조익준님 결정)
    //
    // 전에는 목록이 오는 즉시 넘어갔다. 서버가 빠르면 「코스 찾기」를 누르자마자
    // 화면이 바뀌어서 찾아본 느낌이 없고, 정작 카드 사진은 넘어간 **뒤에** 채워져서
    // 다 온 화면이 한 번 더 움직였다.
    //
    //     0 ─────────── 3초 ─────── 5초
    //     │             │            │
    //     │  로딩 화면은 무조건 여기까지 
    //     │             │  사진이 아직이면 여기까지만 더 기다린다
    //     └ 목록 받기 + 사진 미리 받기
    //
    /// 로딩 화면을 **최소 이만큼**은 보여준다. 사진이 일찍 와도 기다린다.
    private static let minimumLoading: TimeInterval = 3
    /// 사진을 기다려 주는 **한계**. 넘으면 사진 없이 그냥 넘어간다.
    private static let coverDeadline: TimeInterval = 5

    func fetchList() async {
        guard !selectedRegion.isEmpty else { return }
        errorMessage = nil
        courseList = []
        isLoadingList = true
        loadingStep = .searching
        let startedAt = Date()

        do {
            let items = try await CourseAPI.list(
                region: selectedRegion,
                durationDays: durationDays
            )
            courseList = items
            currentCourseIndex = 0

            // 카드 사진을 **먼저** 받아 둔다. 여기서 기다린 만큼 넘어간 화면이
            // 조용하다 — 카드가 사진까지 완성된 채로 나타난다.
            await CourseCoverStore.shared.warm(
                items.compactMap(\.thumbnail),
                until: startedAt.addingTimeInterval(Self.coverDeadline))

            await Self.holdLoading(since: startedAt)

            isLoadingList = false
            loadingStep = .idle
            // 자동으로 첫 코스 detail을 호출하지 않음.
            // 사용자가 Top 3 리스트에서 직접 선택하도록 변경.
        } catch {
            // 실패는 **기다리지 않고** 바로 알린다. 못 가져왔다는 말을 3초 늦게
            // 하는 것은 그냥 더 느린 실패다.
            errorMessage = error.localizedDescription
            loadingStep = .idle
            isLoadingList = false
        }
    }

    /// 최소 로딩 시간을 채운다. 이미 지났으면 곧바로 돌아온다.
    private static func holdLoading(since start: Date) async {
        let left = minimumLoading - Date().timeIntervalSince(start)
        guard left > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000))
    }

    /// 첫 화면 둘러보기 목록을 불러온다. 새로고침할 때마다 다른 코스가 온다.
    ///
    /// 실패해도 `errorMessage` 를 세우지 않는다 — 이 목록은 화면의 곁다리라,
    /// 안 떠도 권역·기간 고르기는 그대로 되는데 경고창이 뜨면 길을 막는 꼴이 된다.
    func loadFeatured() async {
        isLoadingFeatured = true
        defer { isLoadingFeatured = false }
        featured = (try? await CourseAPI.featured(limit: 5)) ?? featured
    }

    /// 사용자가 리스트에서 카드를 탭했을 때 호출.
    /// 선택한 인덱스를 currentCourseIndex로 표시하고 detail을 조회한다.
    func selectCourse(at index: Int) async {
        guard index >= 0, index < courseList.count else { return }
        currentCourseIndex = index
        await fetchDetail(courseId: courseList[index].id)
    }

    func fetchDetail(courseId: String) async {
        errorMessage = nil
        selectedCourse = nil
        isLoadingDetail = true
        loadingStep = .generating

        do {
            let course = try await CourseAPI.detail(courseId: courseId)
            selectedCourse = course
            loadingStep = .idle
        } catch {
            errorMessage = error.localizedDescription
            loadingStep = .idle
        }
        isLoadingDetail = false
    }

    func reset() {
        selectedRegion = ""
        durationDays = 1
        courseList = []
        currentCourseIndex = 0
        selectedCourse = nil
        errorMessage = nil
        loadingStep = .idle
        isLoadingList = false
        isLoadingDetail = false
    }

}
