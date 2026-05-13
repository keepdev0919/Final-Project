# AI 설화 동행자 — 여행 중/여행 후 서비스 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GPS 지오펜스 도착 감지 → AI 설화 동행자 채팅 → 여행 일지 생성까지 이어지는 여행 중/여행 후 서비스를 구현한다.

**Architecture:** 백엔드에 `/travel/companion` (SSE 스트리밍, 캐릭터 페르소나), `/travel/journal` (GPT 요약 → 여행 일지) 엔드포인트를 추가한다. iOS는 LocationService에 30초 체류 조건을 추가하고, ExploreViewModel/ExploreView를 확장해 도착 오버레이 → 동행자 채팅 → 일지 뷰 흐름을 완성한다. `categoryScores`는 `CoursePreviewView`를 통해 `ExploreView`까지 전달한다.

**Tech Stack:** Python FastAPI + LangChain + GPT-4o (SSE), Swift/SwiftUI, CoreLocation CLCircularRegion-style dwell detection, UserDefaults (Codable JSON)

---

## File Structure

**Create (backend):**
- `backend/routers/travel.py` — companion SSE + journal 엔드포인트

**Modify (backend):**
- `backend/main.py` — travel 라우터 등록

**Create (iOS):**
- `ios/JejuFolklore/Sources/Models/TravelSession.swift` — TravelChatMessage, PlaceChatLog, TravelSession, CompanionCharacter
- `ios/JejuFolklore/Sources/Services/TravelAPI.swift` — companion SSE stream + journal POST
- `ios/JejuFolklore/Sources/Views/ArrivalOverlayView.swift` — 전체화면 도착 오버레이 (탭 1회)
- `ios/JejuFolklore/Sources/Views/CompanionChatView.swift` — 동행자 채팅 화면
- `ios/JejuFolklore/Sources/Views/TravelJournalView.swift` — 여행 일지 표시 화면

**Modify (iOS):**
- `ios/JejuFolklore/Sources/Services/LocationService.swift` — 30초 체류 조건 추가
- `ios/JejuFolklore/Sources/ViewModels/ExploreViewModel.swift` — 동행자 상태, 채팅 로그, 일지 관리
- `ios/JejuFolklore/Sources/Views/ExploreView.swift` — 도착 오버레이 + 채팅 + 일지 뷰 연결
- `ios/JejuFolklore/Sources/Views/CoursePreviewView.swift` — categoryScores 수신 + ExploreView로 전달

---

## Task 1: Backend — travel.py 라우터 생성

**Files:**
- Create: `backend/routers/travel.py`
- Modify: `backend/main.py`

- [ ] **Step 1: travel.py 파일 생성 (companion SSE 엔드포인트)**

```python
# backend/routers/travel.py
"""여행 중/여행 후 서비스 엔드포인트."""
import os
import json
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel

router = APIRouter(prefix="/travel", tags=["travel"])

llm_stream = ChatOpenAI(
    model="gpt-4o",
    temperature=0.7,
    streaming=True,
    api_key=os.getenv("OPENAI_API_KEY"),
)
llm = ChatOpenAI(
    model="gpt-4o",
    temperature=0.5,
    api_key=os.getenv("OPENAI_API_KEY"),
)

# ─── 캐릭터 시스템 프롬프트 ───────────────────────────────────────────────────

CHARACTER_PROMPTS: dict[str, str] = {
    "당신/심방": """당신은 제주 마을을 수호하는 당신(堂神)이자 심방(무당)입니다.
이 장소에 깃든 신화와 신격 전승을 엄숙하면서도 따뜻하게 전해줍니다.
말투: 고풍스럽고 신비롭지만, 여행자를 가족처럼 맞이하는 온기가 있습니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "도깨비": """당신은 재치 있고 장난기 많은 제주 도깨비입니다.
생활민담과 교훈담 속 인물들의 이야기를 유머와 함께 풀어냅니다.
말투: 경쾌하고 익살스럽지만, 교훈의 핵심은 놓치지 않습니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "마을 할망": """당신은 이 마을을 수백 년 지켜온 마을 할망(할머니 신)입니다.
마을 공동체가 함께 전해온 이야기와 당제 의식을 정겹게 들려줍니다.
말투: 제주 사투리가 살짝 섞인 따뜻한 할머니 말투입니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "영등신/해녀 선배": """당신은 바다와 바람의 여신 영등신이자, 수십 년 경력의 할망 해녀입니다.
바다, 어부, 용왕, 해녀의 삶에 얽힌 전승을 들려줍니다.
말투: 바다처럼 시원하고 강인하지만, 물질의 고됨을 아는 깊이가 있습니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "도체비": """당신은 제주의 으스스한 도체비(귀신·초자연 존재)입니다.
초자연 존재담과 기이한 전설을 신비롭고 오싹하게 풀어냅니다.
말투: 속삭이듯 말하다가 갑자기 단도직입적이 되는, 예측 불가능한 방식입니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",
}

VALID_CHARACTERS = set(CHARACTER_PROMPTS.keys())


# ─── Request 모델 ──────────────────────────────────────────────────────────────

class ChatHistoryItem(BaseModel):
    role: str   # "user" | "assistant"
    content: str

class CompanionChatRequest(BaseModel):
    place_name: str
    folklore_summaries: list[str]   # 장소 주변 설화 요약 목록 (최대 3개)
    companion_type: str             # CHARACTER_PROMPTS 키 중 하나
    message: str
    history: list[ChatHistoryItem] = []

class PlaceChatLogItem(BaseModel):
    place_name: str
    messages: list[ChatHistoryItem]

class JournalRequest(BaseModel):
    visited_places: list[str]
    chat_logs: list[PlaceChatLogItem]


# ─── 동행자 채팅 (SSE 스트리밍) ───────────────────────────────────────────────

@router.post("/companion")
async def companion_chat(body: CompanionChatRequest):
    character = body.companion_type if body.companion_type in VALID_CHARACTERS else "도깨비"
    system_text = CHARACTER_PROMPTS[character]

    # 장소 컨텍스트 주입
    if body.folklore_summaries:
        folklore_ctx = "\n".join(f"- {s}" for s in body.folklore_summaries[:3])
        system_text += f"\n\n현재 장소: {body.place_name}\n이 장소의 설화:\n{folklore_ctx}"
    else:
        system_text += f"\n\n현재 장소: {body.place_name}\n(이 장소에 특정 설화 기록은 없습니다. 제주 설화 전반적 맥락으로 대화해주세요.)"

    # 첫 메시지면 동행자가 먼저 말을 건네도록
    is_first = len(body.history) == 0 and body.message == "__GREETING__"

    messages = [SystemMessage(content=system_text)]
    for h in body.history[-8:]:
        if h.role == "user":
            messages.append(HumanMessage(content=h.content))
        else:
            from langchain_core.messages import AIMessage
            messages.append(AIMessage(content=h.content))

    if is_first:
        messages.append(HumanMessage(content=f"{body.place_name}에 방금 도착했어요. 반갑게 인사해주세요."))
    else:
        messages.append(HumanMessage(content=body.message))

    async def stream_response():
        try:
            async for chunk in llm_stream.astream(messages):
                if chunk.content:
                    yield f"data: {json.dumps({'text': chunk.content}, ensure_ascii=False)}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)}, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(stream_response(), media_type="text/event-stream")


# ─── 여행 일지 생성 ────────────────────────────────────────────────────────────

JOURNAL_SYSTEM_PROMPT = """당신은 감성적인 여행 기록 작가입니다.
사용자가 제주도를 여행하며 AI 동행자와 나눈 대화를 바탕으로,
개인화된 여행 일지를 작성해주세요.

가이드라인:
- 방문한 장소들을 시간 순서로 엮어 300~500자 한국어 산문으로 작성
- 대화에서 언급된 설화나 인상적인 내용을 자연스럽게 녹여내세요
- 관광 안내문이 아닌, 여행자의 1인칭 회고 형식으로 쓰세요
- 마지막 문장은 이 여행이 남긴 감상으로 마무리해주세요"""


@router.post("/journal")
async def generate_journal(body: JournalRequest):
    places_text = ", ".join(body.visited_places) if body.visited_places else "방문 장소 없음"

    chat_summary_parts = []
    for log in body.chat_logs:
        msgs = [f"[{m.role}] {m.content}" for m in log.messages[:6]]
        chat_summary_parts.append(f"--- {log.place_name} ---\n" + "\n".join(msgs))
    chat_text = "\n\n".join(chat_summary_parts) if chat_summary_parts else "(대화 기록 없음)"

    prompt = (
        f"방문 장소: {places_text}\n\n"
        f"동행자와의 대화:\n{chat_text}\n\n"
        "위 여행을 회고하는 개인 여행 일지를 작성해주세요."
    )

    try:
        result = await llm.ainvoke([
            SystemMessage(content=JOURNAL_SYSTEM_PROMPT),
            HumanMessage(content=prompt),
        ])
        return {"journal_text": result.content}
    except Exception as e:
        return {"journal_text": "", "error": str(e)}
```

- [ ] **Step 2: main.py에 travel 라우터 등록**

`backend/main.py`를 열어 기존 라우터 등록 패턴 아래에 추가:

```python
from routers import travel
app.include_router(travel.router)
```

기존 `from routers import pins, chat, course, tts, tourist, place` 줄을 찾아서:

```python
from routers import pins, chat, course, tts, tourist, place, travel
# ...
app.include_router(travel.router)
```

- [ ] **Step 3: 수동 검증 (백엔드 서버 재시작 후 curl 테스트)**

```bash
cd /Users/choikjun/Desktop/keepdev/졸프/backend
# 서버 재시작 (이미 실행 중이면 재시작)
curl -X POST http://localhost:8000/travel/companion \
  -H "Content-Type: application/json" \
  -d '{
    "place_name": "성산일출봉",
    "folklore_summaries": ["설문대할망이 이 바위를 쌓았다는 전설이 있습니다."],
    "companion_type": "도깨비",
    "message": "__GREETING__",
    "history": []
  }' \
  --no-buffer
```

Expected: `data: {"text": "..."}` SSE 라인들이 스트리밍으로 출력됨

```bash
curl -X POST http://localhost:8000/travel/journal \
  -H "Content-Type: application/json" \
  -d '{
    "visited_places": ["성산일출봉", "협재해수욕장"],
    "chat_logs": [
      {"place_name": "성산일출봉", "messages": [
        {"role": "assistant", "content": "반갑수다!"},
        {"role": "user", "content": "설화 알려줘"},
        {"role": "assistant", "content": "설문대할망 이야기..."}
      ]}
    ]
  }'
```

Expected: `{"journal_text": "..."}` JSON 응답

- [ ] **Step 4: 커밋**

```bash
git add backend/routers/travel.py backend/main.py
git commit -m "feat(backend): add /travel/companion SSE and /travel/journal endpoints"
```

---

## Task 2: iOS — TravelSession 모델 정의

**Files:**
- Create: `ios/JejuFolklore/Sources/Models/TravelSession.swift`

- [ ] **Step 1: TravelSession.swift 생성**

```swift
// ios/JejuFolklore/Sources/Models/TravelSession.swift
import Foundation

// MARK: - CompanionCharacter

enum CompanionCharacter: String, Codable, CaseIterable {
    case mudang = "당신/심방"
    case dokkaebi = "도깨비"
    case hallam = "마을 할망"
    case yeondeung = "영등신/해녀 선배"
    case dochevi = "도체비"

    var displayName: String { rawValue }

    var emoji: String {
        switch self {
        case .mudang:    return "🪷"
        case .dokkaebi:  return "👺"
        case .hallam:    return "👵"
        case .yeondeung: return "🌊"
        case .dochevi:   return "👻"
        }
    }

    var greeting: String {
        switch self {
        case .mudang:    return "당신이 오기를 기다렸습니다."
        case .dokkaebi:  return "어이쿠, 손님이 왔구만!"
        case .hallam:    return "아이고, 어서 오라게."
        case .yeondeung: return "바다 바람이 불어왔구나."
        case .dochevi:   return "...왔군."
        }
    }

    static func from(categoryScores: [String: Int]) -> CompanionCharacter {
        let top = categoryScores.max(by: { $0.value < $1.value })?.key ?? ""
        switch top {
        case "무속신화·신격 전승": return .mudang
        case "생활민담·교훈담":   return .dokkaebi
        case "마을 공동체 전승":  return .hallam
        case "해양·어촌 전승":    return .yeondeung
        case "초자연 존재담":     return .dochevi
        default:                 return .dokkaebi
        }
    }
}

// MARK: - TravelChatMessage

struct TravelChatMessage: Codable, Identifiable, Equatable {
    var id: UUID
    let role: String    // "user" | "assistant"
    let content: String
    let timestamp: Date

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - PlaceChatLog

struct PlaceChatLog: Codable, Identifiable {
    var id: String { placeName }
    let placeName: String
    var messages: [TravelChatMessage]
}

// MARK: - TravelSession

struct TravelSession: Codable {
    let courseId: String
    let companion: CompanionCharacter
    let startedAt: Date
    var visitedPlaceNames: [String]
    var chatLogs: [PlaceChatLog]

    init(courseId: String, companion: CompanionCharacter) {
        self.courseId = courseId
        self.companion = companion
        self.startedAt = Date()
        self.visitedPlaceNames = []
        self.chatLogs = []
    }

    // 장소의 채팅 로그 조회 또는 생성
    mutating func chatLog(for placeName: String) -> PlaceChatLog {
        if let idx = chatLogs.firstIndex(where: { $0.placeName == placeName }) {
            return chatLogs[idx]
        }
        let newLog = PlaceChatLog(placeName: placeName, messages: [])
        chatLogs.append(newLog)
        return newLog
    }

    mutating func appendMessage(_ msg: TravelChatMessage, to placeName: String) {
        if let idx = chatLogs.firstIndex(where: { $0.placeName == placeName }) {
            chatLogs[idx].messages.append(msg)
        } else {
            chatLogs.append(PlaceChatLog(placeName: placeName, messages: [msg]))
        }
    }
}

// MARK: - TravelStore (UserDefaults persistence)

final class TravelStore {
    static let shared = TravelStore()
    private let key = "active_travel_session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private init() {}

    func save(_ session: TravelSession) {
        if let data = try? encoder.encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> TravelSession? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? decoder.decode(TravelSession.self, from: data) else {
            return nil
        }
        return session
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
```

- [ ] **Step 2: Xcode에서 빌드 확인**

Xcode에서 `⌘B`로 빌드. 에러 없으면 통과.

- [ ] **Step 3: 커밋**

```bash
git add "ios/JejuFolklore/Sources/Models/TravelSession.swift"
git commit -m "feat(ios): add TravelSession, CompanionCharacter, TravelStore models"
```

---

## Task 3: iOS — TravelAPI 서비스 생성

**Files:**
- Create: `ios/JejuFolklore/Sources/Services/TravelAPI.swift`

- [ ] **Step 1: TravelAPI.swift 생성**

ChatAPI.swift의 SSE stream 패턴을 그대로 따른다.

```swift
// ios/JejuFolklore/Sources/Services/TravelAPI.swift
import Foundation

struct CompanionChatRequest: Encodable {
    let placeName: String
    let folkloreSummaries: [String]
    let companionType: String
    let message: String
    let history: [CompanionHistoryItem]
}

struct CompanionHistoryItem: Encodable {
    let role: String
    let content: String
}

struct JournalRequestBody: Encodable {
    let visitedPlaces: [String]
    let chatLogs: [JournalChatLog]
}

struct JournalChatLog: Encodable {
    let placeName: String
    let messages: [CompanionHistoryItem]
}

struct JournalResponse: Decodable {
    let journalText: String
}

enum TravelAPI {
    // MARK: - companion SSE stream

    static func companionStream(
        placeName: String,
        folkloreSummaries: [String],
        companionType: String,
        message: String,
        history: [TravelChatMessage]
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let url = URL(string: Config.baseURL + "/travel/companion") else {
                    continuation.finish()
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                let historyItems = history.map { CompanionHistoryItem(role: $0.role, content: $0.content) }
                let body = CompanionChatRequest(
                    placeName: placeName,
                    folkloreSummaries: folkloreSummaries,
                    companionType: companionType,
                    message: message,
                    history: historyItems
                )
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                request.httpBody = try? encoder.encode(body)

                guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else {
                    continuation.finish()
                    return
                }

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    if let data = payload.data(using: .utf8),
                       let json = try? JSONDecoder().decode([String: String].self, from: data),
                       let text = json["text"] {
                        continuation.yield(text)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - journal generation

    static func generateJournal(session: TravelSession) async throws -> String {
        let logs = session.chatLogs.map { log in
            JournalChatLog(
                placeName: log.placeName,
                messages: log.messages.map { CompanionHistoryItem(role: $0.role, content: $0.content) }
            )
        }
        let body = JournalRequestBody(
            visitedPlaces: session.visitedPlaceNames,
            chatLogs: logs
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let url = URL(string: Config.baseURL + "/travel/journal") else {
            throw APIError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(JournalResponse.self, from: data)
        return result.journalText
    }
}
```

- [ ] **Step 2: Xcode 빌드 확인 (`⌘B`)**

- [ ] **Step 3: 커밋**

```bash
git add "ios/JejuFolklore/Sources/Services/TravelAPI.swift"
git commit -m "feat(ios): add TravelAPI with companion SSE stream and journal generation"
```

---

## Task 4: iOS — LocationService 30초 체류 조건 추가

**Files:**
- Modify: `ios/JejuFolklore/Sources/Services/LocationService.swift`

현재 `checkArrival`은 반경 진입 즉시 도착으로 처리한다. 오탐 방지를 위해 30초 이상 체류 시에만 도착 처리한다.

- [ ] **Step 1: LocationService.swift 수정**

기존 `private var visitedPlaceIDs: Set<String> = []` 아래에 dwell state 추가:

```swift
// 기존 코드에서 아래 두 줄을 추가한다
private var pendingArrivals: [String: Date] = [:]
private let dwellRequired: TimeInterval = 30
```

기존 `checkArrival` 함수 전체를 교체:

```swift
private func checkArrival(for location: CLLocation) {
    for place in activePlaces {
        let placeID = "\(place.name)-\(place.day)"
        guard !visitedPlaceIDs.contains(placeID) else { continue }

        let target = CLLocation(latitude: place.lat, longitude: place.lng)
        let distance = location.distance(from: target)

        if distance <= arrivalRadius {
            if let enteredAt = pendingArrivals[placeID] {
                // 반경 안에 충분히 머물렀으면 도착 처리
                if Date().timeIntervalSince(enteredAt) >= dwellRequired {
                    visitedPlaceIDs.insert(placeID)
                    pendingArrivals.removeValue(forKey: placeID)
                    onArrival?(place.name, place.folklorePins.first)
                }
            } else {
                // 처음 진입: 타임스탬프 기록
                pendingArrivals[placeID] = Date()
            }
        } else {
            // 반경 벗어나면 타이머 초기화
            pendingArrivals.removeValue(forKey: placeID)
        }
    }
}
```

`stopExploring()` 함수에 `pendingArrivals.removeAll()` 추가:

```swift
func stopExploring() {
    activePlaces = []
    pendingArrivals.removeAll()
    manager.allowsBackgroundLocationUpdates = false
    manager.stopUpdatingLocation()
}
```

- [ ] **Step 2: Xcode 빌드 확인 (`⌘B`)**

- [ ] **Step 3: 커밋**

```bash
git add "ios/JejuFolklore/Sources/Services/LocationService.swift"
git commit -m "feat(ios/location): add 30s dwell condition to prevent false arrival triggers"
```

---

## Task 5: iOS — ExploreViewModel 동행자 상태 추가

**Files:**
- Modify: `ios/JejuFolklore/Sources/ViewModels/ExploreViewModel.swift`

기존 `ExploreViewModel`을 확장해 동행자 채팅 흐름을 관리한다.

- [ ] **Step 1: ExploreViewModel.swift 전체 교체**

```swift
// ios/JejuFolklore/Sources/ViewModels/ExploreViewModel.swift
import Foundation
import UserNotifications

@MainActor
final class ExploreViewModel: ObservableObject {
    // 기존 필드
    @Published var visitedPlaceNames: Set<String> = []

    // 도착 오버레이
    @Published var arrivedPlace: CoursePlace?
    @Published var showArrivalOverlay = false

    // 동행자 채팅
    @Published var activeChatPlace: CoursePlace?
    @Published var showCompanionChat = false

    // 여행 일지
    @Published var journalText: String = ""
    @Published var isGeneratingJournal = false
    @Published var showJournal = false

    let course: Course
    let transport: String
    let companion: CompanionCharacter

    private var travelSession: TravelSession

    init(course: Course, transport: String, categoryScores: [String: Int]) {
        self.course = course
        self.transport = transport
        self.companion = CompanionCharacter.from(categoryScores: categoryScores)
        self.travelSession = TravelSession(courseId: course.id, companion: self.companion)
    }

    // MARK: - Explore lifecycle

    func startExploring() {
        requestNotificationPermission()
        LocationService.shared.requestAlwaysAuthorization()
        LocationService.shared.onArrival = { [weak self] placeName, pin in
            Task { @MainActor [weak self] in
                self?.handleArrival(placeName: placeName)
            }
        }
        LocationService.shared.startExploring(places: course.places, transport: transport)
    }

    func stopExploring() {
        LocationService.shared.stopExploring()
        LocationService.shared.onArrival = nil
        TravelStore.shared.save(travelSession)
    }

    // MARK: - Arrival handling

    private func handleArrival(placeName: String) {
        guard let place = course.places.first(where: { $0.name == placeName }) else { return }
        visitedPlaceNames.insert(placeName)
        travelSession.visitedPlaceNames.append(placeName)
        TravelStore.shared.save(travelSession)

        arrivedPlace = place
        showArrivalOverlay = true
        sendArrivalNotification(placeName: placeName)
    }

    func dismissArrivalOverlay() {
        showArrivalOverlay = false
    }

    func openCompanionChat(for place: CoursePlace) {
        showArrivalOverlay = false
        activeChatPlace = place
        showCompanionChat = true
    }

    // MARK: - Chat persistence

    func messages(for placeName: String) -> [TravelChatMessage] {
        travelSession.chatLogs.first(where: { $0.placeName == placeName })?.messages ?? []
    }

    func appendMessage(_ msg: TravelChatMessage, to placeName: String) {
        travelSession.appendMessage(msg, to: placeName)
        TravelStore.shared.save(travelSession)
        objectWillChange.send()
    }

    // MARK: - Journal generation

    func generateJournal() async {
        isGeneratingJournal = true
        do {
            journalText = try await TravelAPI.generateJournal(session: travelSession)
        } catch {
            journalText = "여행 일지를 생성하지 못했어요. 나중에 다시 시도해주세요."
        }
        isGeneratingJournal = false
        showJournal = true
    }

    // MARK: - Notification

    private func sendArrivalNotification(placeName: String) {
        let content = UNMutableNotificationContent()
        content.title = "설화 장소에 도착했습니다"
        content.body = "\(placeName) — \(companion.displayName)가 기다리고 있어요"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
```

- [ ] **Step 2: Xcode 빌드 확인 (`⌘B`)**

- [ ] **Step 3: 커밋**

```bash
git add "ios/JejuFolklore/Sources/ViewModels/ExploreViewModel.swift"
git commit -m "feat(ios/vm): expand ExploreViewModel with companion, arrival overlay, journal"
```

---

## Task 6: iOS — ArrivalOverlayView (전체화면 도착 오버레이)

**Files:**
- Create: `ios/JejuFolklore/Sources/Views/ArrivalOverlayView.swift`

"설화 장소에 도착했습니다" 전체화면 오버레이. 탭 1회로 동행자 채팅 진입, "나중에"로 닫기.

- [ ] **Step 1: ArrivalOverlayView.swift 생성**

```swift
// ios/JejuFolklore/Sources/Views/ArrivalOverlayView.swift
import SwiftUI

struct ArrivalOverlayView: View {
    let place: CoursePlace
    let companion: CompanionCharacter
    let onEnterChat: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // 동행자 이모지 + 이름
                VStack(spacing: 8) {
                    Text(companion.emoji)
                        .font(.system(size: 72))
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)

                    Text(companion.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.orange)
                        .opacity(appeared ? 1 : 0)
                }

                // 도착 메시지
                VStack(spacing: 8) {
                    Text("설화 장소에 도착했습니다")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(place.name)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)

                // 동행자 첫마디
                Text("\"\(companion.greeting)\"")
                    .font(.subheadline.italic())
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)

                // 버튼
                VStack(spacing: 12) {
                    Button(action: onEnterChat) {
                        Text("동행자와 대화하기")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: onDismiss) {
                        Text("나중에")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)
            }
            .padding(.vertical, 48)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

#Preview {
    let mockPlace = CoursePlace(name: "성산일출봉", lat: 33.4584, lng: 126.9426, day: 1, folklorePins: [])
    ArrivalOverlayView(
        place: mockPlace,
        companion: .dokkaebi,
        onEnterChat: {},
        onDismiss: {}
    )
}
```

- [ ] **Step 2: Xcode에서 Preview 확인**

Canvas에서 `ArrivalOverlayView` Preview를 열어 레이아웃 확인.

- [ ] **Step 3: 커밋**

```bash
git add "ios/JejuFolklore/Sources/Views/ArrivalOverlayView.swift"
git commit -m "feat(ios/view): add ArrivalOverlayView fullscreen arrival UX"
```

---

## Task 7: iOS — CompanionChatView (동행자 채팅 화면)

**Files:**
- Create: `ios/JejuFolklore/Sources/Views/CompanionChatView.swift`

SSE 스트리밍으로 동행자 응답을 받아 버블 형태로 표시. 첫 진입 시 `__GREETING__`을 전송해 동행자가 먼저 말을 건네게 한다.

- [ ] **Step 1: CompanionChatView.swift 생성**

```swift
// ios/JejuFolklore/Sources/Views/CompanionChatView.swift
import SwiftUI

struct CompanionChatView: View {
    let place: CoursePlace
    let companion: CompanionCharacter
    let vm: ExploreViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var messages: [TravelChatMessage] = []
    @State private var streamingText = ""
    @State private var isStreaming = false
    @FocusState private var isInputFocused: Bool

    private var folkloreSummaries: [String] {
        place.folklorePins.prefix(3).map { "\($0.title): \($0.summary)" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 동행자 헤더
                companionHeader

                Divider()

                // 채팅 목록
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg, companion: companion)
                                    .id(msg.id)
                            }
                            if isStreaming && !streamingText.isEmpty {
                                ChatBubble(
                                    message: TravelChatMessage(role: "assistant", content: streamingText),
                                    companion: companion
                                )
                                .id("streaming")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: streamingText) {
                        withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                    }
                }

                // 입력창
                inputBar
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .onAppear {
            messages = vm.messages(for: place.name)
            if messages.isEmpty { sendGreeting() }
        }
    }

    // MARK: - Companion Header

    private var companionHeader: some View {
        HStack(spacing: 12) {
            Text(companion.emoji)
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 2) {
                Text(companion.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(place.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("동행자에게 말을 건네보세요", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming ? .secondary : .orange)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1), alignment: .top)
    }

    // MARK: - Streaming

    private func sendGreeting() {
        Task { await stream(message: "__GREETING__", history: []) }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""

        let userMsg = TravelChatMessage(role: "user", content: text)
        messages.append(userMsg)
        vm.appendMessage(userMsg, to: place.name)

        Task { await stream(message: text, history: messages.dropLast()) }
    }

    private func stream(message: String, history: some Collection<TravelChatMessage>) async {
        isStreaming = true
        streamingText = ""

        let historyArray = Array(history)
        let stream = TravelAPI.companionStream(
            placeName: place.name,
            folkloreSummaries: folkloreSummaries,
            companionType: companion.rawValue,
            message: message,
            history: historyArray
        )

        for await chunk in stream {
            streamingText += chunk
        }

        if !streamingText.isEmpty {
            let assistantMsg = TravelChatMessage(role: "assistant", content: streamingText)
            messages.append(assistantMsg)
            vm.appendMessage(assistantMsg, to: place.name)
        }
        streamingText = ""
        isStreaming = false
    }
}

// MARK: - ChatBubble

private struct ChatBubble: View {
    let message: TravelChatMessage
    let companion: CompanionCharacter

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                Text(companion.emoji)
                    .font(.system(size: 24))
            }

            Text(message.content)
                .font(.body)
                .foregroundColor(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.orange : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isUser ? Color.clear : Color.orange.opacity(0.2), lineWidth: 1)
                )

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
```

- [ ] **Step 2: Xcode 빌드 확인 (`⌘B`)**

- [ ] **Step 3: 커밋**

```bash
git add "ios/JejuFolklore/Sources/Views/CompanionChatView.swift"
git commit -m "feat(ios/view): add CompanionChatView with SSE streaming and chat bubble UI"
```

---

## Task 8: iOS — TravelJournalView (여행 일지 화면)

**Files:**
- Create: `ios/JejuFolklore/Sources/Views/TravelJournalView.swift`

- [ ] **Step 1: TravelJournalView.swift 생성**

```swift
// ios/JejuFolklore/Sources/Views/TravelJournalView.swift
import SwiftUI

struct TravelJournalView: View {
    let journalText: String
    let visitedPlaces: [String]
    let companion: CompanionCharacter
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 헤더
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(companion.emoji) \(companion.displayName)와 함께한 여행")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)

                        Text("나의 제주 여행 일지")
                            .font(.title2.weight(.bold))

                        Text("방문: \(visitedPlaces.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Divider()
                        .padding(.horizontal, 20)

                    // 일지 본문
                    Text(journalText)
                        .font(.body)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("여행 일지")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Loading state

struct JournalLoadingView: View {
    let companion: CompanionCharacter

    var body: some View {
        VStack(spacing: 20) {
            Text(companion.emoji)
                .font(.system(size: 56))
            ProgressView()
                .scaleEffect(1.3)
            Text("\(companion.displayName)이(가) 여행을 정리하고 있어요...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
```

- [ ] **Step 2: Xcode 빌드 확인 (`⌘B`)**

- [ ] **Step 3: 커밋**

```bash
git add "ios/JejuFolklore/Sources/Views/TravelJournalView.swift"
git commit -m "feat(ios/view): add TravelJournalView and JournalLoadingView"
```

---

## Task 9: iOS — ExploreView 개선 및 CoursePreviewView 연결

**Files:**
- Modify: `ios/JejuFolklore/Sources/Views/ExploreView.swift`
- Modify: `ios/JejuFolklore/Sources/Views/CoursePreviewView.swift`

ExploreView에 도착 오버레이, 동행자 채팅, 여행 일지 흐름을 연결한다.
CoursePreviewView에서 categoryScores를 받아 ExploreView로 전달한다.

- [ ] **Step 1: ExploreView.swift 전체 교체**

```swift
// ios/JejuFolklore/Sources/Views/ExploreView.swift
import SwiftUI
import MapKit

struct ExploreView: View {
    let course: Course
    let transport: String
    let categoryScores: [String: Int]

    @StateObject private var vm: ExploreViewModel
    @StateObject private var location = LocationService.shared

    init(course: Course, transport: String, categoryScores: [String: Int]) {
        self.course = course
        self.transport = transport
        self.categoryScores = categoryScores
        _vm = StateObject(wrappedValue: ExploreViewModel(
            course: course,
            transport: transport,
            categoryScores: categoryScores
        ))
    }

    var body: some View {
        ZStack {
            exploreMap
                .ignoresSafeArea(edges: .top)

            // 도착 오버레이 (전체화면)
            if vm.showArrivalOverlay, let place = vm.arrivedPlace {
                ArrivalOverlayView(
                    place: place,
                    companion: vm.companion,
                    onEnterChat: { vm.openCompanionChat(for: place) },
                    onDismiss: { vm.dismissArrivalOverlay() }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            VStack {
                Spacer()
                statusBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.showArrivalOverlay)
        .navigationTitle("탐험 중")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("탐험 마치기") {
                    vm.stopExploring()
                    Task { await vm.generateJournal() }
                }
                .foregroundColor(.orange)
                .fontWeight(.semibold)
            }
        }
        .onAppear { vm.startExploring() }
        .onDisappear { vm.stopExploring() }
        .sheet(isPresented: $vm.showCompanionChat) {
            if let place = vm.activeChatPlace {
                CompanionChatView(place: place, companion: vm.companion, vm: vm)
            }
        }
        .sheet(isPresented: $vm.showJournal) {
            if vm.isGeneratingJournal {
                JournalLoadingView(companion: vm.companion)
            } else {
                TravelJournalView(
                    journalText: vm.journalText,
                    visitedPlaces: Array(vm.visitedPlaceNames),
                    companion: vm.companion,
                    onDone: { vm.showJournal = false }
                )
            }
        }
    }

    // MARK: - Map

    private var exploreMap: some View {
        let userCoord = location.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 33.3617, longitude: 126.5292)
        return Map(
            coordinateRegion: .constant(
                MKCoordinateRegion(
                    center: userCoord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            ),
            showsUserLocation: true,
            annotationItems: course.places.enumerated().map { IndexedPlace(index: $0.offset, place: $0.element) }
        ) { item in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.place.lat, longitude: item.place.lng)) {
                let isVisited = vm.visitedPlaceNames.contains(item.place.name)
                NumberedMarker(number: item.index + 1, hasfolklore: !item.place.folklorePins.isEmpty)
                    .opacity(isVisited ? 0.35 : 1.0)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("방문 \(vm.visitedPlaceNames.count) / \(course.places.count)곳")
                    .font(.headline)
                if let next = course.places.first(where: { !vm.visitedPlaceNames.contains($0.name) }) {
                    Text("다음: \(next.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("모든 장소를 방문했어요!")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            // 동행자 채팅 버튼 (현재 도착한 장소 기준)
            if let currentPlace = course.places.first(where: { vm.visitedPlaceNames.contains($0.name) }) {
                Button {
                    vm.openCompanionChat(for: currentPlace)
                } label: {
                    HStack(spacing: 4) {
                        Text(vm.companion.emoji)
                        Text("대화")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

- [ ] **Step 2: CoursePreviewView.swift — categoryScores 추가**

`CoursePreviewView`의 `let course: Course` 아래에 필드 추가:

```swift
let categoryScores: [String: Int]
```

`init` 파라미터에 `categoryScores: [String: Int] = [:]` 추가:

```swift
init(course: Course, hasNext: Bool = false, onNext: (() -> Void)? = nil, onReset: (() -> Void)? = nil, categoryScores: [String: Int] = [:]) {
    self.course = course
    self.hasNext = hasNext
    self.onNext = onNext
    self.onReset = onReset
    self.categoryScores = categoryScores
    _vm = StateObject(wrappedValue: CoursePreviewViewModel(course: course))
}
```

기존 `ExploreView(course: course, transport: "car")` 호출을 변경:

```swift
ExploreView(course: course, transport: "car", categoryScores: categoryScores)
```

- [ ] **Step 3: CourseListView.swift — categoryScores 전달**

`CourseListView`에서 `CoursePreviewView`를 생성하는 줄을 찾아 `categoryScores: vm.categoryScores`를 추가:

```swift
CoursePreviewView(
    course: course,
    hasNext: vm.hasNextCourse,
    onNext: { shouldLoadNext = true },
    onReset: { vm.reset() },
    categoryScores: vm.categoryScores
)
```

- [ ] **Step 4: Preview 수정**

`CoursePreviewView.swift` 하단의 `#Preview` 내 `CoursePreviewView(course: mockCourse)` 호출은 `categoryScores` 기본값이 `[:]`이므로 변경 불필요.

`ExploreView.swift`에 필요하면 `#Preview` 추가:

```swift
#Preview {
    let mockCourse = Course(
        id: "preview-001",
        title: "2박3일 제주 해안 여행",
        durationDays: 3,
        places: [
            CoursePlace(name: "성산일출봉", lat: 33.4584, lng: 126.9426, day: 1, folklorePins: []),
        ],
        estimatedMinutes: 120,
        sourceCourseId: "preview-001",
        narrative: ""
    )
    NavigationStack {
        ExploreView(
            course: mockCourse,
            transport: "car",
            categoryScores: ["초자연 존재담": 3, "생활민담·교훈담": 1]
        )
    }
}
```

- [ ] **Step 5: Xcode 전체 빌드 확인 (`⌘B`)**

에러가 없어야 한다. `ExploreView`, `CoursePreviewView`, `CourseListView` 모두 컴파일 통과.

- [ ] **Step 6: 시뮬레이터에서 골든 패스 수동 테스트**

1. 앱 실행
2. 취향 선택 → 코스 추천 → "담기" or 코스 확인
3. CoursePreviewView 하단 버튼에 탐험 시작 버튼이 보이지 않는 경우 — 이 PR에서는 ExploreView 진입을 CoursePreviewView에서 직접 "오늘 탐험 시작" 버튼으로 연결하도록 추가한다

`CoursePreviewView`의 `actionButtons`에 탐험 시작 버튼 추가:

```swift
// "내 일정으로 담기" 버튼 아래에
Button {
    navigateToExplore = true
} label: {
    Label("오늘 탐험 시작", systemImage: "location.fill")
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.orange)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
}
.padding(.top, 4)
```

`CoursePreviewView`에 `@State private var navigateToExplore = false` 추가 (이미 있음).

`navigationDestination(isPresented: $navigateToExplore)` 블록에 `ExploreView` 연결:

```swift
.navigationDestination(isPresented: $navigateToExplore) {
    ExploreView(course: course, transport: "car", categoryScores: categoryScores)
}
```

4. "오늘 탐험 시작" 탭 → ExploreView 진입 확인
5. (시뮬레이터에서는 GPS 미지원이므로 도착 오버레이는 실기기 또는 Custom Location으로 테스트)
6. 상단 "탐험 마치기" 버튼 → 로딩 → 여행 일지 표시 확인

- [ ] **Step 7: 커밋**

```bash
git add "ios/JejuFolklore/Sources/Views/ExploreView.swift" \
        "ios/JejuFolklore/Sources/Views/CoursePreviewView.swift" \
        "ios/JejuFolklore/Sources/Views/CourseListView.swift"
git commit -m "feat(ios): wire ExploreView with companion, arrival overlay, journal + connect from CoursePreviewView"
```

---

## Self-Review Checklist

### Spec Coverage

| 요구사항 | 대응 Task |
|---|---|
| GPS 지오펜스 100m + 30초 체류 도착 감지 | Task 4 (LocationService dwell) |
| 진동 + 효과음 | Task 6 (ArrivalOverlayView — iOS 기본 haptic은 시스템 알림으로 처리) |
| "설화 장소에 도착했습니다" 전체화면 오버레이 | Task 6 |
| 탭 1회 → AI 동행자 채팅 진입 | Task 6, Task 9 |
| 설화 취향 기반 동행자 캐릭터 자동 배정 | Task 2 (CompanionCharacter.from) |
| 동행자가 먼저 말을 건넴 (`__GREETING__`) | Task 7 (CompanionChatView.sendGreeting) |
| 채팅 내용 로컬 저장 | Task 2 (TravelStore), Task 5 (appendMessage) |
| 하루 탐험 마치기 → 방문 장소 요약 | Task 9 (statusBar 방문 수 표시) |
| 여행 일지 생성 (GPT 요약) | Task 1 (/travel/journal), Task 5 (generateJournal), Task 8 |
| categoryScores → 캐릭터 매핑 전달 | Task 9 (CourseListView → CoursePreviewView → ExploreView) |

### Placeholder Scan

없음 — 모든 단계에 실제 코드 포함.

### Type Consistency

- `CompanionCharacter.rawValue` (String) → `TravelAPI.companionStream(companionType:)` — 일치
- `TravelChatMessage` → `ExploreViewModel.appendMessage`, `CompanionChatView.messages` — 일치
- `TravelSession.chatLogs: [PlaceChatLog]` → `TravelAPI.generateJournal(session:)` — 일치
- `ExploreViewModel(course:transport:categoryScores:)` → `ExploreView.init` — 일치
