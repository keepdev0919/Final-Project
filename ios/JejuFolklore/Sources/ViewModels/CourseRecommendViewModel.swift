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

    // Q1(분위기) + Q2(장소) → 백엔드 theme 문자열 매핑
    // 바다해녀·도깨비·신화·사랑과이별·오름자연 5가지 테마
    static func mapTheme(mood: String, place: String) -> String {
        switch mood {
        case "신비롭고 으스스한":
            return place == "바다" ? "바다해녀" : "도깨비"
        case "웅장하고 신성한":
            return "신화"
        case "따뜻하고 감동적인":
            switch place {
            case "바다":   return "바다해녀"
            case "오름·산": return "오름자연"
            default:       return "사랑과이별"
            }
        case "사람들의 삶 이야기":
            switch place {
            case "바다":   return "바다해녀"
            case "오름·산": return "오름자연"
            case "마을":   return "사랑과이별"
            default:       return "바다해녀"
            }
        default:
            return "신화"
        }
    }

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
