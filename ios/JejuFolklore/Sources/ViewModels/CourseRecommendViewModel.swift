import Foundation

enum LoadingStep: String {
    case idle = ""
    case searching = "설화 검색 중..."
    case optimizing = "동선 최적화 중..."
    case done = "완성!"
}

@MainActor
final class CourseRecommendViewModel: ObservableObject {
    @Published var selectedTheme: String = ""
    @Published var durationDays: Int = 1
    @Published var transport: String = "car"
    @Published var loadingStep: LoadingStep = .idle
    @Published var result: Course?
    @Published var errorMessage: String?

    let themes = ["신화", "도깨비·요괴", "사랑과 이별", "바다·해녀", "오름·자연"]

    var isLoading: Bool { loadingStep != .idle && loadingStep != .done && result == nil && errorMessage == nil }

    func recommend() async {
        guard !selectedTheme.isEmpty else { return }
        errorMessage = nil
        result = nil

        loadingStep = .searching
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        loadingStep = .optimizing

        do {
            let course = try await CourseAPI.recommend(
                theme: selectedTheme,
                durationDays: durationDays,
                transport: transport
            )
            loadingStep = .done
            try? await Task.sleep(nanoseconds: 600_000_000)
            result = course
            loadingStep = .idle
        } catch {
            loadingStep = .idle
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        result = nil
        errorMessage = nil
        loadingStep = .idle
    }
}
