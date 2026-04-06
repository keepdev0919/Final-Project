## Why

GPS 도착 감지, 백그라운드 위치 추적, 백그라운드 오디오 재생이 핵심인 앱에서 Flutter 플러그인 레이어는 불필요한 복잡도를 더한다. CoreLocation·MapKit·AVFoundation을 직접 다루는 Swift 네이티브 iOS 앱이 안정성과 구현 단순성 측면에서 더 적합하다. AI가 코드를 작성하므로 언어 장벽은 없다.

## What Changes

- Flutter 앱 계획을 **Swift + SwiftUI iOS 앱**으로 전면 교체
- MapKit 사용 (Google Maps API 키 불필요)
- CoreLocation으로 백그라운드 GPS 추적 및 장소 도착 감지 구현
- AVFoundation + AVSpeechSynthesizer / OpenAI TTS로 설화 음성 재생
- URLSession으로 FastAPI 백엔드 REST/SSE 통신
- 기존 FastAPI 백엔드는 변경 없음 — iOS 앱이 동일한 엔드포인트를 소비

## Capabilities

### New Capabilities

- `map-home`: 홈 지도 화면 — MapKit 위에 설화·민담 핀 마커 표시, 클러스터링, 마커 탭 팝업 (제목 + 한 줄 요약)
- `course-recommendation`: 테마·일수·이동수단 입력 → `/course/recommend` 호출 → SSE 로딩 화면
- `course-preview`: 추천 코스 미리보기 — 지도 위 경로, 장소 목록, 설화 핀, 혼잡도 배지, 저장/다시 추천
- `explore-mode`: 탐험 모드 — 백그라운드 GPS, 도착 반경 감지, 로컬 푸시 알림, 설화 TTS, 오디오 가이드 탭
- `chatbot-ui`: 챗봇 화면 — SSE 스트리밍 텍스트 출력, 멀티턴 히스토리, 코스 컨텍스트 연결
- `story-generation`: *(스트레치)* 여행 후 멀티모달 스토리 생성 — GPT-4o 에세이 + DALL-E 삽화 + TTS 팟캐스트

### Modified Capabilities

<!-- 없음. 기존 OpenSpec 스펙은 백엔드 전용이며 iOS 전환으로 요구사항 자체는 변경되지 않음 -->

## Impact

- `backend/` — 변경 없음. 기존 5개 라우터(pins, chat, course, tts, tourist)를 그대로 소비
- 신규: `ios/` 디렉토리 — Xcode 프로젝트 루트
- 삭제 예정: CHECKLIST.md의 Flutter 패키지 설정 항목 (google_maps_flutter, geolocator 등)
- 의존 패키지: 없음 (MapKit·CoreLocation·AVFoundation 모두 iOS 시스템 프레임워크)
- 최소 배포 타깃: iOS 17+
