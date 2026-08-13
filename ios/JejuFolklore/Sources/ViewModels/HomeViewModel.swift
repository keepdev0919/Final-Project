import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var journeys: [Journey] = []
    @Published var recommendedCourses: [Course] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// 여정과 추천 코스를 병렬로 부른다.
    /// 하나가 실패해도 다른 하나는 보여야 하므로 개별 `try?` 처리한다.
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
