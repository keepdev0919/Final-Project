import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    /// 홈의 주인공 — 스테이지 카드 6곳.
    @Published var stages: [HomeStage] = []
    /// 코스 탭으로 들어가는 곁길.
    @Published var recommendedCourses: [Course] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// 사용자가 "다시 시도"를 눌렀을 때. 이미 받은 걸 버리고 다시 부른다.
    func reload() async {
        stages = []
        recommendedCourses = []
        errorMessage = nil
        await loadHome()
    }

    /// 스테이지와 추천 코스를 병렬로 부른다.
    /// 하나가 실패해도 다른 하나는 보여야 하므로 개별 `try?` 처리한다.
    ///
    /// ⚠️ `&&`인 이유: 하나만 성공했을 때 나머지를 다시 부르면 매 화면 진입마다
    /// 실패한 쪽을 재호출한다. 재시도는 `reload()`로 사용자가 명시적으로 한다.
    func loadHome() async {
        guard stages.isEmpty && recommendedCourses.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        async let stageTask = try? HomeAPI.stages()
        async let courseTask = try? HomeAPI.recommendations()
        let (loadedStages, loadedCourses) = await (stageTask, courseTask)

        stages = loadedStages ?? []
        recommendedCourses = loadedCourses ?? []

        if stages.isEmpty && recommendedCourses.isEmpty {
            errorMessage = "지금은 불러올 수 없어요. 잠시 뒤 다시 시도해주세요."
        } else {
            errorMessage = nil
        }
    }
}
