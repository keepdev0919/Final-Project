import Foundation

enum LoadingStep: String {
    case idle = ""
    case searching = "코스 검색 중..."
    case generating = "내러티브 생성 중..."
    case done = "완성!"
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
            if let first = items.first {
                await fetchDetail(courseId: first.id)
            }
        } catch {
            errorMessage = error.localizedDescription
            loadingStep = .idle
            isLoadingList = false
        }
    }

    func fetchDetail(courseId: String) async {
        errorMessage = nil
        selectedCourse = nil
        isLoadingDetail = true
        loadingStep = .generating

        do {
            let course = try await CourseAPI.detail(courseId: courseId, categoryScores: categoryScores)
            loadingStep = .done
            try? await Task.sleep(nanoseconds: 400_000_000)
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
