<!-- /autoplan restore point: /Users/choikjun/.gstack/projects/keepdev0919-Final-Project/main-autoplan-restore-20260401-142025.md -->
# GPS 기반 제주 설화·민담 탐험 앱 설계

**날짜**: 2026-04-01 (최초: 2026-03-25, 공모전 API 통합: 2026-03-30)
**프로젝트**: 졸업 프로젝트 — 응용 서비스 개발 트랙 / 2026 관광데이터 활용 공모전 ① 웹·앱 개발 부문

---

## 1. 핵심 목표

제주도 방문객이 여행을 **계획하고, 현장에서 경험하고, 기억으로 남기는** 전 과정에서 제주 설화·민담을 자연스럽게 만날 수 있는 Flutter 모바일 앱을 만든다.

- 필수 조건: RAG 사용, 에이전트 기반 서비스, 제주 공공 데이터 활용
- 데이터 파이프라인(505건 설화·민담, ChromaDB, SQLite)은 이미 완성
- **핵심 전략**: AI가 코스를 처음부터 창작하는 대신, Visit Jeju 실제 관광객 검증 코스 위에 설화·민담을 매핑

---

## 2. 중심 컨셉

**"실제 검증된 여행 코스 위에 설화를 얹는다"**

LangGraph 에이전트가 Visit Jeju의 9,134개 실제 여행 일정 중 조건에 맞는 코스를 선별하고, RAG로 각 장소 인근 설화·민담을 매핑·큐레이션한다. 코스의 현실성은 실제 데이터가 보장하고, AI는 문화 콘텐츠 매핑에 집중한다.

한국관광공사 OpenAPI 5개를 추가로 연동하여 장소 정보 보완, 혼잡도 회피, 공식 오디오 가이드를 제공한다.

---

## 3. 사용자 흐름

### 계획 단계 (여행 전, 집에서)
1. 앱을 열면 제주 전체 지도에 설화 마커 표시 (클러스터링)
2. 마커 탭 → 설화 제목 + 한 줄 요약 팝업
3. 관심 권역 선택 → 조건 입력 (여행 일수, 이동수단)
4. LangGraph 에이전트가 Visit Jeju 코스 선별 + 설화 매핑 + 혼잡도 반영
5. 코스 미리보기: 지도 위 경로 + 장소 목록(사진 포함) + 매핑된 설화 + 혼잡도 배지 + 예상 시간
6. [다시 추천] 또는 [저장]
7. 저장된 코스에서 챗봇으로 설화 미리 탐구 가능

### 여행 단계 (현장에서)
8. 저장된 코스 불러오기 → [탐험 시작]
9. 실시간 GPS + 경로 안내
10. 장소 도착 시 푸시 알림 → 설화 등장 + TTS 재생
11. 설화 상세 화면에서 챗봇으로 더 깊이 탐구 가능
12. "공식 안내" 탭에서 한국관광공사 오디오 가이드 음성+대본 제공
13. 드라이빙 모드: 알림 액션 버튼으로 TTS 직접 재생 (iOS background audio + 위치 권한 필요)

### 마무리 단계 (여행 후, 스트레치 목표)
14. 방문한 장소 + 열람한 설화 기록 기반으로 스토리 생성
15. GPT-4o (에세이) + DALL-E (삽화) + TTS (팟캐스트) 출력
    - MVP 폴백: 이미지 없이 텍스트 에세이만 생성

---

## 4. 전체 아키텍처

```
[Flutter 앱]
    ↕ REST / SSE
[FastAPI 백엔드]
    ├─ LangGraph 에이전트      ← 코스 선별 + 설화 매핑 + KTO API 보완
    ├─ ReAct 에이전트          ← 챗봇
    ├─ GPS 핀 조회 API         ← 위치 기반 설화 검색
    ├─ TTS API                 ← OpenAI TTS 래핑
    └─ KTO API 프록시          ← 국문 관광정보 / 연관 관광지 / 집중률 예측 (캐싱)
         ↕
[데이터 레이어]
    ├─ Visit Jeju 여행일정 DB  ← 9,134개 실제 코스 + 6,002개 장소(GPS) + content_id 컬럼
    ├─ ChromaDB                ← 설화/민담 벡터 DB (컬렉션 분리)
    ├─ SQLite (metadata.db)    ← 설화·민담 메타데이터, 청크, GPS 좌표
    └─ tourist_info_cache      ← 국문 관광정보 7일 캐시

[Flutter 직접 호출]
    ├─ KTO 관광사진 API        ← 코스 미리보기·탐험 모드 장소 카드 이미지
    └─ KTO 오디오 가이드 API   ← 탐험 모드 "공식 안내" 탭
```

---

## 5. 에이전트 설계

### LangGraph 코스 추천 에이전트

```
State = { user_input, region, duration_days, transport,
          candidate_courses, folklore_mapped_courses,
          enriched_courses, ranked_courses, validated, retry_count }

analyze_request       → 지역·여행 일수·이동수단 파악
search_courses        → Visit Jeju DB에서 조건(지역·일수)에 맞는 후보 코스 검색
map_folklore          → 각 후보 코스의 장소별 반경 내 설화·민담 RAG 매핑
enrich_places   [NEW] → 국문 관광정보 API로 각 장소 최신 정보 보완
                        (운영시간, 주소, 카테고리, 전화번호)
replace_low_coverage  → 설화 커버리지 낮은 장소를 연관 관광지 API로 대안 탐색
              [NEW]
fetch_congestion[NEW] → 집중률 예측 API로 여행 예정일 기준 혼잡도 조회
rank_courses          → 설화 커버리지 + 혼잡도 기준 코스 랭킹
                        점수 = (설화 커버리지 × 0.7) + (혼잡도 역수 × 0.3)
                        혼잡도 데이터 없는 장소는 기본값 0.5 적용
validate_course       → 총 거리·시간·설화 유형 다양성 검증
    ├─ 통과 → generate_card (코스 카드 생성 → 저장/공유)
    ├─ 실패 (retry_count < 3) → search_courses 재검색 (조건 완화)
    └─ 실패 (retry_count >= 3) → 현재 최선 코스 반환 + 사용자 안내
```

### ReAct 챗봇 에이전트

툴 3개:
- `search_folklore` — 설화 ChromaDB 컬렉션 RAG 검색 (텍스트 서사 중심)
- `search_folktale` — 민담 ChromaDB 컬렉션 RAG 검색 (구술 채록 자료 중심)
- `get_nearby_pins` — GPS 반경 내 핀 조회

두 검색 툴은 동일한 임베딩 모델을 사용하되 ChromaDB 컬렉션이 분리되어 있어 타입별 검색이 가능하다.

멀티턴 대화 히스토리 + 사용자가 저장한 코스 컨텍스트 유지.
`max_distance` 임계값 `0.62` (코사인 거리 기준)으로 저관련 청크 제거 → 환각 억제.
출처는 시스템 후처리로 부착 (`제목 (코드: 번호)` 형식).

---

## 6. 데이터 모델

### VisitJejuCourse
| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | 여행일정아이디 |
| title | String | 여행일정타이틀 |
| duration_days | Int | 여행 일수 |
| places | List\<VisitJejuPlace\> | 일차별 방문 장소 목록 |

### VisitJejuPlace
| 필드 | 타입 | 설명 |
|------|------|------|
| name | String | 장소명 |
| lat | Double | 위도 |
| lng | Double | 경도 |
| day | Int | 여행 일차 |
| start_time | String | 시작 시간 |
| content_id | String? | 한국관광공사 contentId (전처리 매핑, 없으면 null) |

### Pin (설화·민담)
| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | 설화/민담 고유 코드 |
| title | String | 설화·민담 제목 |
| type | Enum(folklore/folktale) | 설화 또는 민담 |
| summary | String | 한 줄 요약 |
| lat | Double | 위도 |
| lng | Double | 경도 |
| region | String | 제주 11개 권역 중 하나 |

### Course (추천 결과)
| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | UUID |
| source_course_id | String | 기반 Visit Jeju 일정 ID |
| title | String | 코스 이름 (LLM 생성) |
| places | List\<VisitJejuPlace\> | 방문 장소 목록 |
| folklore_pins | List\<Pin\> | 매핑된 설화·민담 핀 |
| estimated_minutes | Int | 예상 소요시간 |
| created_at | DateTime | 생성 시각 |

### ChatMessage
| 필드 | 타입 | 설명 |
|------|------|------|
| role | Enum(user/assistant) | 발화 주체 |
| content | String | 메시지 내용 |
| sources | List\<String\> | 출처 목록 (후처리 부착) |

코스는 기기 로컬 SQLite에 저장한다. 별도 인증/사용자 계정은 없다.

### SQLite 추가 테이블

```sql
-- Visit Jeju 장소에 contentId 컬럼 추가 (전처리 단계에서 alter)
ALTER TABLE visit_jeju_places ADD COLUMN content_id TEXT;

-- 국문 관광정보 캐시 (7일)
CREATE TABLE tourist_info_cache (
    content_id TEXT PRIMARY KEY,
    name       TEXT,
    address    TEXT,
    phone      TEXT,
    category   TEXT,
    cached_at  DATETIME
);
```

집중률 예측은 일별로 달라지므로 캐시 없이 매 코스 추천 시 실시간 조회한다.

### KTO OpenAPI 실제 식별자 구조

API 매뉴얼 확인 결과, 5개 API 중 `contentId`를 사용하는 API는 **국문관광정보 1개뿐**이다. 나머지는 별도 식별자 체계를 사용한다.

| API | ServiceID | 핵심 식별자 | 연결 방식 |
|-----|-----------|-----------|---------|
| 국문관광정보 | `KorService2` | `contentId` | GPS → `locationBasedList1` → contentId → `detailCommon2` |
| 관광사진 | `PhotoGalleryService1` | `galContentId` (별도) | 키워드/지역 검색 (`galleryList1`) |
| 오디오가이드 | `Odii` | `tid` (관광지아이디, 별도) | 지역코드 기반 목록 조회 (`themeBasedList1`) |
| 연관관광지 | `TarRlteTarService1` | `areaCd + signguCd + baseYm` | 지역코드+년월 조합 → `tAtsCd`/`rlteTatsCd` 반환 |
| 집중률 예측 | `TatsCntrRateService` | `areaCd + signguCd + tAtsNm` | 지역코드+장소명 → `cnctrRate`(%) 반환 |

### contentId 매핑 전략 (국문관광정보 전용)

Visit Jeju 장소 CSV에는 contentId가 없으므로 사전 전처리가 필요하다. **국문관광정보 API에만 해당**.

1. **일괄 매핑**: 국문관광정보 API 위치기반 검색(`locationBasedList1`)으로 제주 전체 관광지 수집 → 장소명 유사도 매칭 (완전일치 우선) → `content_id` 컬럼 추가
2. **매핑 실패 처리**: contentId 없는 장소는 국문관광정보/관광사진 API 호출 스킵, 기본값 적용
3. **연관관광지·집중률**: contentId 불필요 — 지역코드(areaCd)+시군구코드(signguCd)로 독립 호출 가능
4. **관광사진**: galContentId 매핑이 어려운 경우 장소명 키워드 검색(`gallerySearchList1`)으로 우회
5. **오디오가이드**: tid 매핑 어려운 경우 지역코드 기반 전체 목록에서 장소명 매칭으로 우회

---

## 7. API 계약 (FastAPI)

### 기존 엔드포인트

| 메서드 | 경로 | 요청 | 응답 |
|--------|------|------|------|
| POST | `/course/recommend` | `{ region, duration_days, transport }` | `Course` 객체 |
| GET | `/pins` | `?lat=&lng=&radius_m=` | `List<Pin>` |
| POST | `/chat` | `{ message, history, course_id? }` | SSE 스트림 (토큰 단위) |
| POST | `/tts` | `{ text, pin_id }` | `{ audio_url }` (캐시 활용) |
| POST | `/story/generate` | `{ visited_pins, course_id }` | `Story` 객체 |

### KTO API 프록시 엔드포인트 (신규)

| 메서드 | 경로 | 파라미터 | KTO 서비스 | 설명 |
|--------|------|---------|-----------|------|
| GET | `/tourist/info` | `content_id` | `KorService2/detailCommon2` | 국문 관광정보 조회 (7일 캐시) |
| GET | `/tourist/related` | `area_cd`, `signgu_cd`, `base_ym(YYYYMM)` | `TarRlteTarService1/AreaBasedList1` | 연관 관광지 조회 |
| GET | `/tourist/congestion` | `area_cd`, `signgu_cd`, `tats_nm?`, `date` | `TatsCntrRateService/tatsCntrRateList` | 집중률 예측 조회 (캐시 없음, 30일 예측) |

### Flutter 직접 호출 (백엔드 경유 없음)

- 관광사진 API: 코스 미리보기 화면, 탐험 모드 장소 카드
- 오디오 가이드 API: 탐험 모드 "공식 안내" 탭

Google Geocoding 결과는 SQLite에 사전 저장 (런타임 호출 없음).

---

## 8. Flutter 앱 화면 구조

| 화면 | 주요 기능 |
|------|---------|
| 홈 (지도) | 설화 마커 전체 표시, 클러스터링, 마커 탭 팝업 |
| 코스 추천 | 조건 입력, LangGraph 에이전트 실행 |
| 코스 미리보기 | 지도 위 경로, 장소+설화 목록, 관광사진, 혼잡도 배지, 다시 추천/저장 |
| 내 코스 | 저장된 코스 목록, 탐험 시작 |
| 탐험 모드 | 실시간 GPS, 푸시 알림, 설화 TTS / 공식 안내 탭 분리 |
| 챗봇 | ReAct 에이전트 멀티턴 대화 |
| 스토리 생성 | GPT-4o + DALL-E + TTS 멀티모달 출력 (스트레치) |

탐험 모드 장소 도착 시 콘텐츠 탭 구성:
- **설화 탭**: 우리 RAG 설화·민담 TTS
- **공식 안내 탭**: 한국관광공사 오디오 가이드 음성 + 대본

코스 미리보기 혼잡도 배지: 🟢 여유 / 🟡 보통 / 🔴 혼잡 (예측일 기준)

---

## 9. 기술 스택

| 레이어 | 기술 |
|--------|------|
| Flutter 앱 | `google_maps_flutter`, `geolocator`, `flutter_local_notifications` |
| 백엔드 | FastAPI, LangGraph, LangChain |
| LLM / 임베딩 | GPT-4o, `text-embedding-3-small` |
| 벡터 DB | ChromaDB (완성) |
| 메타데이터 DB | SQLite (완성) |
| Visit Jeju 데이터 | 여행장소(6,002개) + 여행세부일정(9,134개 일정) CSV |
| 공공 데이터 API | 한국관광공사 OpenAPI 5종 (국문 관광정보, 관광사진, 오디오 가이드, 연관 관광지, 집중률 예측) |
| GPS 좌표 | Google Geocoding API (예비실험 완료, 365건) |
| TTS | OpenAI TTS API |
| 이미지 생성 | DALL-E API (스트레치) |

---

## 10. GPS 좌표 연결 전략

- **설화 (182건)**: 텍스트 내 지명을 화이트리스트 NER로 추출 → Geocoding. 예비실험: 182건 중 138건(75.8%) 유효 지명 추출.
- **민담 (323건)**: 채록 메타데이터의 조사 장소 파싱 → Geocoding.
- **Visit Jeju 장소**: 여행장소 CSV에 위경도 직접 포함. 여행세부일정과 장소명 기준 조인하여 코스 DB 구축.
- Geocoding 결과는 사전 일괄 처리 후 SQLite 저장 (런타임 API 호출 없음).

---

## 11. 에러 처리 전략

| 실패 시나리오 | 처리 방식 |
|-------------|---------|
| LangGraph retry_count >= 3 | 현재 최선 코스 반환 + 사용자 안내 토스트 |
| 조건에 맞는 Visit Jeju 코스 없음 | 조건 완화 (지역 반경 확대 또는 일수 ±1) 후 재검색 |
| GPS 신호 소실 | 마지막 알려진 위치 유지, "GPS 신호를 찾는 중" 배너 표시 |
| OpenAI API 타임아웃 / 레이트 리밋 | 재시도 1회 후 실패 시 에러 메시지 + 수동 재시도 버튼 |
| TTS 생성 실패 | 텍스트 설화 화면으로 폴백 |
| DALL-E 실패 (스트레치) | 이미지 없이 텍스트 에세이만 반환 |
| KTO API 응답 없음 | contentId 없는 장소와 동일하게 처리 (기본값 적용) |
| contentId 매핑 실패 | 국문관광정보·관광사진 호출 스킵 (기본값 적용). 연관관광지·집중률은 지역코드 기반이므로 contentId 없어도 정상 호출 |

---

## 12. 테스트 전략

- **LangGraph 에이전트**: 각 노드(search, map, enrich, replace, fetch_congestion, rank, validate)를 단위 테스트. RAG 검색은 실제 ChromaDB 사용 (모킹 없음).
- **ReAct 챗봇**: 주요 질문 시나리오 10개로 툴 호출 정확성 수동 검증.
- **GPS 기능**: 시뮬레이터의 GPX 경로 재생으로 핀 도착 이벤트 테스트.
- **Flutter 화면**: 코스 미리보기, 탐험 모드 핵심 위젯 단위 테스트.
- **평가 질문셋**: 기존 `evaluation_runner.py` 활용하여 RAG 검색 품질 정량 평가.
- **KTO API 연동**: contentId 매핑률 측정, 각 엔드포인트 응답 스키마 검증.

---

## 13. 구현 우선순위

1. **Visit Jeju 데이터 전처리** — 장소명 조인 → courses DB 구축 + GPS 좌표 DB 완성
2. **FastAPI 백엔드 + LangGraph 에이전트** — search→map→replace→fetch_congestion→rank→validate + KTO 프록시 엔드포인트 3개 (enrich_places는 contentId 매핑 완료 후 추가)
3. **Flutter 앱 — 지도 화면 + 코스 추천/미리보기/저장** (관광사진 키워드 검색 우회, 혼잡도 배지 포함)
4. **Flutter 앱 — 탐험 모드** (GPS + 푸시 알림 + TTS + 공식 안내 탭)
5. **ReAct 챗봇 에이전트 + Flutter 연동**
6. **contentId 매핑 전처리 + enrich_places 노드 추가** — Visit Jeju 장소 6,002개에 contentId 매핑 → 코스 미리보기에 운영시간·전화번호 표시 (국문관광정보 API 전용, MVP 이후 보강)
7. *(스트레치)* **멀티모달 스토리 생성** (GPT-4o + DALL-E + TTS)

---

## 14. 공모전 심사 기준 매핑

| 심사항목 | 배점 | 어필 포인트 |
|---------|------|-----------|
| 서비스 기획력 (독창성, 트렌드) | 30 | 설화 RAG + 혼잡도 회피 AI 에이전트 — 단순 관광정보 앱과 차별화 |
| 서비스 완성도 (기능성, 편의성) | 30 | 5개 KTO API가 각 화면에 명확히 연결된 완성된 흐름 |
| 데이터 활용 적절성 | 20 | 5개 API 전부 사용자가 직접 체감하는 위치에 배치 |
| 서비스 발전성 (확장성) | 20 | 영문 관광정보 API 추가 시 외국인 확장 용이한 구조 |
| 지역 특화 가점 | +2 | 제주 특화 서비스 → 자동 해당 |
| 제주 RTO 특별상 | 별도 | 제주관광공사 협업 RTO 특별상 후보 |

---

## 15. /autoplan Reviews (2026-04-01)

### PHASE 2: Design Review [subagent-only]

**Design Litmus Scorecard:**

| Dimension | Score | Key Finding |
|-----------|-------|-------------|
| Onboarding / first-run flow | 3/10 | 빈 상태 + 온보딩 완전 미정의 |
| Loading / async states | 2/10 | LangGraph 10~20초 로딩 화면 없음 |
| Error states | 4/10 | KTO 사진 실패, GPS 음영, 오프라인 미정의 |
| Navigation / routing | 5/10 | 푸시 알림 탭 → 딥링크 라우팅 미정의 |
| Input components | 4/10 | 코스 추천 조건 입력 UI 컴포넌트 미정의 |
| Demo readiness | 2/10 | 3개 치명적 데모 실패 시나리오 존재 |
| Driving mode UX | 4/10 | 도착 감지 반경 미정의, 고속 이동 시 오발화 |

**Critical Design Findings:**

1. **[CRITICAL] 온보딩 없음** — 첫 실행 시 지도+마커만 있고 사용자 유도 없음. 바텀시트 2단계 온보딩 추가 필요.
2. **[CRITICAL] 코스 추천 로딩 UX 미정의** — 10~20초 대기 중 화면 없음. SSE 단계별 상태 텍스트 필수.
3. **[CRITICAL] 푸시 알림 딥링크 라우팅 미정의** — 알림 탭 → 어느 화면? `notification payload → screen route` 매핑 명세 필요.
4. **[CRITICAL] 데모 모드 없음** — 심사 중 20초 침묵 방지용 캐시된 응답 "데모 플래그" 필요.
5. **[HIGH] TTS 사전 생성 없음** — 도착 시 온디맨드 TTS면 수 초 지연. 코스 저장 시점 일괄 사전 생성으로 변경.
6. **[HIGH] 도착 감지 반경 미정의** — 도보 100m / 차량 300m 명시 필요.

**Design: NOT in scope** — 애니메이션 트랜지션, 다크모드, 접근성(색맹 대비) → 공모전 후 처리

---

### PHASE 3: Eng Review [subagent-only]

**Architecture ASCII Diagram:**
```
Flutter App
  ├─ google_maps_flutter / geolocator / flutter_local_notifications
  ├── REST/SSE ──► FastAPI Backend
  │                 ├─ LangGraph Agent (7 nodes, asyncio 병렬화 필요)
  │                 │   ├─ ChromaDB [완성, 파일 I/O — 볼륨 마운트 필수]
  │                 │   ├─ SQLite metadata [완성]
  │                 │   ├─ Visit Jeju DB [미존재 — 블로커]
  │                 │   └─ KTO Proxy: KorService2, TarRlteTarService1,
  │                 │                 TatsCntrRateService
  │                 └─ ReAct Chatbot
  │                     └─ ChromaDB [동일 인스턴스]
  └── Direct HTTP ──► PhotoGalleryService1 [CRITICAL: API 키 노출]
                   └► Odii [CRITICAL: API 키 노출]
```

**ENG Dual Voices — Consensus Table [subagent-only]:**
```
ENG DUAL VOICES — CONSENSUS TABLE:
══════════════════════════════════════════════════════════════
  Dimension                         Subagent  Codex  Consensus
  ───────────────────────────────── ──────── ─────── ─────────
  1. Architecture sound?             PARTIAL   N/A   PARTIAL
  2. Test coverage sufficient?       NO        N/A   NO
  3. Performance risks addressed?    NO        N/A   NO
  4. Security threats covered?       CRITICAL  N/A   CRITICAL
  5. Error paths handled?            PARTIAL   N/A   PARTIAL
  6. Deployment risk manageable?     NO        N/A   NO
══════════════════════════════════════════════════════════════
```

**Critical Eng Findings:**

| # | 심각도 | 컴포넌트 | 문제 |
|---|--------|---------|------|
| E1 | CRITICAL | LangGraph | p95 레이턴시 10~25초. 3초 목표 불가 |
| E2 | CRITICAL | Flutter + KTO API | 관광사진/오디오 직접 호출 → API 키 APK에 노출 |
| E3 | CRITICAL | Visit Jeju CSV | 미확보 + 포맷 불일치 폴백 없음 → LangGraph 구현 블로커 |
| E4 | HIGH | ChromaDB | 컨테이너 재시작 시 볼륨 없으면 벡터 DB 소실 |
| E5 | HIGH | FastAPI | 인증 없음 → `/course/recommend` 무제한 호출 → GPT-4o 비용 폭발 |
| E6 | HIGH | 배포 | Railway 프리 콜드 스타트 5~15초 + 디스크 비영속 |
| E7 | HIGH | contentId 전처리 | 스크립트 없음 + 퍼지 매칭 오매핑 위험 |
| E8 | HIGH | 테스트 | GPS 트리거, 노드 실패 전이, KTO 레이트 리밋 미커버 |

**자동 결정된 수정 사항:**
- **E2 → 자동 수정**: Flutter 직접 호출 → FastAPI KTO 프록시로 이전. API 키는 서버 환경변수만.
- **E1 → 자동 수정**: `enrich_places` + `fetch_congestion` 노드에 `asyncio.gather` 병렬화. 응답은 SSE 스트리밍.
- **E5 → 자동 수정**: FastAPI에 `slowapi` rate limiting + 내부용 API key 헤더 추가.
- **E6 → 자동 수정**: `/health` 헬스체크 엔드포인트 + UptimeRobot 15분 핑. 데모 당일 유료 플랜($5/월) 또는 ngrok.
- **E3 → 사용자 결정 반영**: CSV 먼저 검증 후 LangGraph 구현 시작.

**Test Diagram — Codepath Coverage:**

| 플로우 / 코드패스 | 테스트 타입 | 존재 여부 |
|----------------|-----------|---------|
| ChromaDB RAG 검색 품질 | `evaluation_runner.py` 활용 | ✅ 기존 |
| LangGraph search_courses 노드 | pytest 단위 | ❌ 필요 |
| LangGraph map_folklore 노드 | pytest (실 ChromaDB) | ❌ 필요 |
| LangGraph enrich_places 노드 (KTO API) | pytest + mock | ❌ 필요 |
| LangGraph fetch_congestion 노드 | pytest + mock | ❌ 필요 |
| LangGraph 노드 실패 → State 전이 | pytest 실패 주입 | ❌ 필요 |
| GPS 지오펜스 트리거 → 푸시 알림 | Flutter 통합 테스트 + GPX | ❌ 필요 |
| KTO API 레이트 리밋 초과 처리 | pytest + mock | ❌ 필요 |
| FastAPI rate limit 미들웨어 | pytest + httpx | ❌ 필요 |
| contentId 퍼지 매칭 정확도 | 샘플 100건 정밀도 측정 | ❌ 필요 |

---

## Decision Audit Trail

| # | Phase | 결정 | 원칙 | 근거 | 기각된 대안 |
|---|-------|------|------|------|-----------|
| 1 | CEO | Flutter 유지 | P3 (pragmatic) | GPS+TTS+백그라운드 오디오 조합에 Flutter가 최적 | Web PWA |
| 2 | CEO | 처음부터 전부 실구현 | USER OVERRIDE | 사용자가 dummy 대신 실 구현 선택 (TASTE) | dummy + 추후 연동 |
| 3 | CEO | replace/congestion 노드 asyncio 병렬화 | P5 (explicit) | 레이턴시 10~25s → SSE+병렬로 체감 개선 | 노드 제거 |
| 4 | Design | 온보딩 바텀시트 2단계 추가 | P1 (completeness) | 빈 상태 → 사용자 포기 방지 | 생략 |
| 5 | Design | TTS 코스 저장 시점 사전 생성 | P1 (completeness) | 도착 시 지연 없는 즉시 재생 | 온디맨드 |
| 6 | Design | 데모 모드 플래그 구현 | P6 (bias toward action) | 심사 10~20s 침묵 방지 | 없음 |
| 7 | Eng | Flutter KTO 직접 호출 → FastAPI 프록시 | P5 (explicit) | API 키 클라이언트 노출 방지 | 직접 호출 유지 |
| 8 | Eng | FastAPI slowapi rate limiting 추가 | P1 (completeness) | 인증 없는 엔드포인트 비용 폭발 방지 | 없음 |
| 9 | Eng | ChromaDB Railway 볼륨 마운트 필수 | P1 (completeness) | 재배포 시 벡터 DB 소실 방지 | Chroma Cloud |
| 10 | Eng | /health + UptimeRobot 핑 | P1 (completeness) | 콜드 스타트 방지 | 없음 |

---

### PHASE 1: CEO Review (2026-04-01)

### CEO Dual Voices — Consensus Table [subagent-only]

```
CEO DUAL VOICES — CONSENSUS TABLE:
═══════════════════════════════════════════════════════════════════
  Dimension                              Subagent   Codex   Consensus
  ───────────────────────────────────── ─────────── ─────── ──────────
  1. Premises valid?                     PARTIAL     N/A    PARTIAL
  2. Right problem to solve?             YES*        N/A    YES*
  3. Scope calibration correct?          OVER-SCOPED N/A    OVER-SCOPED
  4. Alternatives sufficiently explored? PARTIAL     N/A    PARTIAL
  5. Competitive/market risks covered?   MEDIUM      N/A    MEDIUM
  6. 6-month trajectory sound?           AT RISK     N/A    AT RISK
═══════════════════════════════════════════════════════════════════
*YES with repositioning note: "설화 앱" → "현장 발견 경험 앱"으로 심사 PT 프레이밍 권장
```

### Critical Findings (from Claude subagent)

**CRITICAL — Visit Jeju CSV 좌표 품질 미검증**
9,134개 코스의 GPS 좌표가 null이거나 행정구역 중심점만 있을 가능성. 전체 아키텍처 붕괴 위험.
→ 조치: CSV 즉시 다운로드, null 비율 + 좌표 정밀도 확인

**CRITICAL — KTO API 5개 키 미발급**
집중률 예측 API는 협약 기관 대상일 수 있음. 이번 주 내 5개 전부 신청 + 테스트 호출 필수.

**HIGH — 설화 위치 × Visit Jeju 코스 중첩률 미검증**
설화 위치(오름·해안·마을)와 관광 코스(식당·카페·숙소 중심)의 GPS 반경 겹침이 낮으면 핵심 컨셉이 무너짐.
→ 조치: CSV 확보 즉시, 500m 반경 교차 분석 스크립트 실행

**HIGH — LangGraph 응답 레이턴시 위험**
7개 노드 × 외부 API 호출 → 코스 추천 1회에 10~20초 예상.
→ 조치: 코스 추천 배치 캐싱 전략 또는 노드 수 축소 필요

**HIGH — MVP 스코프 과부하**
7개 LangGraph 노드 + Flutter 7화면 + iOS 백그라운드 오디오 + contentId 전처리를 5월 6일 이전 또는 10월까지 단독 개발 가능하지만 빡빡함.
→ 자동 결정: `replace_low_coverage` + `fetch_congestion` 노드를 demo 단계에서 하드코딩 더미로 대체 가능한 구조로 설계 (P5: explicit over clever)

### Not In Scope (deferred)

- 영문 관광정보 API 연동 (제안서 어필용만)
- 타 지역 RTO 확장 (제안서 어필용만)
- 멀티모달 스토리 생성 (스트레치 목표)
- RTO 특별상 요건 공식 확인 → 사용자 액션 필요

### What Already Exists (코드 레버리지)

| 서브문제 | 기존 파일 | 재사용 |
|---------|---------|--------|
| 설화 RAG 검색 | `scripts/chat_engine.py` + ChromaDB | ✅ |
| 설화 메타데이터 | `data/processed/metadata_*.jsonl` + SQLite | ✅ |
| RAG 품질 평가 | `scripts/evaluation_runner.py` | ✅ |
| GPS 좌표 | `scripts/fetch_metadata.py` (365건) | ✅ 부분 |
| 전처리 파이프라인 | `scripts/normalize_text.py` 등 | ✅ |

### Error & Rescue Registry

| 실패 | 확률 | 탐지 시점 | 복구 |
|------|------|---------|------|
| Visit Jeju CSV 좌표 null/불량 | 중간 | CSV 다운로드 즉시 | 제주관광공사 별도 API 또는 Google Places로 보완 |
| KTO API 발급 거부/지연 | 낮음 | 이번 주 | 해당 API 없이 Mock 데이터로 제안서 제출 후 발급 재시도 |
| 설화 × 코스 중첩률 < 20% | 중간 | CSV 분석 후 | 반경 확대 (500m → 2km) 또는 설화 기반 커스텀 코스 생성으로 피벗 |
| LangGraph 응답 > 10초 | 높음 | MVP 구현 후 | 배치 사전 계산 + 캐싱, 노드 병렬화 |
| iOS 백그라운드 오디오 권한 실패 | 중간 | Flutter 구현 시 | 탐험 모드 포그라운드 전용으로 데모 |

### CEO Completion Summary

- 핵심 전략: 맞음. "검증된 코스 위에 설화 RAG"는 차별화된 접근.
- 즉시 블로커 2개: Visit Jeju CSV 확보 + KTO API 5개 키 발급
- 스코프: 과부하. `replace_low_coverage`, `fetch_congestion` 노드를 데모 단계에서 더미로 운영 가능하도록 설계할 것.
- 심사 PT 프레이밍: "설화 앱" → "현장에서 장소 이야기를 발견하는 경험"으로 언어 전환 권장.

