## ADDED Requirements

### Requirement: background-location-tracking
탐험 모드에서는 앱이 백그라운드 상태에서도 사용자 GPS 위치를 지속 추적해야 한다.

#### Scenario: start-exploration
- **WHEN** 사용자가 저장된 코스에서 탐험 시작 버튼을 탭할 때
- **THEN** CoreLocation significantLocationChanges 또는 standard location updates가 백그라운드 모드로 시작되어야 한다
- **AND** Info.plist의 NSLocationAlwaysAndWhenInUseUsageDescription 권한이 요청되어야 한다

#### Scenario: tracking-continues-in-background
- **WHEN** 탐험 모드가 활성화된 상태에서 앱이 백그라운드로 전환될 때
- **THEN** 위치 추적이 중단 없이 계속되어야 한다

### Requirement: arrival-detection
코스의 각 장소에 도착 반경 내로 진입하면 도착 이벤트를 발생시켜야 한다.

#### Scenario: arrival-trigger-walking
- **WHEN** 사용자 위치가 장소 좌표로부터 100m 이내로 진입할 때 (이동수단: 도보)
- **THEN** 해당 장소의 도착 이벤트가 발생해야 한다

#### Scenario: arrival-trigger-driving
- **WHEN** 사용자 위치가 장소 좌표로부터 300m 이내로 진입할 때 (이동수단: 차량)
- **THEN** 해당 장소의 도착 이벤트가 발생해야 한다

#### Scenario: no-duplicate-arrival
- **WHEN** 이미 도착 이벤트가 발생한 장소 반경 내에서 계속 이동할 때
- **THEN** 동일 장소에 대한 도착 이벤트가 재발생하지 않아야 한다

### Requirement: arrival-push-notification
장소 도착 시 로컬 푸시 알림으로 설화 등장을 안내해야 한다.

#### Scenario: push-notification-on-arrival
- **WHEN** 장소 도착 이벤트가 발생할 때
- **THEN** UNUserNotificationCenter를 통해 설화 제목을 포함한 로컬 알림이 전송되어야 한다
- **AND** 알림 액션에 "설화 듣기" 버튼이 포함되어야 한다

#### Scenario: notification-action-tts
- **WHEN** 사용자가 알림의 "설화 듣기" 버튼을 탭할 때
- **THEN** 설화 TTS가 즉시 재생되어야 한다 (앱 포그라운드 전환 없이)

### Requirement: folklore-tts-playback
도착한 장소의 설화 내용을 음성으로 재생해야 한다.

#### Scenario: tts-play
- **WHEN** 설화 상세 화면에서 재생 버튼을 탭할 때
- **THEN** `/tts` API로 설화 텍스트를 전송하고 반환된 오디오를 AVAudioPlayer로 재생해야 한다

#### Scenario: tts-background-audio
- **WHEN** TTS 재생 중 앱이 백그라운드로 전환될 때
- **THEN** AVAudioSession을 .playback 카테고리로 설정하여 오디오가 계속 재생되어야 한다

### Requirement: official-audio-guide-tab
설화 상세 화면에서 한국관광공사 공식 오디오 가이드를 제공하는 탭이 있어야 한다.

#### Scenario: audio-guide-tab-display
- **WHEN** 사용자가 설화 상세 화면의 "공식 안내" 탭을 선택할 때
- **THEN** KTO 오디오 가이드 음성 파일과 텍스트 대본이 표시되어야 한다
- **AND** 오디오 가이드 데이터가 없는 경우 "공식 안내 없음" 안내 메시지가 표시되어야 한다
