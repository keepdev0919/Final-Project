import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var journeys: [Journey] = []
    @Published var recommendedCourses: [Course] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// 사용자가 "다시 시도"를 눌렀을 때. 캐시를 무시하고 다시 부른다.
    func reload() async {
        journeys = []
        recommendedCourses = []
        errorMessage = nil
        await loadHome()
    }

    /// 여정과 추천 코스를 병렬로 부른다.
    /// 하나가 실패해도 다른 하나는 보여야 하므로 개별 `try?` 처리한다.
    ///
    /// ⚠️ `&&`인 이유: 하나만 성공했을 때 나머지를 다시 부르면 매 화면 진입마다
    /// 실패한 쪽을 재호출한다. 재시도는 `reload()`로 사용자가 명시적으로 한다.
    func loadHome() async {
        guard journeys.isEmpty && recommendedCourses.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        async let journeyTask = try? JourneyAPI.list()
        async let courseTask = try? HomeAPI.recommendations()
        let (loadedJourneys, loadedCourses) = await (journeyTask, courseTask)

        journeys = loadedJourneys ?? []
        recommendedCourses = loadedCourses ?? []

        if journeys.isEmpty && recommendedCourses.isEmpty {
            errorMessage = "지금은 불러올 수 없어요. 잠시 뒤 다시 시도해주세요."
        } else {
            errorMessage = nil
        }
    }
}
