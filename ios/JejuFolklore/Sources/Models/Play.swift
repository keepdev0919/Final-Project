import Foundation
import CoreLocation

/// PLAY 콘텐츠. 서버 `GET /plays/{id}` 가 내려준다.
///
/// 구조는 백엔드 `models/play.py` 와 같다.
///
///     PLAY → Point → Mission → Step
///
/// **Mission 하나 ≠ 화면 하나다.** 호령창은 `찾았어요 → 오른쪽 → 왜` 세 Step 이
/// 모여 하나다. 그래서 화면을 정하는 것은 `Step.inputType` 하나뿐이고,
/// `Mission.patterns`(FIND·COMPARE·INFER…)는 콘텐츠 검수용 이름표다.

// MARK: - 답

/// Step 의 정답. `inputType` 마다 모양이 다르다.
///
/// 서버가 JSON 으로 문자열·숫자·배열·null 을 섞어 보내므로 하나로 받아 둔다.
enum MissionAnswer: Equatable {
    case none                 // CONFIRM — 누르면 통과
    case text(String)         // CHOICE(보기 id) · DIRECTION(LEFT/RIGHT/…)
    case number(Int)          // NUMBER
    case list([String])       // SHORT_TEXT(허용 답안) · MATCH_ORDER(순서 또는 "a>x")
}

extension MissionAnswer: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .none; return }
        if let v = try? c.decode(Int.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .text(v); return }
        if let v = try? c.decode([String].self) { self = .list(v); return }
        self = .none
    }
}

// MARK: - Step

enum MissionInput: String, Decodable {
    case confirm = "CONFIRM"
    case choice = "CHOICE"
    case direction = "DIRECTION"
    case number = "NUMBER"
    case shortText = "SHORT_TEXT"
    case matchOrder = "MATCH_ORDER"
}

struct MissionOption: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    /// 그림 보기. 배치도처럼 글자로 설명하기 어려운 것에만 쓴다.
    /// ⚠️ 미션의 답이 되는 **현실물**을 그림으로 대체하지 않는다 (DESIGN.md §1).
    let image: String?
}

struct MissionStep: Decodable, Identifiable, Equatable {
    let inputType: MissionInput
    let prompt: String
    let options: [MissionOption]
    /// 짝 맞추기의 오른쪽 항목. 비어 있으면 MATCH_ORDER 는 '순서 세우기'다.
    let matchTargets: [MissionOption]
    let answer: MissionAnswer
    let successFeedback: String
    let failureFeedback: String

    /// 같은 Mission 안에서 Step 을 구분하는 값. 서버가 id 를 주지 않아 내용으로 만든다.
    var id: String { "\(inputType.rawValue)-\(prompt.hashValue)" }

    /// 오답 문구. 원고가 비워두면 공용 문구를 쓴다 —
    /// **"틀렸습니다"라고 하지 않는다.** 시험이 아니라 관광이다.
    var failureText: String {
        failureFeedback.isEmpty
            ? "아직 아닌 것 같아요. 실제 대상을 다시 한번 살펴보세요."
            : failureFeedback
    }

    /// 사용자가 넣은 답이 맞는지 **단말에서** 판정한다.
    ///
    /// 서버 왕복을 하지 않는다. 현장은 통신이 불안하고, 이 게임은 경쟁이 아니라
    /// 자기 속도 관광이라 답을 숨길 이유가 약하다 (`[정답과 이야기 보기]`로 이미 열려 있다).
    func isCorrect(_ submitted: MissionAnswer) -> Bool {
        switch (inputType, answer, submitted) {
        case (.confirm, _, _):
            return true
        case (_, .text(let want), .text(let got)):
            return want == got
        case (_, .number(let want), .number(let got)):
            return want == got
        case (.shortText, .list(let allowed), .text(let got)):
            // 표기가 갈리는 답 때문에 정답을 못 맞히는 일이 제일 흔하다.
            // 공백과 대소문자를 무시하고 허용 답안 중 하나와 같으면 통과시킨다.
            let norm = { (s: String) in
                s.replacingOccurrences(of: " ", with: "").lowercased()
            }
            return allowed.map(norm).contains(norm(got))
        case (.matchOrder, .list(let want), .list(let got)):
            // 짝 맞추기는 순서가 상관없고, 순서 세우기는 상관있다.
            return matchTargets.isEmpty ? want == got : Set(want) == Set(got)
        default:
            return false
        }
    }
}

// MARK: - Mission

struct MissionHint: Decodable, Equatable {
    let text: String
}

struct MissionDiscovery: Decodable, Equatable {
    let title: String
    let body: String
}

/// 웹 검증 등급. 현장 답사를 하지 않기로 했으므로(2026-09-02),
/// `likely` 인 미션은 현장에서 못 찾을 수 있다 — 힌트·건너뛰기·신고가 그래서 필수다.
enum MissionVerification: String, Decodable {
    case strong, likely, unverified
}

struct Mission: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let patterns: [String]
    let prompt: String
    let steps: [MissionStep]
    let hints: [MissionHint]
    let discovery: MissionDiscovery?
    /// 채워지는 진행도 칸. 없을 수 있다 —
    /// **모든 Mission 이 독립적인 Discovery 를 가질 필요는 없다** (콘텐츠.md §13).
    let progressReward: String?
    let verification: MissionVerification
    let isShowcase: Bool
}

// MARK: - Point

struct PlayPoint: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let objective: String
    let lat: Double?
    let lng: Double?
    let navigationText: String
    let intro: String
    let missions: [Mission]

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Story

struct StorySource: Decodable, Equatable {
    let kind: String
    let ref: String
    let note: String
}

/// 발견의 의미. **놀멍봅서가 직접 쓴 문장이다** — 오디 대본을 그대로 틀지 않는다.
/// `script` 하나가 화면 자막이자 TTS 원문이다.
struct PlayStory: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let script: String
    let sources: [StorySource]
    let unlockAfterMission: String
}

// MARK: - Final · Clear · 진행도

struct FinalStage: Decodable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let step: MissionStep
    let story: PlayStory?
}

struct ClearStage: Decodable, Equatable {
    let title: String
    let body: String
}

/// 이번 PLAY 에서 실제로 모으는 것 한 칸.
/// XP·코인 같은 범용 점수를 쓰지 않는다 — 성읍은 「생활기록 6칸」이다.
struct ProgressRecord: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
}

// MARK: - PLAY

enum RouteRevealMode: String, Decodable {
    case full = "FULL"
    case progressive = "PROGRESSIVE"
}

struct Play: Decodable, Identifiable, Equatable {
    let id: String
    /// 놀멍봅서가 발급한 불변 Place ID. 오디 stid 나 KTO contentId 가 아니다.
    let placeId: String
    let placeKey: String
    let placeName: String

    let title: String
    let fantasy: String
    let role: String
    let objective: String

    let estimatedMinutesMin: Int
    let estimatedMinutesMax: Int
    let distanceMeters: Int
    let difficulty: String

    let progressLabel: String
    let progressRecords: [ProgressRecord]
    /// 시작 버튼 문구. 원고가 비워두면 공통 문구를 쓴다.
    let startCta: String

    let routeRevealMode: RouteRevealMode
    let startName: String
    let startLat: Double?
    let startLng: Double?
    let finishName: String

    let cautions: [String]
    let points: [PlayPoint]
    let stories: [PlayStory]
    let final: FinalStage?
    let clear: ClearStage?
    /// 「가이드 투어와 무엇이 다른가」. PLAY 5개가 공통으로 쓴다.
    let comparison: GuideComparison?

    var missionCount: Int { points.reduce(0) { $0 + $1.missions.count } }

    /// 시작 버튼에 쓸 말. **버튼 문구는 Game Fantasy 의 일부다** —
    /// 성읍은 「복원 시작」이고, 문구를 안 정한 PLAY 는 「탐험 시작」이다.
    var startLabel: String {
        startCta.isEmpty ? "탐험 시작" : startCta
    }

    /// 이어서 할 때. 「복원 시작」 → 「이어서 복원하기」처럼 앞말을 살린다.
    /// 시작 문구가 `~ 시작` 꼴이 아니면 그냥 「이어서 하기」로 둔다.
    var resumeLabel: String {
        let label = startLabel
        guard label.hasSuffix(" 시작") else { return "이어서 하기" }
        return "이어서 " + label.replacingOccurrences(of: " 시작", with: "") + "하기"
    }

    /// 「60~75분」. 최소·최대가 같으면 하나만 쓴다.
    var durationText: String {
        estimatedMinutesMin == estimatedMinutesMax
            ? "\(estimatedMinutesMin)분"
            : "\(estimatedMinutesMin)~\(estimatedMinutesMax)분"
    }

    /// 「약 1km」 — 1km 미만은 m 로 쓴다.
    var distanceText: String {
        distanceMeters < 1000
            ? "\(distanceMeters)m"
            : String(format: "약 %.1fkm", Double(distanceMeters) / 1000)
                .replacingOccurrences(of: ".0km", with: "km")
    }

    /// 시작점. 원고에 좌표가 없으면 첫 Point 로 안내한다 —
    /// **추측 좌표를 넣지 않기로 했다** (`data/plays/*.json` 참조).
    var startCoordinate: CLLocationCoordinate2D? {
        if let lat = startLat, let lng = startLng {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return points.first?.coordinate
    }

    func story(after missionId: String) -> PlayStory? {
        stories.first { $0.unlockAfterMission == missionId }
    }

    func point(id: String) -> PlayPoint? { points.first { $0.id == id } }

    /// 모든 미션을 Point 순서대로 편 목록. 진행 계산에 쓴다.
    var orderedMissions: [(point: PlayPoint, mission: Mission)] {
        points.flatMap { p in p.missions.map { (point: p, mission: $0) } }
    }
}

// MARK: - 가이드 투어 비교

struct ComparisonRow: Decodable, Identifiable, Equatable {
    let aspect: String
    let left: String
    let leftIcon: String
    let right: String
    let rightIcon: String
    /// 숫자를 쓸 때의 근거. 비어 있으면 화면에 출처 줄이 안 뜬다.
    let source: String

    var id: String { aspect }
}

/// PLAY 상세 맨 아래의 「가이드 투어와 무엇이 다른가」.
///
/// `CLAUDE.md` 는 "전문 가이드의 역할을 개인의 속도에 맞는 게임형 경험으로
/// 바꾼다"고 적어놨는데, 앱 어디에도 **「그럼 가이드 투어랑 뭐가 다른데?」에
/// 답하는 자리가 없었다.** 시작을 망설이는 사람이 마지막으로 보는 곳에 둔다.
struct GuideComparison: Decodable, Equatable {
    let title: String
    let leftLabel: String
    let rightLabel: String
    let rows: [ComparisonRow]
}

// MARK: - 목록 · 지도

/// 홈 카드·지도 핀·장소 상세가 쓰는 가벼운 형태.
struct PlaySummary: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let placeId: String
    let placeName: String
    let title: String
    let objective: String
    let estimatedMinutesMin: Int
    let estimatedMinutesMax: Int
    let distanceMeters: Int
    let difficulty: String
    let missionCount: Int
    let thumbnail: String?

    var durationText: String {
        estimatedMinutesMin == estimatedMinutesMax
            ? "\(estimatedMinutesMin)분"
            : "\(estimatedMinutesMin)~\(estimatedMinutesMax)분"
    }

    var distanceText: String {
        distanceMeters < 1000
            ? "\(distanceMeters)m"
            : String(format: "약 %.1fkm", Double(distanceMeters) / 1000)
                .replacingOccurrences(of: ".0km", with: "km")
    }
}

/// PLAY 지도 핀.
///
/// 지도가 답하는 질문이 바뀌었다 — "오디 해설이 몇 개 있나"가 아니라
/// **"제주 어디서 놀멍봅서를 할 수 있고, 앞으로 어디에 생기나"** 다.
struct PlayMapPin: Decodable, Identifiable, Equatable, Hashable {
    enum Status: String, Decodable {
        case active     // 지금 플레이할 수 있다
        case preparing  // 준비 중
    }

    let placeId: String
    let placeName: String
    let lat: Double
    let lng: Double
    let status: Status
    let play: PlaySummary?

    var id: String { placeId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
