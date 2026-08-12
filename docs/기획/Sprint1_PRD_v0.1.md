# Sprint 1 PRD (v0.1)

> 🟢 **[실행 정본]** 4개 PRD 중 최신·새 방향에 가장 근접(5종 페르소나 폐기·성산일출봉 예시). 07-20 재정립(비트 명세+런타임 엔진, 관찰지점 경로, 반응형 대화, 성산 1개 집중)을 흡수해 **v0.2로 갱신 예정.** 방향 SSoT → [`방향성_재정립_2026-07-20.md`](방향성_재정립_2026-07-20.md).

**작성일:** 2026-07-14
**Sprint 기간:** 2026-07-21 ~ 2026-08-17 (4주)
**상태:** 초안 (7/17 KAIST 발표 후 v0.2 업데이트 예정)
**목표 산출물:** 쌍방향 도슨트 v0.2 · TestFlight 배포 · W1 Retention 측정 시작
**연관 문서:**
- [방향성_재정립_2026-07-14.md](../legacy/방향성_재정립_2026-07-14.md)
- [Sprint1_콘텐츠_파이프라인.md](Sprint1_콘텐츠_파이프라인.md)
- [공공데이터.md](공공데이터.md)
- [PRD-travel-companion.md](../legacy/PRD-travel-companion.md) (기존 부분 PRD · 흡수됨)

---

## 0. Sprint 1 미션 (한 줄)

> 제주 관광지 30개소 이상에 대해, GPS 도착 감지 시 **전문 가이드 톤 내레이션 + 텍스트 인터럽트 Q&A**가 작동하는 iOS 앱을 4주 안에 TestFlight로 배포하고 W1 Retention 측정을 시작한다.

---

## 1. 스코프

### In (반드시 하는 것)

**콘텐츠**
- 5개 공공 데이터 소스 통합 파이프라인 (제주학·nculture·도청·문화재청·비짓제주)
- 관광지 인벤토리 1,047개소 (도청 데이터)
- 정제 스토리 30~90개소 (LLM 리라이팅 완료)
- 라이선스 크레딧 UI 완비 (About 페이지)

**iOS 앱**
- GPS 도착 자동 감지 (CoreLocation)
- 관광지 매칭 → 내레이션 스트리밍 재생
- 텍스트 인터럽트 Q&A (음성 인식은 v0.3 유보)
- 관광지 이미지 표시
- Firebase Analytics 이벤트 훅 (W1 Retention 측정)
- 라이선스 크레딧 화면

**백엔드**
- FastAPI 서버 (Cloudflare/AWS 배포)
- PostgreSQL + pgvector
- `/spots/near` `/story/:id` `/verify/:id` `/qa` 엔드포인트
- 관광지 이미지 CDN 캐싱 (S3 or Cloudflare R2)
- 사용자 인증 (Firebase Auth · 익명 로그인 우선)

**측정**
- Firebase Analytics 이벤트 정의 (`session_start`, `story_played`, `qa_asked`, `session_end`)
- W1 Retention 대시보드 (Firebase Console)

### Out (Sprint 1에서 안 하는 것)

- 음성 인식 인터럽트 (v0.3 · Sprint 2 후반)
- 게임화 레이어 (Sprint 2)
- 결제 시스템 (유료화 트리거 도달 후)
- 5종 페르소나 (폐기 · 1명 가이드로 통합)
- 민화 이미지 생성 (Sprint 2 이후)
- 다국어 (Sprint 3+)
- 여행 계획 세우기 기능 확장 (기존 v1 그대로 유지)
- 소셜 공유 (Sprint 2+)
- 오프라인 모드 (Sprint 3+)

---

## 2. 유지 · 폐기 · 재배치 매트릭스 (v1 → v0.2 전환)

기존 v1의 각 요소를 어떻게 처리할지:

| v1 요소 | Sprint 1 처리 | 이유 |
|---|---|---|
| 5종 페르소나 동행자 | **폐기** | 익준님 스스로 안 믿는 기능 · 1명의 유능한 가이드로 통합 |
| GPS 도착 자동 감지 | **유지 + 개선** | 핵심 UX · 반경·정확도 튜닝 |
| RAG 기반 대화 | **재설계** | 내레이션 스트리밍 + 인터럽트 Q&A 이중 흐름 |
| 검증된 코스 추천 (결정론) | **유지** | 무료 layer · 여행 계획 훅 |
| 여행 계획 · 장소 정보 | **유지 + 무료 layer로 재배치** | 결제 게이트 없이 유입 훅 |
| 대화 = 일지 | **유지, 우선순위 낮춤** | Sprint 1 스코프 밖. Sprint 2+ |
| 민화 이미지 렌더링 | **유지, 우선순위 낮춤** | Sprint 2+ |
| 설화·민담 데이터 | **유지 + 확장** | Layer 2 스토리 원자재의 일부. 지역N문화·제주학연구센터 데이터 추가 |
| 5종 페르소나 대본 데이터 | **재활용** | 톤 통일 후 신규 소스 데이터와 병합 |

---

## 3. 사용자 스토리 (핵심 5개)

### US-1. 제주 도착 후 첫 관광지에서 앱 사용

> **As a** 제주 여행자
> **I want** 성산일출봉에 도착했을 때 앱을 열면 자동으로 이 장소에 대한 이야기가 시작되기를
> **So that** 유료 가이드 없이도 이곳의 역사와 전설을 알 수 있다

**Acceptance:**
- 앱을 열고 5초 안에 현재 위치 관광지 매칭
- 매칭된 관광지 이름 · 대표 이미지 · "이야기 듣기" 버튼 표시
- 버튼 탭 후 3초 안에 내레이션 시작

### US-2. 내레이션 중 궁금한 것 인터럽트해서 질문

> **As a** 도슨트 앱 사용자
> **I want** 내레이션 재생 중 궁금한 점이 생기면 텍스트 입력으로 질문할 수 있기를
> **So that** 일방향 오디오북과 다른 대화 경험을 얻는다

**Acceptance:**
- 재생 중 "질문하기" 버튼 상시 노출
- 버튼 탭 시 내레이션 일시정지 · 텍스트 입력창 표시
- 질문 제출 후 5초 내 답변 스트리밍 시작
- 답변 종료 후 "이어서 듣기" 버튼으로 내레이션 재개

### US-3. 관광지 매칭 안 되는 위치에서 근처 추천 받기

> **As a** 관광지 아닌 곳(예: 숙소)에 있는 사용자
> **I want** 근처 3~5km 내 관광지 리스트를 볼 수 있기를
> **So that** 어디로 갈지 결정할 수 있다

**Acceptance:**
- 현재 위치에서 관광지 매칭 실패 시 자동으로 "근처 관광지" 화면 전환
- 거리·카테고리·대표 이미지·간단 소개 표시
- 리스트에서 관광지 선택 시 그 관광지 상세 화면으로

### US-4. 이야기 출처 확인

> **As a** 신뢰할 만한 정보를 원하는 사용자
> **I want** 이야기의 출처를 명확히 확인할 수 있기를
> **So that** 앱이 창작한 이야기인지 공식 자료인지 구분할 수 있다

**Acceptance:**
- 각 이야기 하단에 소스 표시 (예: "제주학연구센터", "국가유산청")
- About 페이지에 전체 라이선스 크레딧
- 사실 근거(문화재청 데이터) 있는 부분은 별도 아이콘 표시

### US-5. 익명으로 즉시 사용 시작

> **As a** 회원가입이 귀찮은 사용자
> **I want** 로그인 없이도 앱의 대부분 기능을 쓸 수 있기를
> **So that** 첫 진입 마찰을 최소화한다

**Acceptance:**
- 앱 첫 실행 시 Firebase Anonymous Auth로 자동 세션 생성
- 세션은 앱 재실행 시 유지 (UUID 로컬 저장)
- 명시적 회원가입은 나중 (Sprint 2+ 결제 도입 시)

---

## 4. 기술 아키텍처

### 4.1 시스템 다이어그램

```
                     ┌────────────────────────────────────┐
                     │  iOS Client (Swift · SwiftUI)      │
                     │  · CoreLocation (GPS)              │
                     │  · AVFoundation (내레이션 재생)    │
                     │  · Firebase Analytics              │
                     │  · Firebase Auth (Anonymous)       │
                     └────────────┬───────────────────────┘
                                  │
                                  │ HTTPS · JSON
                                  │
                                  ▼
                     ┌────────────────────────────────────┐
                     │  FastAPI (Python 3.12)             │
                     │  · /spots/near                     │
                     │  · /story/:id                      │
                     │  · /qa (SSE 스트리밍)              │
                     │  · /verify/:id                     │
                     │  · JWT 검증 (Firebase Admin SDK)   │
                     └────────────┬───────────────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
     ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
     │ PostgreSQL     │  │ pgvector       │  │ LLM API        │
     │ · spots        │  │ · story chunks │  │ (Claude/OpenAI)│
     │ · stories      │  │ · embeddings   │  │                │
     │ · facts        │  │                │  │                │
     │ · media        │  │                │  │                │
     └────────────────┘  └────────────────┘  └────────────────┘

     ┌────────────────┐
     │ CDN (S3/R2)    │  ← 이미지·정적 자산
     │ · WebP images  │
     │ · audio TTS    │
     └────────────────┘
```

### 4.2 iOS 클라이언트 구조

```
App/
├── Features/
│   ├── LocationDetection/     ← GPS · 관광지 매칭
│   ├── StoryPlayer/           ← 내레이션 재생 + 인터럽트
│   ├── QAOverlay/             ← 질문 입력 · 답변 표시
│   ├── NearbySpots/           ← 매칭 실패 시 근처 리스트
│   └── About/                 ← 라이선스 크레딧
├── Services/
│   ├── APIClient/             ← FastAPI 호출
│   ├── LocationService/       ← CoreLocation 래퍼
│   ├── AnalyticsService/      ← Firebase Analytics
│   └── AudioService/          ← AVPlayer 스트리밍
├── Models/
│   ├── Spot.swift
│   ├── Story.swift
│   └── QAMessage.swift
└── Shared/
    ├── DesignSystem/
    └── Utilities/
```

### 4.3 백엔드 엔드포인트

**`GET /spots/near`**
```json
Request: ?lat=33.4586&lng=126.9426&radius=5000
Response: {
  "matched_spot": {          // 반경 300m 이내 있으면
    "id": "spot_abc",
    "name": "성산일출봉",
    "category": "heritage",
    "image_url": "https://cdn.../abc.webp",
    "distance_m": 45
  },
  "nearby_spots": [          // 매칭 실패 시만 채움
    { "id": "...", "name": "...", "distance_m": 2340 }
  ]
}
```

**`GET /story/{spot_id}`**
```json
Response: {
  "spot_id": "spot_abc",
  "story_id": "story_xyz",
  "title": "일출봉 그늘 아래 숨은 이야기",
  "body_narration": "...(1000자)...",
  "source_credit": "제주학연구센터 (공공누리 제1유형)",
  "audio_url": null,         // v0.3에서 TTS 추가 예정
  "estimated_duration_sec": 180,
  "grounding_facts": [
    { "text": "...", "citation": "국가유산청 (2026-02)" }
  ]
}
```

**`POST /qa`** (Server-Sent Events)
```json
Request: {
  "spot_id": "spot_abc",
  "story_id": "story_xyz",
  "question": "여기서 왜 일출을 본다고 해요?",
  "session_id": "sess_123"
}
Response (SSE stream):
  data: {"delta": "일출봉이 "}
  data: {"delta": "일출 명소로 "}
  ...
  data: {"done": true, "citation": "국가유산청"}
```

**`GET /verify/{spot_id}`**
```json
Response: {
  "facts": [
    { "text": "성산일출봉은 2007년 유네스코 세계자연유산에 등재되었다.",
      "citation": "국가유산청 국가유산검색 (2026-02)" }
  ]
}
```

### 4.4 데이터 모델 (PostgreSQL)

[Sprint1_콘텐츠_파이프라인.md](Sprint1_콘텐츠_파이프라인.md#1-데이터-레이어-4단-구조) 참조. Layer 1~4 스키마 동일.

추가 테이블:
- `users` (Firebase UID · 익명 세션 UUID · 첫 접속·마지막 접속)
- `sessions` (session_id · user_id · start·end · spot_ids listened · qa_count)
- `qa_history` (session_id · question · answer · citations · latency_ms)

---

## 5. RAG 파이프라인 (v0.2 재설계)

### 5.1 이중 흐름 (Narration + Interrupt Q&A)

**Narration Stream (내레이션):**
- Pre-generated. story.body_narration을 그대로 스트리밍
- TTS 없이 텍스트 스크롤 방식으로 시작 (Sprint 1)
- Sprint 2에서 TTS 추가 (Google Cloud TTS 또는 ElevenLabs)

**Interrupt Q&A Flow:**
```
1. 사용자 질문 입력
2. 내레이션 pause · 세션 상태에 "in_qa" 저장
3. 서버 /qa 호출
   a. 질문 임베딩 (bge-m3)
   b. 해당 spot의 story chunks에서 top-3 유사도 검색
   c. Layer 3 grounding facts join
   d. System prompt 구성:
      · 캐릭터: "제주 관광 전문 가이드"
      · Context: story chunks + grounding facts (인용 필수)
      · Constraint: "제공된 컨텍스트 안에서만 답변. 없으면 '그건 저도 잘 모르겠어요' 응답"
   e. LLM 응답 스트리밍 (SSE)
4. 답변 완료 후 "이어서 듣기" 버튼 노출
5. 탭 시 내레이션 재개 (마지막 재생 지점부터)
```

### 5.2 System Prompt (Q&A용 v1.0)

```
당신은 제주 관광 전문 가이드 "탐라"입니다. 사용자가 지금 서 있는 관광지에
대해 방금 이야기를 들려주고 있었는데, 사용자가 질문을 던졌습니다.

규칙:
1. 아래 [현재 관광지 컨텍스트]와 [사실 근거]에 있는 내용으로만 답변
2. 컨텍스트에 없는 사실은 절대 창작하지 말 것 ("잘 모르겠어요" 응답)
3. 답변은 3~5문장 이내 (내레이션 흐름 끊지 않기)
4. 사실 근거가 있는 부분은 자연스럽게 인용 ("국가유산청 자료에 따르면...")
5. 사용자가 답을 얻고 이야기를 다시 듣고 싶어할 만한 마무리

[현재 관광지]: {spot_name} ({category})
[현재 관광지 컨텍스트]:
{story_chunks}

[사실 근거]:
{grounding_facts}

[사용자 질문]: {question}

답변:
```

### 5.3 응답 품질 QA (Sprint 1 내부 검수)

30개 관광지 × 각 5개 예상 질문 = 150개 Q&A 표본 수동 검수:
- [ ] 사실 오류 없음 (grounding facts 대조)
- [ ] 답변 길이 3~5문장
- [ ] 톤이 "전문 가이드"에 맞음
- [ ] 인용이 자연스러움
- [ ] "잘 모르겠어요" 발동 케이스도 정상 작동

**목표 정확도:** 95%+ (표본 150개 중 143개 이상 통과)

---

## 6. 지표 & 분석

### 6.1 핵심 지표 (Sprint 1 종료 시 리포트)

| 지표 | 정의 | 목표 |
|---|---|---|
| **W1 Retention** | 첫 세션 이후 7일 내 재접속 % | 측정 시작 (수치는 Sprint 2에 나옴) |
| **평균 세션 시간** | 앱 실행 후 종료까지 | 8분+ |
| **세션당 스토리 재생 수** | 한 세션에서 몇 개 관광지 청취 | 2개+ |
| **Q&A 발생률** | 스토리 재생 중 질문한 세션 % | 30%+ |
| **매칭 성공률** | GPS 트리거 시 관광지 매칭 성공 % | 70%+ (관광지 안에서만 트리거 예상) |
| **QA 응답 정확도** | 표본 수동 검수 | 95%+ |

### 6.2 Firebase Analytics 이벤트 정의

| 이벤트 | 파라미터 | 트리거 |
|---|---|---|
| `session_start` | `user_id`, `start_lat`, `start_lng` | 앱 실행 |
| `spot_matched` | `spot_id`, `spot_name`, `distance_m` | GPS 매칭 성공 |
| `story_played` | `spot_id`, `story_id`, `duration_played_sec` | 스토리 재생 시작 |
| `story_completed` | `spot_id`, `duration_played_sec` | 스토리 끝까지 재생 |
| `qa_asked` | `spot_id`, `question_length`, `latency_ms` | 질문 제출 |
| `qa_answered` | `spot_id`, `answer_length`, `citation_count` | 답변 완료 |
| `session_end` | `duration_sec`, `spots_visited`, `qa_count` | 앱 백그라운드 5분+ |

### 6.3 대시보드 위치

Firebase Console → Analytics → Custom Dashboard
- 일별 신규 사용자 · W1 코호트
- 세션 시간 분포
- 관광지별 인기도 (재생 횟수)
- Q&A 발생률 · 평균 지연

---

## 7. QA · 릴리스 기준

### Sprint 1 종료 게이트 (모두 통과해야 TestFlight 승인)

- [ ] iOS 앱 크래시 프리 (내부 dogfood 8시간+ 세션 무크래시)
- [ ] TestFlight 심사 통과
- [ ] 30개소 이상 콘텐츠 정제 완료
- [ ] 매칭 성공률 70%+ (관광지 실측)
- [ ] Q&A 응답 정확도 95%+ (150개 표본)
- [ ] Firebase Analytics 이벤트 정상 수집 (24시간+ 데이터)
- [ ] 라이선스 크레딧 화면 완비
- [ ] 서버 응답 P95 < 3초 (스토리 조회) · < 5초 (Q&A 첫 델타)

### 사용자 인수 시나리오 (End-to-End Test)

- [ ] 성산일출봉 좌표에서 앱 실행 → 5초 내 매칭 → 스토리 재생 → 인터럽트 질문 → 답변 → 재개 → 세션 종료 → Firebase 이벤트 6개 이상 수집 확인

---

## 8. 리스크 · 대응

| 리스크 | 대응 |
|---|---|
| TestFlight 심사 지연 | Week 3 초 빌드 제출 · 심사 기간 5~7일 감안 |
| 비짓제주 API 승인 지연 | Week 1에 신청 · 대체 이미지 (Unsplash CC0) 준비 |
| LLM 비용 폭증 | Sprint 1은 30개 표본 정제만 · 프로덕션은 캐시 우선 |
| pgvector 성능 (초기엔 문제 없음) | Sprint 3+ Qdrant 검토 |
| GPS 배터리 소모 | 백그라운드 위치 정확도 낮게 · 앱 활성 시만 고정확도 |
| 매칭 실패율 높음 | Week 2 종료 후 반경 튜닝 · 실측 데이터 기반 조정 |
| Q&A 응답이 그럴싸하지만 틀림 (Hallucination) | Grounding facts 강제 인용 · "잘 모르겠어요" 응답 유도 |
| 4주 안에 30개소 못 채움 | 최소 15개소 (성산일출봉·한라산·만장굴·주상절리 등 유명지) 우선 · 롱테일 Sprint 2 이월 |

---

## 9. 의존성 · 준비 사항

### 즉시 (이번 주 안에)

- [x] 오디 API 활용신청 (7/14 완료)
- [ ] 비짓제주 API 활용신청 (7/17 이전)
- [ ] 문화재청 API 인증키 발급
- [ ] Firebase 프로젝트 생성 · iOS 앱 등록 · GoogleService-Info.plist
- [ ] OpenAI/Anthropic API 키 확보
- [ ] PostgreSQL 배포 (Supabase 또는 자체 호스팅)
- [ ] pgvector 확장 활성화
- [ ] Cloudflare R2 or AWS S3 버킷 생성 (이미지 CDN)
- [ ] TestFlight 앱 등록 (Apple Developer 계정 확인)

### Week 1 착수 시점

- [ ] 애플 개발자 계정 유효 확인
- [ ] Xcode 최신 버전
- [ ] Swift 5.10+ · SwiftUI · iOS 17+ 타겟

---

## 10. Sprint 1 이후 (Sprint 2 시드)

Sprint 1이 성공하면 Sprint 2에서 착수:
- 게임화 레이어 (미션·퀘스트·수집)
- TTS 음성 내레이션 (텍스트 → 음성)
- 음성 인식 인터럽트
- 유료화 트리거 도달 시 결제 시스템 (인앱결제)
- 콘텐츠 커버리지 60~90개소로 확장
- B2B/B2G 콜드 아웃리치 시작 (제주도청 · 관광공사)

---

## 11. 결정 대기 항목 (익준님 확인 필요)

이 PRD를 v0.2로 확정하기 전에 결정해야 할 것들:

- [ ] **LLM 벤더 선택:** Claude (Anthropic) vs OpenAI · 비용·품질·지연 비교 후 결정
- [ ] **PostgreSQL 호스팅:** Supabase (관리형) vs 자체 서버
- [ ] **CDN 벤더:** Cloudflare R2 (저렴) vs AWS S3 (표준)
- [ ] **User Auth 정책:** Anonymous만 vs Apple ID 옵션 병행
- [ ] **관광지 매칭 반경:** 300m · 500m · 1km 중 어느 것부터 시작 (Week 1 실측 후 조정 가능)
- [ ] **첫 Sprint 1 배포 지역:** 제주 전역 vs 제주 동측(성산·우도·섭지) 집중 (콘텐츠 확보 속도에 따라)
- [ ] **Q&A 응답 언어 정책:** 사용자 톤 따라가기 vs 항상 존댓말 · 격식

---

## 12. 발표·심사 대비 매핑

이 PRD가 KAIST 발표에서 어떻게 활용되는가:

- **금요일 5분 발표** — 슬라이드 3 (BM) + 슬라이드 4 (로드맵)에 이 PRD의 스코프 · 릴리스 기준 요약 사용
- **7/17 1페이지** — 이 PRD의 섹션 1 (스코프) + 섹션 6 (지표) 압축 인용
- **다음 주 발표 (7/22 예상)** — 이 PRD의 v0.2 반영 후 진척 보고
- **9월 해커톤** — Sprint 1 종료 데이터를 이 PRD 지표 매트릭스 기반으로 리포트
- **10/29 IR Day** — 이 PRD의 지표 실측치 vs 목표치 비교 · 3층 BM 진척
