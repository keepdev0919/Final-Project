## ADDED Requirements

### Requirement: post-trip-story-trigger
여행 종료 후 방문한 장소와 설화를 기반으로 멀티모달 스토리 생성을 요청할 수 있어야 한다.

#### Scenario: story-generation-request
- **WHEN** 사용자가 완료된 탐험 코스에서 "스토리 만들기" 버튼을 탭할 때
- **THEN** 방문한 핀 ID 목록과 코스 ID가 `/story/generate` API로 전송되어야 한다

### Requirement: multimodal-story-display
생성된 스토리는 에세이 텍스트, 삽화 이미지, TTS 오디오를 함께 제공해야 한다.

#### Scenario: story-with-image
- **WHEN** `/story/generate` API가 이미지 URL을 포함한 Story 객체를 반환할 때
- **THEN** 에세이 텍스트와 DALL-E 삽화가 함께 표시되어야 한다

#### Scenario: story-text-only-fallback
- **WHEN** DALL-E 생성이 실패하여 이미지 URL이 없을 때
- **THEN** 이미지 없이 텍스트 에세이만 표시되어야 한다

#### Scenario: story-tts-playback
- **WHEN** 사용자가 스토리 화면의 재생 버튼을 탭할 때
- **THEN** 에세이 텍스트가 TTS로 변환되어 팟캐스트 형식으로 재생되어야 한다
