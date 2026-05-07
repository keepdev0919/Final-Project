
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
