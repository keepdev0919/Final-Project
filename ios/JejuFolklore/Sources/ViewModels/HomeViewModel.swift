import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    /// 홈에 뜨는 스테이지 카드. 이것 하나가 홈의 전부다.
    ///
    /// 「오늘의 추천 코스」 섹션은 2026-08-24에 없앴다 — 코스는 코스 탭이 온전히 담당하고,
    /// 홈은 스테이지 선택 화면이라 다른 성질의 목록이 섞이면 무엇을 하는 화면인지 흐려진다.
    @Published var stages: [HomeStage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// 사용자가 "다시 시도"를 눌렀을 때. 이미 받은 걸 버리고 다시 부른다.
    func reload() async {
        stages = []
        errorMessage = nil
        await loadHome()
    }

    func loadHome() async {
        guard stages.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        stages = (try? await HomeAPI.stages()) ?? []
        errorMessage = stages.isEmpty
            ? "지금은 불러올 수 없어요. 잠시 뒤 다시 시도해주세요."
            : nil
    }
}
