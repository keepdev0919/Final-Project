
## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health

## 오케스트레이션 모드

사용자가 "시작해"라고 하면 아래 순서로 진행한다:

1. COMPANY.md를 읽어 현재 완성도와 시연 플로우를 확인한다
2. BACKLOG.md를 읽어 우선순위를 파악한다
3. CRITICAL 항목부터 순서대로 작업한다
4. 각 작업은 Agent 툴로 서브에이전트에게 위임한다:
   - 백엔드 코드 작업 → subagent_type: "Backend Architect"
   - iOS/Swift 작업 → subagent_type: "Mobile App Builder"
   - QA/검증 → subagent_type: "API Tester"
   - 미팅 노트 기록 → subagent_type: "general-purpose"
5. 작업 완료 후 BACKLOG.md 해당 항목을 ✅로 업데이트한다
6. docs/미팅/YYYY-MM-DD.md에 오늘 작업 내용을 기록한다 (서기 에이전트 위임)

**판단 기준**: 졸업 발표 10단계 시연 플로우를 끊김 없이 실행할 수 있는가.

---

## 프로젝트 컨텍스트 — 졸업 + 공모전 동시 진행

이 프로젝트(**탐라담**, 가칭 — 제주 설화 기반 AI 여행 가이드 앱)는 두 가지 목표를 동시에 갖는다:

1. **경희대 컴공 졸업프로젝트 시연** (졸업 발표일 임박)
2. **2026 관광데이터 활용 공모전 (웹·앱 개발 부문)** — 예비심사 합격, 최종 심사 2026-10월
   - 자세한 일정·시상규모·전략: `docs/기획/공모전-2026-tourapi.md`

### 핵심 전략

**5개월 개발 only는 함정.** 졸업 발표 후 빠르게 App Store 출시 → 실제 사용자 피드백 받으며 디벨롭. 심사 위원이 가장 좋아하는 것은 "출시했고 X명이 쓰고 있고 데이터로 가설을 검증했다"이며, mock data 데모는 이걸 절대 못 이긴다.

### 5단계 로드맵 (2026)

| Phase | 기간 | 핵심 목표 |
|---|---|---|
| 1 | 5월말~6월초 | 졸업 시연 + App Store 등록 시작 |
| 2 | 6월중~7월중 | TestFlight 베타 100명, 매주 인터뷰 5건 |
| 3 | 7월말~8월말 | 공개 출시 + SNS 쇼츠 마케팅, MAU 500~1000 |
| 4 | 9월~10월초 | 사용자 데이터 정리 + 심사 자료 작성 |
| 5 | 10월~11월 | 1차/최종 심사 + 시상식 |

### 가드레일 — 매 작업 시 두 질문 필수

1. **"이게 `docs/기획/lean-canvas.md` 의 어느 칸에 기여하는가?"** (Problem / Solution / UVP / Channels / Revenue 등)
2. **"이게 현재 Phase 의 검증 목표에 기여하는가?"**

답이 모호하면 그 작업은 **미루거나 폐기**. 산발적 기능 추가 자체가 가장 큰 리스크 (사용자 본인이 인지·요청한 가드레일).

### 우선 참조 문서

- `docs/기획/lean-canvas.md` — 9칸 비즈니스 모델 (어떤 서비스를 만드는가의 정의)
- `docs/기획/공모전-2026-tourapi.md` — 공모전 일정·시상·요건·전략
- `docs/미팅/YYYY-MM-DD.md` — 주차별 진행 기록

