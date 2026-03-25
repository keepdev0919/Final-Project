# GPS 기반 제주 설화·민담 탐험 앱 설계

**날짜**: 2026-03-25
**프로젝트**: 졸업 프로젝트 — 응용 서비스 개발 트랙

---

## 1. 핵심 목표

제주도 방문객이 여행을 **계획하고, 현장에서 경험하고, 기억으로 남기는** 전 과정에서 제주 설화·민담을 자연스럽게 만날 수 있는 Flutter 모바일 앱을 만든다.

- 필수 조건: RAG 사용, 에이전트 기반 서비스, 제주 공공 데이터 활용
- 데이터 파이프라인(505건 설화·민담, ChromaDB, SQLite)은 이미 완성

---

## 2. 중심 컨셉

**"AI가 설화로 만드는 제주 여행 코스"**

LangGraph 코스 생성 에이전트가 앱의 뼈대다. 나머지 기능(GPS 알림, 챗봇, 스토리 생성)은 코스를 중심으로 한 여정을 보완한다.

---

## 3. 사용자 흐름

### 계획 단계 (여행 전, 집에서)
1. 앱을 열면 제주 전체 지도에 설화 마커 표시 (클러스터링)
2. 마커 탭 → 설화 제목 + 한 줄 요약 팝업
3. 관심 권역 선택 → 조건 입력 (소요시간, 이동수단)
4. LangGraph 에이전트가 코스 생성
5. 코스 미리보기: 지도 위 경로 + 핀 목록 + 예상 시간
6. [다시 생성] 또는 [저장]
7. 저장된 코스에서 챗봇으로 설화 미리 탐구 가능

### 여행 단계 (현장에서)
8. 저장된 코스 불러오기 → [탐험 시작]
9. 실시간 GPS + 경로 안내
10. 장소 도착 시 푸시 알림 → 설화 등장 + TTS 재생
11. 설화 상세 화면에서 챗봇으로 더 깊이 탐구 가능
12. 드라이빙 모드: 알림 액션 버튼으로 TTS 직접 재생 (iOS background audio + 위치 권한 필요)

### 마무리 단계 (여행 후, 스트레치 목표)
13. 방문한 장소 + 열람한 설화 기록 기반으로 스토리 생성
14. GPT-4o (에세이) + DALL-E (삽화) + TTS (팟캐스트) 출력
    - MVP 폴백: 이미지 없이 텍스트 에세이만 생성

---

## 4. 전체 아키텍처

```
[Flutter 앱]
    ↕ REST / SSE
[FastAPI 백엔드]
    ├─ LangGraph 에이전트      ← 코스 생성
    ├─ ReAct 에이전트          ← 챗봇
    ├─ GPS 핀 조회 API         ← 위치 기반 설화 검색
    └─ TTS API                 ← OpenAI TTS 래핑
         ↕
[데이터 레이어] (완성)
    ├─ ChromaDB                ← 벡터 검색 (설화/민담 컬렉션 분리)
    └─ SQLite (metadata.db)    ← 메타데이터, 청크, GPS 좌표
```

---

## 5. 에이전트 설계

### LangGraph 코스 생성 에이전트

```
State = { user_input, region, selected_pins, restaurants, route, validated, retry_count }

analyze_request   → 지역·소요시간·이동수단 파악
select_pins       → RAG로 해당 권역 설화·민담 선별 (다양성 확보)
fetch_restaurants → Google Places API, 핀 반경 500m 맛집·카페 삽입
optimize_route    → Google Directions API, 경로 최적화 + 소요시간 계산
validate_course   → 총 거리·시간·설화 유형 다양성 검증
    ├─ 통과 → generate_card (코스 카드 생성 → 저장/공유)
    └─ 실패 (retry_count < 3) → select_pins 재시도
    └─ 실패 (retry_count >= 3) → 부분 결과로 코스 반환 + 사용자에게 안내
```

### ReAct 챗봇 에이전트

툴 3개:
- `search_folklore` — 설화 ChromaDB 컬렉션 RAG 검색 (텍스트 서사 중심)
- `search_folktale` — 민담 ChromaDB 컬렉션 RAG 검색 (구술 채록 자료 중심)
- `get_nearby_pins` — GPS 반경 내 핀 조회

두 검색 툴은 동일한 임베딩 모델을 사용하되 ChromaDB 컬렉션이 분리되어 있어 메타데이터 필터 없이 타입별 검색이 가능하다.

멀티턴 대화 히스토리 + 사용자가 저장한 코스 컨텍스트 유지.
`max_distance` 임계값 `0.62` (코사인 거리 기준)으로 저관련 청크 제거 → 환각 억제.
출처는 시스템 후처리로 부착 (`제목 (코드: 번호)` 형식).

---

## 6. 데이터 모델

### Pin
| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | 설화/민담 고유 코드 |
| title | String | 설화·민담 제목 |
| type | Enum(folklore/folktale) | 설화 또는 민담 |
| summary | String | 한 줄 요약 |
| lat | Double | 위도 |
| lng | Double | 경도 |
| region | String | 제주 11개 권역 중 하나 |

### Course
| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | UUID |
| title | String | 코스 이름 (LLM 생성) |
| region | String | 대상 권역 |
| pins | List\<Pin\> | 방문 순서대로 정렬된 핀 목록 |
| restaurants | List\<Place\> | 삽입된 맛집·카페 |
| estimated_minutes | Int | 예상 소요시간 |
| created_at | DateTime | 생성 시각 |

### ChatMessage
| 필드 | 타입 | 설명 |
|------|------|------|
| role | Enum(user/assistant) | 발화 주체 |
| content | String | 메시지 내용 |
| sources | List\<String\> | 출처 목록 (후처리 부착) |

### Story (스트레치 목표)
| 필드 | 타입 | 설명 |
|------|------|------|
| essay | String | GPT-4o 생성 에세이 |
| image_urls | List\<String\> | DALL-E 삽화 URL 목록 |
| audio_url | String | TTS 오디오 URL |

코스는 기기 로컬 SQLite에 저장한다. 별도 인증/사용자 계정은 없다.

---

## 7. API 계약 (FastAPI)

| 메서드 | 경로 | 요청 | 응답 |
|--------|------|------|------|
| POST | `/course/generate` | `{ region, duration_minutes, transport }` | `Course` 객체 |
| GET | `/pins` | `?lat=&lng=&radius_m=` | `List<Pin>` |
| POST | `/chat` | `{ message, history, course_id? }` | SSE 스트림 (토큰 단위) |
| POST | `/tts` | `{ text, pin_id }` | `{ audio_url }` (캐시 활용) |
| POST | `/story/generate` | `{ visited_pins, course_id }` | `Story` 객체 |

Google Geocoding 결과는 SQLite에 사전 저장(런타임 호출 없음).
Google Directions/Places 결과는 코스 단위로 캐시하여 중복 과금 방지.

---

## 8. Flutter 앱 화면 구조

| 화면 | 주요 기능 |
|------|---------|
| 홈 (지도) | 설화 마커 전체 표시, 클러스터링, 마커 탭 팝업 |
| 코스 생성 | 조건 입력, LangGraph 에이전트 실행 |
| 코스 미리보기 | 지도 위 경로, 핀 목록, 다시 생성/저장 |
| 내 코스 | 저장된 코스 목록, 탐험 시작 |
| 탐험 모드 | 실시간 GPS, 푸시 알림, 설화 상세, TTS |
| 챗봇 | ReAct 에이전트 멀티턴 대화 |
| 스토리 생성 | GPT-4o + DALL-E + TTS 멀티모달 출력 (스트레치) |

---

## 9. 기술 스택

| 레이어 | 기술 |
|--------|------|
| Flutter 앱 | `google_maps_flutter`, `geolocator`, `flutter_local_notifications` |
| 백엔드 | FastAPI, LangGraph, LangChain |
| LLM / 임베딩 | GPT-4o, `text-embedding-3-small` |
| 벡터 DB | ChromaDB (완성) |
| 메타데이터 DB | SQLite (완성) |
| GPS 좌표 | Google Geocoding API (예비실험 완료, 365건) |
| 경로 최적화 | Google Directions API |
| 맛집 삽입 | Google Places API |
| TTS | OpenAI TTS API |
| 이미지 생성 | DALL-E API (스트레치) |

---

## 10. GPS 좌표 연결 전략

- **설화 (182건)**: 텍스트 내 지명을 화이트리스트 NER로 추출 → Geocoding. 예비실험: 182건 중 138건(75.8%) 유효 지명 추출, 유니크 장소 80곳.
- **민담 (323건)**: 채록 메타데이터의 조사 장소 파싱 → Geocoding.
- 통합 결과: 제주 11개 권역, 365건 위치 기반 콘텐츠.
- Geocoding 결과는 사전 일괄 처리 후 SQLite 저장 (런타임 API 호출 없음).

---

## 11. 에러 처리 전략

| 실패 시나리오 | 처리 방식 |
|-------------|---------|
| LangGraph retry_count >= 3 | 현재까지 선별된 핀으로 부분 코스 반환 + 사용자 안내 토스트 |
| GPS 신호 소실 | 마지막 알려진 위치 유지, "GPS 신호를 찾는 중" 배너 표시 |
| OpenAI API 타임아웃 / 레이트 리밋 | 재시도 1회 후 실패 시 사용자에게 에러 메시지 + 수동 재시도 버튼 |
| TTS 생성 실패 | 텍스트 설화 화면으로 폴백 (오디오 없이 읽기 가능) |
| DALL-E 실패 (스트레치) | 이미지 없이 텍스트 에세이만 반환 |
| Google Places / Directions API 할당량 초과 | 맛집 삽입 생략하고 설화 핀만으로 코스 구성 |

---

## 12. 테스트 전략

- **LangGraph 에이전트**: 각 노드(analyze, select, validate)를 단위 테스트. RAG 검색은 실제 ChromaDB 사용 (모킹 없음).
- **ReAct 챗봇**: 주요 질문 시나리오 10개로 툴 호출 정확성 수동 검증.
- **GPS 기능**: 시뮬레이터의 GPX 경로 재생으로 핀 도착 이벤트 테스트.
- **Flutter 화면**: 코스 미리보기, 탐험 모드 핵심 위젯 단위 테스트.
- **평가 질문셋**: 기존 `evaluation_runner.py` 활용하여 RAG 검색 품질 정량 평가.

---

## 13. 학기 구현 우선순위

데이터 파이프라인이 완성되어 있으므로 이번 학기 핵심 작업은 아래 순서다.

1. GPS 좌표 DB 구축 완성 (Geocoding 연동 + SQLite 저장)
2. FastAPI 백엔드 + LangGraph 코스 생성 에이전트
3. Flutter 앱 — 지도 화면 + 코스 생성/미리보기/저장
4. Flutter 앱 — 탐험 모드 (GPS + 푸시 알림 + TTS)
5. ReAct 챗봇 에이전트 + Flutter 연동
6. *(스트레치)* 멀티모달 스토리 생성 (GPT-4o + DALL-E + TTS)
