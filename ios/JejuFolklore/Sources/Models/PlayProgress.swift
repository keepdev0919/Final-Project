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
