import Foundation

enum LoadingStep: String {
    case idle = ""
    case searching = "코스 검색 중..."
    case generating = "코스 준비 중..."
}

@MainActor
final class CourseRecommendViewModel: ObservableObject {
    @Published var selectedRegion: String = ""
    @Published var categoryScores: [String: Int] = [:]
    @Published var durationDays: Int = 1

    @Published var courseList: [CourseListItem] = []
    @Published var currentCourseIndex: Int = 0
    @Published var isLoadingList: Bool = false

    var hasNextCourse: Bool { currentCourseIndex + 1 < courseList.count }

    @Published var selectedCourse: Course?
    @Published var isLoadingDetail: Bool = false

    @Published var loadingStep: LoadingStep = .idle
    @Published var errorMessage: String?

    var isLoading: Bool { isLoadingList || isLoadingDetail }

    func fetchList() async {
        guard !selectedRegion.isEmpty, !categoryScores.isEmpty else { return }
        errorMessage = nil
        courseList = []
        isLoadingList = true
        loadingStep = .searching

        do {
            let items = try await CourseAPI.list(
                region: selectedRegion,
                categoryScores: categoryScores,
                durationDays: durationDays
            )
            courseList = items
            currentCourseIndex = 0
            isLoadingList = false
            loadingStep = .idle
            // 자동으로 첫 코스 detail을 호출하지 않음.
            // 사용자가 Top 3 리스트에서 직접 선택하도록 변경.
        } catch {
            errorMessage = error.localizedDescription
            loadingStep = .idle
            isLoadingList = false
        }
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
            let course = try await CourseAPI.detail(courseId: courseId, categoryScores: categoryScores)
            selectedCourse = course
            loadingStep = .idle
        } catch {
            errorMessage = error.localizedDescription
            loadingStep = .idle
        }
        isLoadingDetail = false
    }

    func advanceToNextCourse() async {
        guard hasNextCourse else { return }
        currentCourseIndex += 1
        await fetchDetail(courseId: courseList[currentCourseIndex].id)
    }

    func reset() {
        selectedRegion = ""
        categoryScores = [:]
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
