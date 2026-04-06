## ADDED Requirements

### Requirement: streaming-chat-display
챗봇 화면은 `/chat` API의 SSE 스트리밍 응답을 실시간으로 텍스트 버블에 렌더링해야 한다.

#### Scenario: streaming-token-display
- **WHEN** 사용자가 메시지를 전송하고 SSE 스트림이 시작될 때
- **THEN** 토큰이 도착하는 순서대로 어시스턴트 버블에 텍스트가 점진적으로 추가되어야 한다

#### Scenario: stream-complete
- **WHEN** SSE 스트림에서 `[DONE]` 이벤트를 수신할 때
- **THEN** 메시지 버블이 완성 상태로 고정되고 다음 입력이 활성화되어야 한다

### Requirement: multi-turn-history
이전 대화 내용을 히스토리로 유지하여 연속 질문이 가능해야 한다.

#### Scenario: history-sent-with-message
- **WHEN** 사용자가 새 메시지를 전송할 때
- **THEN** 최근 6턴 이내의 대화 히스토리가 ChatRequest의 history 필드에 포함되어 전송되어야 한다

### Requirement: course-context-link
챗봇은 현재 코스와 연결된 컨텍스트로 대화할 수 있어야 한다.

#### Scenario: course-context-passed
- **WHEN** 사용자가 코스 미리보기 또는 탐험 모드에서 챗봇을 열 때
- **THEN** ChatRequest의 course_id 필드에 현재 코스 ID가 포함되어 전송되어야 한다
