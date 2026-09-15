import Foundation

/// **이번 판의 상태.** 진행 화면이 살아 있는 동안만 존재한다.
///
/// 화면 세 곳이 이걸 읽는다.
///
///     상단 HUD    생활기록 2 / 6
///     CLEAR       완료 미션 8/8 · 건너뛴 미션 · 걸린 시간
///     진행         지금 어느 Point · 어느 Mission · 몇 번째 Step
///
/// ## `PlayProgressStore` 가 미션 단위로 저장한다 (2026-09-07 되살림)
///
/// 2026-09-04 에 한 번 걷어냈다 — PLAY 는 언제나 처음부터, 화면마다 상태에 따라
/// 다른 말이 나오던 것을 없애 만들고 확인하기를 단순하게 하려고 했다. 그런데
/// 성읍은 60~75분짜리라 현장에서 전화가 오거나 배터리를 아끼려 앱을 내리면
/// 대장간집부터 다시 해야 했다 — 그 손실이 더 크다고 판단해 되살렸다.
///
/// **Step 단위가 아니라 미션 단위로 저장한다.** 미션을 하나 끝낼 때마다
/// `RunnerViewModel` 이 이 구조체를 `PlayProgressStore` 에 write 한다. 그래서
/// 나갔다 들어오면 **마지막으로 완료한 미션 다음**부터 시작하고, 진행 중이던
/// 미션의 Step·힌트 상태는 되살아나지 않는다 — 나가기 확인창이 그 정도를
/// 정확히 말해준다.
///
/// 단, 끝낸 미션의 발견·이야기를 **보던 중**에 나갔으면 그 자리부터 다시 연다
/// (`pendingReveal`, 2026-09-15).
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
    /// 아직 다 못 본 발견·이야기. 없으면 nil. 이 칸이 생기기 전(2026-09-15 전)에
    /// 기기에 저장된 진행에는 없다 — 그때는 nil 로 읽는다 (`init(from:)`).
    var pendingReveal: PendingReveal?
    let startedAt: Date
    var updatedAt: Date

    /// 미션은 끝냈지만 **아직 다 못 본** 발견·이야기 (2026-09-15).
    ///
    /// 진행은 미션을 끝내는 순간 저장된다. 그 뒤에 나오는 발견·이야기를 보다가 앱을
    /// 내리면 전에는 이어서 할 때 그걸 건너뛰고 다음 미션(마지막이면 FINAL)으로 갔다 —
    /// 방금 찾은 것의 의미를 못 듣고 지나가는 셈이다. FINAL 이야기를 듣다 나가면 맞힌
    /// FINAL 을 다시 풀어야 했다. 그래서 무엇을 보던 중이었는지 같이 적어 두고,
    /// 이어서 할 때 거기부터 연다. 웹(`miniapp` 의 `PendingReveal`)도 같은 두 경우다.
    enum PendingReveal: Codable, Equatable {
        enum Stage: String, Codable { case discovery, story }
        /// 미션을 끝낸 뒤 그 미션의 발견 또는 이야기를 보던 중.
        case afterMission(missionId: String, stage: Stage)
        /// FINAL 을 맞힌 뒤 FINAL 이야기(`final.story`)를 듣던 중. 끝나면 CLEAR 다.
        case afterFinal
    }

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
        self.pendingReveal = nil
        self.startedAt = Date()
        self.updatedAt = Date()
    }

    /// 저장된 진행을 읽는다. 직접 쓴 이유는 `pendingReveal` 하나다.
    ///
    /// 칸이 없으면(옛 저장) nil 이다. 칸이 있는데 못 읽는 모양이어도(경우가 늘어난
    /// 저장을 옛 앱이 읽을 때) nil 로 본다 — 자동 생성 디코딩은 이때 **진행 전체**를
    /// 못 읽어 `PlayProgressStore` 가 통째로 버린다. 못 읽는 것은 「보다 만 자리」뿐이고,
    /// 그게 없어도 완료한 미션 다음부터 이어갈 수 있다. 쓰기(`encode`)는 자동 생성 그대로다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playId = try c.decode(String.self, forKey: .playId)
        currentPointId = try c.decode(String.self, forKey: .currentPointId)
        currentMissionId = try c.decode(String.self, forKey: .currentMissionId)
        currentStepIndex = try c.decode(Int.self, forKey: .currentStepIndex)
        completedMissionIds = try c.decode([String].self, forKey: .completedMissionIds)
        discoveredRecordIds = try c.decode([String].self, forKey: .discoveredRecordIds)
        skippedMissionIds = try c.decode([String].self, forKey: .skippedMissionIds)
        finalCleared = try c.decode(Bool.self, forKey: .finalCleared)
        pendingReveal = try? c.decodeIfPresent(PendingReveal.self, forKey: .pendingReveal)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    var isFinished: Bool { finalCleared }
}
