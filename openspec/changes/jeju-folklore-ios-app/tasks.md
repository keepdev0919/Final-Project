## 1. Xcode 프로젝트 셋업

- [x] 1.1 `ios/` 디렉토리에 SwiftUI + SwiftData Xcode 프로젝트 생성 (번들 ID: com.keepdev.jejufolklore)
- [x] 1.2 `Config.swift` 작성 — DEBUG/RELEASE 백엔드 베이스 URL 분기
- [x] 1.3 `APIClient.swift` 작성 — URLSession async/await 기반 공통 request/response 레이어
- [x] 1.4 Info.plist에 위치 권한 설명 추가 (NSLocationWhenInUseUsageDescription, NSLocationAlwaysAndWhenInUseUsageDescription)
- [x] 1.5 Info.plist에 백그라운드 모드 설정 (location, audio)

## 2. 데이터 모델 (SwiftData + Codable)

- [x] 2.1 `Pin.swift` — Codable struct (code_no, title, source_type, summary, lat, lng, primary_place, distance_m)
- [x] 2.2 `Course.swift` — Codable struct (id, title, duration_days, places, estimated_minutes)
- [x] 2.3 `CoursePlace.swift` — Codable struct (name, lat, lng, day, start_time, folklore_pins)
- [x] 2.4 `ChatMessage.swift` — Codable struct (role, content, sources)
- [x] 2.5 `SavedCourse.swift` — @Model 클래스 (SwiftData 로컬 저장용)

## 3. 서비스 레이어

- [x] 3.1 `LocationService.swift` — CLLocationManager 싱글톤, 백그라운드 GPS 추적, 도착 반경 감지
- [x] 3.2 `PinsAPI.swift` — GET /pins 호출, lat/lng/radius_m 파라미터
- [x] 3.3 `CourseAPI.swift` — POST /course/recommend 호출
- [x] 3.4 `ChatAPI.swift` — POST /chat SSE 스트리밍 파싱 (AsyncStream<String>)
- [x] 3.5 `TTSAPI.swift` — POST /tts 호출, MP3 Data 반환
- [x] 3.6 `AudioPlayer.swift` — AVAudioPlayer 래퍼, AVAudioSession .playback 설정

## 4. 홈 지도 화면 (map-home)

- [x] 4.1 `HomeViewModel.swift` — 앱 시작 시 전체 핀 1회 로드 (`/pins/all`), 좌표별 PinGroup 그룹핑
- [x] 4.2 `HomeView.swift` — UIViewRepresentable MKMapView, 좌표 기반 그룹 마커 표시
- [x] 4.3 단일 핀 마커 탭 → FolkloreDetailView 시트 직접 표시
- [x] 4.4 복수 핀 마커 탭 → PinListSheet (장소 내 설화 목록) → 설화 탭 → FolkloreDetailView
- [x] 4.5 GPS 정밀도 개선 — NER whitelist 30개 리 단위 지명 추가, SPECIFICITY 점수 반영 후 geocoding 재실행 (최대 클러스터 36→10)

## 5. 코스 추천 화면 (course-recommendation)

- [x] 5.1 `CourseRecommendViewModel.swift` — 테마/일수/이동수단 상태, API 호출 및 단계별 로딩 상태 관리
- [x] 5.2 `CourseRecommendView.swift` — 테마 선택 그리드, 일수·이동수단 피커
- [x] 5.3 로딩 화면 — "설화 검색 중...", "동선 최적화 중...", "완성!" 단계별 텍스트 애니메이션
- [x] 5.4 에러 상태 뷰 + 다시 시도 버튼

## 6. 코스 미리보기 + 저장 (course-preview)

- [x] 6.1 `CoursePreviewViewModel.swift` — 코스 데이터 보관, SwiftData 저장 로직
- [x] 6.2 `CoursePreviewView.swift` — Map 위 번호 마커 + 폴리라인 경로 표시
- [x] 6.3 하단 시트 — 장소 카드 스크롤 뷰 (장소명, 설화 제목, 혼잡도 배지 🟢🟡🔴)
- [x] 6.4 저장 버튼 → SwiftData에 SavedCourse 저장 + 토스트 피드백
- [x] 6.5 다시 추천 버튼 → 동일 조건 재호출

## 7. 내 코스 목록 화면

- [x] 7.1 `MyCourseListView.swift` — SwiftData @Query로 저장된 코스 목록 표시
- [x] 7.2 코스 카드 탭 → 탐험 시작 버튼 포함 상세 뷰

## 8. 탐험 모드 (explore-mode)

- [x] 8.1 `ExploreViewModel.swift` — 탐험 상태 관리, 도착 이벤트 수신, 방문 완료 장소 추적
- [x] 8.2 `ExploreView.swift` — 실시간 GPS 지도 뷰, 현재 위치 블루닷, 다음 목적지 표시
- [x] 8.3 LocationService에 도착 반경 감지 추가 (도보 100m / 차량 300m, 중복 방지)
- [x] 8.4 UNUserNotificationCenter 도착 알림 — "설화 듣기" 액션 버튼 포함
- [x] 8.5 알림 액션 → 백그라운드에서 TTS 재생 (UNNotificationAction + AudioPlayer)
- [x] 8.6 `FolkloreDetailView.swift` — 설화 탭 (텍스트 + TTS 재생 버튼) / 공식 안내 탭 (KTO 오디오 가이드)
- [x] 8.7 TTS 재생 백그라운드 유지 (AVAudioSession .playback 카테고리)

## 9. 챗봇 화면 (chatbot-ui)

- [x] 9.1 `ChatViewModel.swift` — 메시지 히스토리 관리, SSE 스트림 수신, course_id 컨텍스트 주입
- [x] 9.2 `ChatView.swift` — 메시지 버블 리스트, 스트리밍 토큰 append 애니메이션
- [x] 9.3 텍스트 입력창 + 전송 버튼, 스트리밍 중 전송 비활성화

## 10. 스토리 생성 화면 (story-generation, 스트레치)

- [ ] 10.1 `StoryViewModel.swift` — POST /story/generate 호출, 이미지 URL 유무에 따른 폴백 처리
- [ ] 10.2 `StoryView.swift` — 에세이 텍스트 + DALL-E 삽화 (이미지 없으면 텍스트만)
- [ ] 10.3 TTS 재생 버튼 — 에세이 텍스트를 AudioPlayer로 팟캐스트 형식 재생

## 11. 통합 확인

- [ ] 11.1 시뮬레이터에서 홈 지도 핀 로딩 동작 확인
- [ ] 11.2 코스 추천 → 미리보기 → 저장 전체 플로우 확인
- [ ] 11.3 실기기에서 백그라운드 GPS 추적 및 도착 알림 동작 확인
- [ ] 11.4 챗봇 SSE 스트리밍 텍스트 렌더링 확인
