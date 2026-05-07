# 백로그 — 제주 설화 탐험

**우선순위 기준: 졸업 발표 시연 10단계 플로우 완성**
시연 실패 조건(500 에러, 빈 화면 10초, 동행자 무음, 일지 실패)을 먼저 막는다.

---

## 🔴 CRITICAL — 시연 블로커

| # | 항목 | 담당 | 세부 내용 |
|---|------|------|-----------|
| ✅ C1 | `/course/detail` 근본 원인 해결 | 백엔드 | NULL lat/lng 가드 추가, response_model=Course 복원 완료 |
| ✅ C2 | ExploreView.swift 완전 검증 | iOS | 세션 복원 시 재도착 방지 로직 추가, sheet race condition 수정 완료 |
| ✅ C3 | 동행자 첫 인사 자동 전송 검증 | iOS + 백엔드 | __GREETING__ 메시지로 첫 인사 자동 전송 구현 확인, 정상 동작 |
| ✅ C4 | 시연 E2E 플로우 전체 실행 | QA | 6/6 PASS. /course/detail 200, 동행자 채팅 사투리 확인, 일지 400자 생성 |

---

## 🟠 HIGH — 완성도 직결

| # | 항목 | 담당 | 세부 내용 |
|---|------|------|-----------|
| ✅ H1 | 코스 추천 로딩 UX | iOS | CourseListView에 ProgressView + "AI가 코스를 추천하고 있어요..." 표시 완료 |
| ✅ H2 | 페르소나 수동 선택 UI | iOS | CoursePreviewView에 자동 배정 표시 + "바꾸기" sheet 구현 완료 |
| ✅ H3 | 설화 없는 장소 도착 처리 | iOS + 백엔드 | has_folklore 분기로 프롬프트 분리, 설화 없을 때 제주 분위기 대화로 fallback |
| ✅ H4 | 채팅 UI 폴리시 | iOS | themeColor/bubbleColor computed property 추가, AI 버블·헤더·전송 버튼에 반영 |

---

## 🟡 MEDIUM — 발표 인상 강화

| # | 항목 | 담당 | 세부 내용 |
|---|------|------|-----------|
| ✅ M1 | 일지 SNS 공유 카드 | iOS | UIActivityViewController 공유 시트 구현 (동행자 정보 + 방문지 + 일지 전문) |
| ✅ M2 | 동행자 채팅 페르소나 색상 | iOS | H4에서 완료 — themeColor/bubbleColor 적용 |
| ✅ M3 | Day 요약 화면 개선 | iOS | 동행자 표시 + StatBadge (N곳 방문, N개 설화) 추가 |

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
