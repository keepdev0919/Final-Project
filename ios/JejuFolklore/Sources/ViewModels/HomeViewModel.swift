import Foundation
import MapKit

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var pins: [Pin] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Home extras (오늘의 설화 / 추천 코스)
    @Published var todayFolklore: TodayFolklore?
    @Published var recommendedCourses: [Course] = []
    @Published var isLoadingHomeData = false

    var pinGroups: [PinGroup] {
        Dictionary(grouping: pins, by: { "\(round($0.lat * 10000) / 10000)-\(round($0.lng * 10000) / 10000)" })
            .values
            .map { PinGroup(pins: $0) }
    }

    func loadAllPins() async {
        guard pins.isEmpty else { return }
        isLoading = true
        do {
            pins = try await PinsAPI.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// `/home/today` + `/home/recommendations` 를 병렬로 로드.
    /// 둘 중 하나가 실패해도 다른 하나는 표시될 수 있도록 개별 try? 처리.
    func loadHomeData() async {
        guard todayFolklore == nil && recommendedCourses.isEmpty else { return }
        isLoadingHomeData = true
        async let todayTask = try? HomeAPI.today()
        async let recsTask = try? HomeAPI.recommendations()
        let (today, recs) = await (todayTask, recsTask)
        self.todayFolklore = today
        self.recommendedCourses = recs ?? []
        isLoadingHomeData = false
    }

    /// 오늘의 설화에 해당하는 Pin(전체 pins에서 codeNo 매칭)을 찾아 반환.
    /// HomeView에서 카드 탭 시 지도 줌인 + 디테일 시트 오픈에 사용.
    func pin(for today: TodayFolklore) -> Pin? {
        pins.first { $0.codeNo == today.codeNo }
    }
}
