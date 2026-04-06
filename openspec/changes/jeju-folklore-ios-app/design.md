## Context

FastAPI 백엔드(5개 라우터)와 데이터 레이어(ChromaDB + SQLite)는 완성되어 있다. 이 design은 그 백엔드를 소비하는 iOS 클라이언트 앱의 아키텍처를 정의한다. 기존 설계 문서(`docs/superpowers/specs/2026-04-01-jeju-folklore-app-design.md`)의 Flutter 앱 부분을 Swift/SwiftUI로 대체한다.

최소 배포 타깃: iOS 17. Xcode 16+.

## Goals / Non-Goals

**Goals:**
- SwiftUI + MVVM 구조로 전체 화면 구현
- CoreLocation으로 백그라운드 GPS 추적 및 도착 감지
- MapKit 기반 지도 화면 (Google Maps 키 불필요)
- AVFoundation으로 백그라운드 TTS 오디오 재생
- URLSession으로 FastAPI REST + SSE 스트리밍 통신
- 코스 로컬 저장 (SwiftData 또는 SQLite)

**Non-Goals:**
- Android 지원 (나중에 별도 Kotlin 프로젝트로 분리)
- 사용자 인증 / 계정 시스템
- 클라우드 동기화 (코스는 기기 로컬 저장)
- 백엔드 코드 변경

## Decisions

### Decision 1: SwiftUI + MVVM

SwiftUI를 기본 UI 프레임워크로 사용하고, 각 화면마다 `@ObservableObject` ViewModel을 둔다. UIKit은 MapKit 커스텀 어노테이션 등 SwiftUI 래핑이 어려운 부분에만 `UIViewRepresentable`로 제한 사용한다.

**대안 고려**: UIKit + Storyboard — 코드량이 많고 AI 생성에 불리함. 기각.

### Decision 2: MapKit (Apple Maps)

Google Maps 대신 MapKit을 사용한다. API 키 불필요, 시스템 프레임워크라 번들 크기 증가 없음, iOS 17+ `MapContentBuilder` API로 SwiftUI 통합이 자연스럽다.

클러스터링은 `MKAnnotationView.clusteringIdentifier`로 구현.

### Decision 3: CoreLocation 백그라운드 위치

`CLLocationManager`를 `AppDelegate` 또는 싱글톤 `LocationService`에서 관리한다. 탐험 모드 진입 시 `.allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false` 설정. 도착 감지는 CLRegion 또는 수동 거리 계산으로 구현한다.

**대안 고려**: CLCircularRegion 모니터링 — iOS가 최대 20개 리전만 허용하므로 코스 장소가 많을 경우 수동 거리 계산 폴백 필요.

### Decision 4: SSE 스트리밍 (챗봇)

`URLSession.dataTask` + `AsyncStream`으로 SSE를 직접 파싱한다. 서드파티 라이브러리 없이 `data: ` 접두사 줄을 파싱하여 토큰을 스트리밍 버블에 append한다.

### Decision 5: 로컬 저장소 (코스)

SwiftData (iOS 17+)를 사용한다. `@Model` 클래스로 `SavedCourse`, `SavedPlace`, `SavedPin`을 정의. 기기 로컬 전용, iCloud 동기화 없음.

### Decision 6: TTS 오디오

`/tts` API로 MP3 바이트를 받아 `AVAudioPlayer`로 재생. `AVAudioSession.sharedInstance().setCategory(.playback)` 설정으로 백그라운드 재생 및 잠금화면 컨트롤 지원.

### Decision 7: 네트워크 레이어

`URLSession` 기반 `APIClient` 싱글톤으로 모든 백엔드 호출을 중앙화. `async/await` 사용. 엔드포인트별 request/response 타입은 `Codable` struct로 정의. 베이스 URL은 `Config.swift`에서 `DEBUG`/`RELEASE` 분기.

## Risks / Trade-offs

- **CoreLocation 백그라운드 권한**: 앱 심사 시 "Always" 위치 권한은 명확한 사용 사례 명시 필요. Info.plist 설명 문구 신중히 작성 필요.
  → 미티게이션: 탐험 모드 진입 시에만 Always 권한 요청, 평소엔 WhenInUse

- **CLRegion 20개 제한**: 코스 장소가 20개를 초과할 경우 CLCircularRegion 모니터링 부족.
  → 미티게이션: 현재 위치 기준 가장 가까운 5개 장소만 활성 리전으로 유지하고 이동에 따라 갱신

- **SSE 파싱 직접 구현**: 서드파티 없이 구현 시 엣지 케이스(멀티라인 data, retry 필드 등) 누락 가능.
  → 미티게이션: `data:` 단일 라인만 사용하는 백엔드 계약 유지 (현재 `chat.py` 방식 그대로)

- **SwiftData iOS 17+ 전용**: iOS 16 이하 지원 불가.
  → 의도적 결정. 졸업프로젝트 시연 기기 기준 iOS 17 이상 가정.

## Migration Plan

1. `ios/` 디렉토리에 Xcode 프로젝트 신규 생성
2. 화면 순서대로 구현: 홈 지도 → 코스 추천 → 미리보기 → 저장 → 탐험 모드 → 챗봇 → 스토리 생성
3. 백엔드는 로컬 실행(`uvicorn`) 기준으로 개발, 배포 시 베이스 URL만 교체

## Open Questions

- KTO API 키 수령 시점에 따라 `tourist.py` 연동 테스트 가능 여부 (W5 예정)
- 심사 시연을 시뮬레이터로 할지 실제 기기로 할지 (백그라운드 GPS는 실기기 필요)
