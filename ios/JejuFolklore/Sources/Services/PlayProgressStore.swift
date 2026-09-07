import Foundation

/// `PlayProgress` 의 UserDefaults 저장소. 여러 PLAY 를 동시에 붙잡고 있을 수 있다 —
/// 성읍을 하다 말고 다른 곳에 갔다가 돌아올 수 있어야 한다.
///
/// ## 2026-09-07 되살림
///
/// 2026-09-04 에 「PLAY 는 언제나 처음부터」로 걷어냈던 것을, 성읍이 60~75분짜리라
/// 현장에서 전화·배터리로 앱이 내려가면 대장간집부터 다시 해야 하는 문제가 커서
/// 되살렸다. `RunnerViewModel` 이 완료한 미션이 바뀔 때마다 `save(_:)` 를 부른다 —
/// **Step 단위가 아니라 미션 단위로 저장한다.** 나가기 확인창의 문구가 그 정도를
/// 정확히 말한다 (`PlayRunnerView` 참조).
@MainActor
final class PlayProgressStore {
    static let shared = PlayProgressStore()

    private let key = "play_progress_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    private func loadAll() -> [String: PlayProgress] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        guard let map = try? decoder.decode([String: PlayProgress].self, from: data) else {
            // 저장 형식이 바뀌어 못 읽는 데이터는 버린다. 남겨두면 매번 실패를 반복한다.
            UserDefaults.standard.removeObject(forKey: key)
            return [:]
        }
        return map
    }

    private func saveAll(_ map: [String: PlayProgress]) {
        guard let data = try? encoder.encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load(playId: String) -> PlayProgress? { loadAll()[playId] }

    func save(_ progress: PlayProgress) {
        var map = loadAll()
        var p = progress
        p.updatedAt = Date()
        map[p.playId] = p
        saveAll(map)
    }

    func clear(playId: String) {
        var map = loadAll()
        map.removeValue(forKey: playId)
        saveAll(map)
    }

    /// 진행 중인 PLAY (아직 CLEAR 안 한 것). 홈 카드가 쓴다.
    func inProgress() -> [PlayProgress] {
        loadAll().values.filter { !$0.isFinished }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 완료한 PLAY.
    func completed() -> [PlayProgress] {
        loadAll().values.filter(\.isFinished).sorted { $0.updatedAt > $1.updatedAt }
    }
}
