# 백로그 — 제주 설화 탐험

**우선순위 기준: 졸업 발표 시연 10단계 플로우 완성**
시연 실패 조건(500 에러, 빈 화면 10초, 동행자 무음, 일지 실패)을 먼저 막는다.

---

## 🔴 CRITICAL — 시연 블로커

| # | 항목 | 담당 | 세부 내용 |
|---|------|------|-----------|
| C1 | `/course/detail` 근본 원인 해결 | 백엔드 | response_model 제거로 임시 핫픽스됨. Pydantic v2 ResponseValidationError 원인 파악 후 response_model 복원 |
| C2 | ExploreView.swift 완전 검증 | iOS | 세션 시작 시 지도 로딩, 장소 카드, "다음 장소 도착" 버튼 동작 E2E 확인 |
| C3 | 동행자 첫 인사 자동 전송 검증 | iOS + 백엔드 | 장소 도착 시 companion greeting 자동 발송 → CompanionChatView 오버레이 등장 확인 |
| C4 | 시연 E2E 플로우 전체 실행 | QA | 취향 선택 → 코스 추천 → 탐험 시작 → 장소 도착 2회 → 동행자 채팅 → 일지 생성 |

---

## 🟠 HIGH — 완성도 직결

| # | 항목 | 담당 | 세부 내용 |
|---|------|------|-----------|
| H1 | 코스 추천 로딩 UX | iOS | TasteDiscoveryView → CourseListView 전환 시 빈 화면 대신 ProgressView + 문구 표시 |
| H2 | 페르소나 수동 선택 UI | iOS | CompanionCharacter 5개를 선택 가능한 카드 UI. 자동 배정 위에 "바꾸기" 옵션 |
| H3 | 설화 없는 장소 도착 처리 | iOS + 백엔드 | folklore_pins 빈 배열일 때 동행자가 fallback 인사 + 장소 설명으로 대체 |
| H4 | 채팅 UI 폴리시 | iOS | 페르소나별 버블 색상, 배경색. 마을 할망=주황, 심방=보라, 해녀=파랑, 도깨비=초록, 도체비=회색 |

---

## 🟡 MEDIUM — 발표 인상 강화

| # | 항목 | 담당 | 세부 내용 |
|---|------|------|-----------|
| M1 | 일지 SNS 공유 카드 | iOS | JournalView에 "공유하기" 버튼 → UIActivityViewController로 이미지 카드 공유 |
| M2 | 동행자 채팅 페르소나 색상 | iOS | H4와 연계. 오버레이 배경색도 페르소나별 차별화 |
| M3 | Day 요약 화면 개선 | iOS | 방문 장소 리스트 + 들은 설화 수 + 걸은 거리 집계 표시 |

---

## 🟢 LOW — 여유 있으면

| # | 항목 | 담당 | 세부 내용 |
|---|------|------|-----------|
| L1 | 실기기 GPS 테스트 | QA | 제주 현장 또는 Xcode Simulate Location으로 실제 geofence 트리거 검증 |
| L2 | 오프라인 캐시 | iOS | 코스 데이터 로컬 저장, 네트워크 없을 때 이전 코스 복구 |
| L3 | 설화 핀 필터 | iOS | FolkloreDetailView 진입 전 legend/oral 필터 토글 |

---

## 완료 항목 (참고용)

- ✅ 취향 선택 UI
- ✅ AI 코스 추천 (list + detail 핫픽스 포함)
- ✅ 설화 핀 매핑
- ✅ GPS 도착 감지 + 시뮬레이터 버튼
- ✅ AI 동행자 채팅 5개 페르소나
- ✅ 카테고리 → 페르소나 자동 배정
- ✅ 설화 핀 상세 + TTS (stop 포함)
- ✅ Day 요약 + 일지 생성
- ✅ 세션 복구
- ✅ 지도 이동 경로 점선
