import Foundation

/// PLAY 진행 상태. 앱을 껐다 켜도 하던 자리로 돌아온다.
///
/// 현장에서 앱이 내려가는 일은 흔하다 — 전화가 오고, 사진을 찍고, 배터리를 아끼려
/// 화면을 끈다. 그때마다 처음부터 다시 하게 만들면 아무도 끝까지 못 간다.
struct PlayProgress: Codable, Equatable {
    let playId: String
    var currentPointId: String
    var currentMissionId: String
    var currentStepIndex: Int
    var completedMissionIds: [String]
    /// 복원한 기록 칸. 「생활기록 4/6」의 4가 이것이다.
    var discoveredRecordIds: [String]
    /// 건너뛴 미션. 진행은 되지만 **직접 발견한 것은 아니다** —
    /// CLEAR 화면에서 구분해 보여주려고 따로 센다.
    var skippedMissionIds: [String]
    var finalCleared: Bool
    let startedAt: Date
    var updatedAt: Date

    init(play: Play) {
        let first = play.orderedMissions.first
        self.playId = play.id
        self.currentPointId = first?.point.id ?? ""
        self.currentMissionId = first?.mission.id ?? ""
        self.currentStepIndex = 0
        self.completedMissionIds = []
        self.discoveredRecordIds = []
        self.skippedMissionIds = []
        self.finalCleared = false
        self.startedAt = Date()
        self.updatedAt = Date()
    }

    var isFinished: Bool { finalCleared }
}

/// UserDefaults 저장소. 여러 PLAY 를 동시에 붙잡고 있을 수 있다 —
/// 성읍을 하다 말고 다른 곳에 갔다가 돌아올 수 있어야 한다.
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

    /// 진행 중인 PLAY (아직 CLEAR 안 한 것). 프로필과 홈이 쓴다.
    func inProgress() -> [PlayProgress] {
        loadAll().values.filter { !$0.isFinished }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 완료한 PLAY.
    func completed() -> [PlayProgress] {
        loadAll().values.filter(\.isFinished).sorted { $0.updatedAt > $1.updatedAt }
    }
}
