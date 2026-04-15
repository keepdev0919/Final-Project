# 백엔드 구현 계획: 코스 에이전트 재설계 및 버그 수정

**날짜**: 2026-04-15
**브랜치**: main
**담당**: keepdev0919

---

## 목표

현재 백엔드의 두 가지 핵심 문제를 해결한다.

1. **`tourist_info_cache` 테이블 미생성** — `tourist.py`에서 사용하는 테이블이 DB에 없어 런타임 500 에러 발생
2. **코스 에이전트 흐름 불일치** — 설계 문서의 "Visit Jeju 실제 코스 선별 + 설화 매핑" 방식이 아닌, RAG 검색 후 직접 경로를 구성하는 방식으로 구현되어 있음

---

## 현재 상태

### 완성된 것
- `courses` 테이블: Visit Jeju 여행일정 9,134개 (SQLite)
- `course_places` 테이블: 장소 146,508개 (GPS 포함)
- ChromaDB: 설화·민담 505개 벡터 인덱스 (완성)
- KTO API 프록시 3개 (`/tourist/info`, `/tourist/related`, `/tourist/congestion`)
- ReAct 챗봇 에이전트 (`/chat`)

### 현재 `course_agent.py` 흐름 (잘못됨)
```
understand_interest → search_folklore (RAG) → extract_locations (GPS JSON)
  → build_route (greedy nearest neighbor) → enrich_with_visitjeju → fill_gaps → finish
```

### 설계 문서 목표 흐름
```
analyze_request → search_courses (Visit Jeju DB 쿼리) → map_folklore (RAG 매핑)
  → replace_low_coverage → fetch_congestion → rank_courses → validate_course → finish
```

---

## 구현 항목

### Task 1: `tourist_info_cache` 테이블 자동 생성

**파일**: `backend/services/db.py`

`get_db_connection()` 초기화 시 테이블이 없으면 생성:

```sql
CREATE TABLE IF NOT EXISTS tourist_info_cache (
    content_id TEXT PRIMARY KEY,
    name       TEXT,
    address    TEXT,
    phone      TEXT,
    category   TEXT,
    cached_at  REAL
);
```

---

### Task 2: 코스 에이전트 핵심 흐름 재설계

**파일**: `backend/agents/course_agent.py`

#### 새 State 구조

```python
class AgentState(TypedDict):
    user_input: str
    theme: str
    category_scores: dict[str, int]
    selected_categories: list[str]
    duration_days: int
    transport: str
    region: str                      # 제주 지역 (선택적)
    candidate_courses: list[dict]    # Visit Jeju 후보 코스 목록
    folklore_mapped_courses: list[dict]  # 설화 매핑된 코스 목록
    ranked_courses: list[dict]       # 혼잡도 기반 랭킹 결과
    final_course: dict               # 최종 선택 코스
    course_title: str
    retry_count: int
    error: str
```

#### 새 노드 구성

**`analyze_request`** (기존 `understand_interest` 대체)
- 사용자 입력에서 category_scores, duration_days, transport 파악
- region 파악 (없으면 전체 제주)

**`search_courses`** (신규)
- SQLite `courses` + `course_places` 테이블에서 duration_days 조건에 맞는 코스 선별
- transport 조건 반영 (도보 코스는 하루 장소 수 제한 등)
- 최대 10개 후보 반환

```python
def search_courses(state: AgentState) -> AgentState:
    conn = get_db_connection()
    candidates = conn.execute("""
        SELECT c.id, c.title, c.duration_days,
               GROUP_CONCAT(cp.place_name || '|' || cp.lat || '|' || cp.lng || '|' || cp.day, ';;') as places_raw
        FROM courses c
        JOIN course_places cp ON c.id = cp.course_id
        WHERE c.duration_days BETWEEN ? AND ?
          AND cp.in_jeju = 1
          AND cp.lat IS NOT NULL
        GROUP BY c.id
        ORDER BY RANDOM()
        LIMIT 10
    """, (state["duration_days"], state["duration_days"] + 1)).fetchall()
    ...
```

**`map_folklore`** (신규)
- 각 후보 코스의 장소별 반경 1km 내 설화·민담 RAG 매핑
- 장소 GPS → `folklore_gps.json` 에서 인근 설화 조회
- 설화 커버리지 계산 (매핑된 장소 수 / 전체 장소 수)

**`replace_low_coverage`** (신규)
- 설화 커버리지 < 0.3인 장소는 `/tourist/related` 데이터에서 대안 장소 탐색
- KTO `areaCd`/`signguCd` 기반 연관 관광지 활용

**`fetch_congestion`** (신규)
- 코스의 각 장소에 대해 `/tourist/congestion` API 호출
- 혼잡도 점수 산출 (cnctrRate 기반)
- 데이터 없는 장소는 기본값 0.5 적용

**`rank_courses`** (신규)
- 점수 = (설화 커버리지 × 0.7) + (혼잡도 역수 × 0.3)
- 상위 1개 코스 선택

**`validate_course`** (신규)
- 총 장소 수 ≥ 2 검증
- 설화 매핑 장소 ≥ 1 검증
- 실패 시 retry_count < 3이면 `search_courses`로 재시도 (조건 완화)
- 실패 3회 시 현재 최선 코스 반환

**`finish`** (기존 유지, 약간 수정)
- 코스 제목 생성 (선택된 categories 기반)

#### 그래프 구성

```python
g.set_entry_point("analyze_request")
g.add_edge("analyze_request", "search_courses")
g.add_edge("search_courses", "map_folklore")
g.add_edge("map_folklore", "replace_low_coverage")
g.add_edge("replace_low_coverage", "fetch_congestion")
g.add_edge("fetch_congestion", "rank_courses")
g.add_edge("rank_courses", "validate_course")
g.add_conditional_edges("validate_course", _route_validate, {
    "retry": "search_courses",
    "finish": "finish",
})
g.add_edge("finish", END)
```

---

### Task 3: `Course` 응답 스키마에 `source_course_id` 추가

**파일**: `backend/models/schemas.py`, `backend/routers/course.py`

```python
class Course(BaseModel):
    id: str
    source_course_id: str    # Visit Jeju 원본 코스 ID
    title: str
    duration_days: int
    places: list[CoursePlace]
    estimated_minutes: int
```

---

### Task 4: `CoursePlace`에 `congestion_level` 배지 추가

**파일**: `backend/models/schemas.py`

```python
class CoursePlace(BaseModel):
    name: str
    lat: float
    lng: float
    day: int
    start_time: Optional[str] = None
    folklore_pins: list[Pin] = []
    congestion_level: Optional[str] = None  # "low" | "medium" | "high"
    congestion_rate: Optional[float] = None
```

---

## 영향받는 파일

- `backend/services/db.py` — tourist_info_cache 테이블 생성
- `backend/agents/course_agent.py` — 전체 재설계
- `backend/models/schemas.py` — Course, CoursePlace 스키마 업데이트
- `backend/routers/course.py` — 새 state 필드 매핑

## 영향받지 않는 파일 (변경 없음)

- `backend/routers/chat.py` — ReAct 챗봇 유지
- `backend/routers/pins.py` — GPS 핀 조회 유지
- `backend/routers/tts.py` — TTS API 유지
- `backend/routers/tourist.py` — KTO 프록시 유지
- `backend/main.py` — 라우터 등록 유지

---

## 스코프 밖 (이번 구현 제외)

- `enrich_places` 노드 (contentId 매핑 전처리 필요, 설계 우선순위 6번)
- TTS 사전 생성 (코스 저장 시점 일괄 생성)
- `/story/generate` 엔드포인트 (스트레치 목표)

---

## 테스트 전략

- Task 1: DB 초기화 후 `tourist.py` 의 INSERT 쿼리 정상 실행 확인
- Task 2: `POST /course/recommend` 호출 → Visit Jeju 실제 코스 ID가 응답에 포함되는지 확인
- Task 3: `source_course_id` 필드 응답 포함 확인
- Task 4: `congestion_level` 배지 포함 확인
