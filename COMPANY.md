# 제주 설화 탐험 — 오케스트레이터 브리핑

## 서비스 한 줄 정의
제주 설화 데이터 기반 여행 앱. **여행 계획 → 여행 중 → 여행 후** 전 구간을 책임진다.
사용자가 제주 설화 장소에 도착하면 AI 동행자가 먼저 말을 걸고, 여행이 끝나면 대화가 자동으로 일지가 된다.

## 팀
- 조익준 (개발자/PM, 1인 팀) — 방향 결정, 최종 승인
- 오케스트레이터 (Opus 4.7) — 상태 판단, 작업 지시, 결과 리뷰
- 백엔드 에이전트 (Sonnet) — FastAPI, 프롬프트, DB
- iOS 에이전트 (Sonnet) — Swift, SwiftUI
- QA 에이전트 (Sonnet) — 버그 탐지, 흐름 검증
- 서기 에이전트 (Sonnet) — 미팅 노트 업데이트

---

## 졸업 발표 시연 플로우 (이게 곧 완성 기준)

심사위원 앞에서 아래를 끊김 없이 보여줄 수 있어야 한다:

```
1. 취향 선택 (설화 카테고리 + 지역 + 일수)
2. AI 코스 추천 수신 (10초 이내)
3. 코스 미리보기 → 탐험 시작
4. 지도 화면 (이동 경로 점선, 다음 장소 카드)
5. [시뮬레이터] "다음 장소 도착" 버튼 → GPS 도착 시뮬레이션
6. AI 동행자 오버레이 등장 → 탭 1회 → 채팅
7. 채팅에서 설화 이야기 2~3턴 (페르소나 말투 시연)
8. 장소 이동 반복 (최소 2곳)
9. "탐험 마치기" → Day 요약 → 일지 생성 버튼
10. 개인화된 여행 일지 출력
```

**시연 실패 조건 (절대 피해야 하는 것):**
- 500 에러
- 빈 화면 10초 이상
- 동행자가 아무 말 안 함
- 일지 생성 실패

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| iOS | Swift 6, SwiftUI, CoreLocation, AVFoundation |
| 지도 | Google Maps SDK |
| 백엔드 | FastAPI, LangChain, GPT-4o |
| DB | SQLite (place_folklore_mapping), ChromaDB (벡터) |
| 개발 환경 | Mac, Xcode, uvicorn --reload |

---

## 현재 완성도 (2026-05-07 기준)

### ✅ 완료
- 취향 선택 UI (TasteDiscoveryView)
- AI 코스 추천 (course_list_agent + course_detail_agent)
- 설화 핀 매핑 (place_folklore_mapping)
- GPS 도착 감지 (CLCircularRegion + 시뮬레이터 디버그 버튼)
- AI 동행자 채팅 (/travel/companion, CompanionChatView)
- 5개 페르소나 (마을 할망, 당신·심방, 영등신·해녀 선배, 도깨비, 도체비)
- 카테고리 → 페르소나 자동 배정 (from(categoryScores:))
- 설화 핀 상세 + TTS (FolkloreDetailView, TTS stop 포함)
- Day 요약 (DaySummaryView)
- 여행 일지 생성 (/travel/journal)
- 세션 복구 (SessionRestoreView)
- 지도 이동 경로 점선

### ⚠️ 불안정 / 부분 완성
- /course/detail: response_model 제거로 핫픽스됨, 근본 원인 미해결
- ExploreView.swift: 세션 시작 시 unstaged 상태였음, 완전 검증 필요
- 동행자 첫 인사: greeting 자동 전송 여부 미검증

### ❌ 미완성
- 페르소나 수동 선택 UI (현재 자동 배정만)
- 설화 없는 장소 도착 시 처리 로직 검증
- 일지 SNS 공유 카드
- 채팅 UI 폴리시 (페르소나별 색상, 말풍선 디자인)
- 코스 추천 로딩 UX (현재 빈 화면)

---

## 핵심 제약
- 1인 개발, 졸업 발표까지 시간 제한 → YAGNI 원칙 철저히
- 설화 데이터는 제주도 내 매핑된 장소에만 존재
- 실기기 GPS 테스트는 현장 또는 시뮬레이션으로만 가능
- iOS 빌드는 `xcodegen generate` 후 Xcode에서 직접 실행
