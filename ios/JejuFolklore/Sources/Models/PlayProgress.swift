import Foundation

/// **이번 판의 상태.** 진행 화면이 살아 있는 동안만 존재한다.
///
/// 화면 세 곳이 이걸 읽는다.
///
///     상단 HUD    생활기록 2 / 6
///     CLEAR       완료 미션 8/8 · 건너뛴 미션 · 걸린 시간
///     진행         지금 어느 Point · 어느 Mission · 몇 번째 Step
///
/// ## 기기에 저장하지 않는다 (2026-09-04 조익준님 결정)
///
/// 전에는 `PlayProgressStore` 가 이걸 UserDefaults 에 넣어 두고, 앱을 껐다 켜면
/// 하던 자리로 돌아오게 했다. 홈 카드와 PLAY 상세의 버튼도 그걸 보고
/// 「이어서 하기」·「다시 하기」로 갈렸다.
///
/// **그 갈래를 다 걷어냈다.** PLAY 는 언제나 처음부터 시작한다. 화면마다 상태에
/// 따라 다른 말이 나오던 것이 없어져서 만들고 확인하기가 단순해진다.
///
/// ⚠️ 대신 **나가면 진행이 사라진다.** 성읍은 60~75분짜리라 현장에서 전화가
/// 오거나 배터리를 아끼려 앱을 내리면 대장간집부터 다시 해야 한다. 나가기
/// 확인창이 그걸 말해준다. 다시 필요해지면 git 에서 저장소를 되살리면 된다.
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
