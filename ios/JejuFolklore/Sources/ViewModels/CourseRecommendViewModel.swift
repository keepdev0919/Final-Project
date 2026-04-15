import Foundation

enum LoadingStep: String {
    case idle = ""
    case searching = "코스 검색 중..."
    case generating = "내러티브 생성 중..."
    case done = "완성!"
}

@MainActor
final class CourseRecommendViewModel: ObservableObject {
    // 신규 입력 상태
    @Published var selectedRegion: String = ""
    @Published var selectedStyle: String = ""
    @Published var durationDays: Int = 1

    // 리스트 결과
    @Published var courseList: [CourseListItem] = []
    @Published var isLoadingList: Bool = false

    // 상세 결과
    @Published var selectedCourse: Course?
    @Published var isLoadingDetail: Bool = false

    @Published var loadingStep: LoadingStep = .idle
    @Published var errorMessage: String?

    var isLoading: Bool { isLoadingList || isLoadingDetail }

    func fetchList() async {
        guard !selectedRegion.isEmpty, !selectedStyle.isEmpty else { return }
        errorMessage = nil
        courseList = []
        isLoadingList = true
        loadingStep = .searching

        do {
            let items = try await CourseAPI.list(
                region: selectedRegion,
                style: selectedStyle,
                durationDays: durationDays
            )
            courseList = items
            loadingStep = .idle
        } catch {
            errorMessage = error.localizedDescription
            loadingStep = .idle
        }
        isLoadingList = false
    }

    func fetchDetail(courseId: String) async {
        errorMessage = nil
        selectedCourse = nil
        isLoadingDetail = true
        loadingStep = .generating

        do {
            let course = try await CourseAPI.detail(courseId: courseId, style: selectedStyle)
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

    func reset() {
        selectedRegion = ""
        selectedStyle = ""
        durationDays = 1
        courseList = []
        selectedCourse = nil
        errorMessage = nil
        loadingStep = .idle
        isLoadingList = false
        isLoadingDetail = false
    }
}
