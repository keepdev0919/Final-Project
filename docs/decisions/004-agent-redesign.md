# 004. 코스 추천 에이전트 재설계

**날짜**: 2026-04-08  
**상태**: 설계 완료 / 구현 예정

---

## 왜 재설계하는가

기존 구조는 고정 파이프라인이었음:

```
입력 → A → B → C → D → 출력  (순서 고정, LLM 거의 안 씀)
```

문제점:
- 사용자가 선택한 **일수**는 장소 개수 자르기에만 쓰임
- 사용자가 선택한 **이동수단**은 코드 어디에도 반영 안 됨
- **하루 동선이 지리적으로 엉킴** (제주 동쪽 → 서쪽 → 동쪽 왔다갔다 가능)
- 비짓제주의 9,134개 실제 검증된 코스를 활용하지 않음
- LLM이 테마 분류 한 번 외에 아무 판단도 안 함

---

## 새 에이전트가 해야 할 판단

```
1. 이 테마에 맞는 설화 장소가 제주 어느 지역에 분포해 있나?
2. 일수에 맞게 지역을 어떻게 묶을까? (1일차=동쪽, 2일차=서쪽)
3. 이동수단 기준으로 이 동선이 현실적인가? (도보면 하루 5km 반경)
4. 비짓제주 코스 중 우리 설화 장소를 지나는 코스가 있나? (동선 검증)
5. 설화 장소 사이 빈 자리에 어떤 관광지를 넣을까?
```

---

## 전체 아키텍처

### 시스템 레이어

```
[iOS 앱]
  사용자 입력 (분위기, 장소, 일수, 이동수단)
        ↓ POST /course/recommend
[백엔드 - 코스 생성 에이전트]
  LangGraph 기반, LLM이 핵심 판단 담당
        ↓
  코스 JSON 반환 (날짜별 장소 목록)
        ↓
[iOS 앱]
  코스 결과 화면에서 장소 클릭
        ↓ GET /tourist/place-detail?name=성산일출봉
[백엔드 - 장소 상세]
  KTO searchKeyword2 → contentId
  detailCommon2 → 설명글
  detailImage2  → 사진
  + 우리 DB → 이 장소 설화 텍스트
        ↓
  장소 상세 JSON 반환
```

---

## 에이전트 내부 구조 (LangGraph)

### State

```python
class AgentState(TypedDict):
    # 입력
    theme: str              # "바다해녀"
    duration_days: int      # 2
    transport: str          # "car" | "walk"

    # 중간 결과
    folklore_spots: list[dict]     # GPS 있는 설화 후보들
    filtered_spots: list[dict]     # 이동수단 필터 후
    day_plan: list[list[dict]]     # [[1일차 장소들], [2일차 장소들]]
    enriched_plan: list[list[dict]]# 비짓제주 장소 보충 후

    # 출력
    course_title: str
    course_description: str
    error: str
```

### 노드 구성

```
[1] search_folklore_with_gps
        ↓
[2] filter_by_transport
        ↓
[3] plan_days_by_region  ← LLM 판단
        ↓
[4] enrich_with_visitjeju
        ↓
[5] write_course_narrative  ← LLM 판단
        ↓
[6] finish
```

---

## 각 노드 상세 설계

### [1] search_folklore_with_gps

**역할:** ChromaDB에서 테마 관련 설화 검색 + GPS 있는 것만 필터

```
입력: theme
처리:
  - THEME_QUERIES[theme]로 ChromaDB 벡터 검색
  - distance < 0.65 필터
  - folklore_gps.json에서 GPS 좌표 조회
  - GPS 없는 설화 제외 (228개 풀 안에서만)
출력: folklore_spots (code_no, title, lat, lng, text, region)
```

> **region 필드 추가**: 위도/경도로 제주를 5개 권역으로 자동 분류
> - 북제주 (lat > 33.52): 제주시, 조천, 함덕
> - 동제주 (lng > 126.80): 성산, 표선, 세화
> - 남제주 (lat < 33.32): 서귀포, 중문, 마라도
> - 서제주 (lng < 126.40): 한경, 한림, 애월
> - 중산간 (나머지): 한라산, 오름 지역

---

### [2] filter_by_transport

**역할:** 이동수단에 따라 하루 이동 가능 범위로 장소 필터

```
입력: folklore_spots, transport, duration_days
처리:
  if transport == "car":
    - 제주 전역 허용
    - 하루 최대 이동: 100km 이내
    - 후보 장소 수: duration_days * 5개 목표
  
  if transport == "walk":
    - 한 권역 내 장소만 허용
    - 하루 최대 이동: 5km 반경
    - duration_days * 3개 목표
    - 가장 설화가 많은 권역 중심으로 집중

출력: filtered_spots
```

---

### [3] plan_days_by_region

**역할:** LLM이 장소들을 날짜별로 배분

```
입력: filtered_spots, duration_days, transport
처리:
  LLM에게 전달하는 정보:
    - 각 설화 장소의 이름, 권역, 간략 설화 내용
    - 일수, 이동수단
    - 지시: "하루에 한 권역 중심으로 묶어줘.
             이동거리 최소화. 설화 흐름이 자연스럽게."

  LLM 출력: JSON 형태
    [
      {"day": 1, "region": "동제주", "spots": [...]},
      {"day": 2, "region": "남제주", "spots": [...]}
    ]

출력: day_plan
```

**LLM이 이 노드에서 하는 판단:**
- 어떤 권역을 며칠차에 배치할지
- 권역 간 이동 순서 (인접한 권역 순서로)
- 하루 내 장소 순서 (설화 서사 흐름 고려)

---

### [4] enrich_with_visitjeju

**역할:** 비짓제주 코스 데이터에서 빈 자리 채우기

```
입력: day_plan, duration_days
처리:
  각 날짜별로:
    1. 그날 권역에서 비짓제주 코스 중
       duration_days와 비슷한 일수 코스 조회
    2. 그 코스에 포함된 장소들 추출
    3. 우리 설화 장소와 GPS가 가까운 관광지 삽입
       (설화 장소 사이 이동 중에 들를 수 있는 곳)
    4. 하루 장소 수 상한: 5개 (설화 2~3 + 관광지 2~3)

출력: enriched_plan
```

**비짓제주 코스 활용 방식:**
- 코스를 그대로 복사하는 게 아니라 "동선 검증 + 빈 자리 채우기"용
- 우리 설화 장소가 먼저, 비짓제주 장소는 사이사이 보충

---

### [5] write_course_narrative

**역할:** LLM이 코스 제목과 한 줄 설명 생성

```
입력: enriched_plan, theme, duration_days
처리:
  LLM에게 전달:
    - 날짜별 장소 목록과 각 설화 요약
    - 테마

  LLM 출력:
    - course_title: "해녀의 바다를 따라 — 제주 동부 2일"
    - course_description: "성산의 용왕 전설에서 시작해 세화
                           해녀 이야기로 이어지는 제주 동쪽 바다 여정"

출력: course_title, course_description
```

---

## 장소 상세 조회 (별도 엔드포인트)

에이전트와 분리. iOS 앱에서 장소 클릭 시 호출.

```
GET /tourist/place-detail?name={장소명}&lat={위도}&lng={경도}

처리:
  1. KTO searchKeyword2(name, areaCode=39, contentTypeId=12)
     → contentId 획득
     → 결과 중 contenttypeid=12 첫 번째 항목 선택
  2. detailCommon2(contentId) → overview (설명글)
  3. detailImage2(contentId)  → 사진 URL 목록
  4. 우리 DB에서 이 장소 설화 (lat/lng로 근접 조회)
     → 설화 제목 + 본문

응답:
  {
    "name": "성산일출봉",
    "overview": "성산일출봉은...",
    "images": ["url1", "url2"],
    "folklore": {
      "title": "성산의 용왕 이야기",
      "text": "옛날 성산 앞바다에..."
    }
  }
```

---

## 에이전트 도구 목록

| 도구 | 데이터 소스 | 역할 |
|------|------------|------|
| search_folklore | ChromaDB | 테마 기반 설화 벡터 검색 |
| get_folklore_gps | folklore_gps.json | 설화 GPS 조회 |
| get_visitjeju_courses | course_places DB | 권역·일수 기반 코스 조회 |
| get_spots_near | course_places DB | 설화 장소 근처 관광지 |
| classify_region | 계산 (위경도) | 장소를 5개 권역으로 분류 |

---

## 기존 대비 변경 요약

| 항목 | 기존 | 변경 후 |
|------|------|---------|
| 일수 활용 | 장소 수 나누기 | LLM이 권역별 날짜 배분 |
| 이동수단 활용 | 미사용 | 후보 장소 반경 필터링 |
| 동선 최적화 | Nearest Neighbor (기계적) | LLM이 서사 흐름 고려해서 배분 |
| 비짓제주 활용 | 근처 장소 단순 추가 | 동선 검증 + 빈 자리 채우기 |
| LLM 역할 | 테마 분류만 | 날짜 배분 + 코스 설명 생성 |
| GPS 없는 설화 | 검색 후 탈락 | 처음부터 228개 풀에서만 검색 |

---

## 구현 순서

1. `classify_region()` 함수 (위경도 → 5개 권역)
2. `search_folklore_with_gps` 노드 수정 (GPS 풀에서만 검색)
3. `filter_by_transport` 노드 신규
4. `plan_days_by_region` 노드 신규 (LLM 프롬프트 설계 필요)
5. `enrich_with_visitjeju` 노드 수정 (코스 조회 로직 개선)
6. `write_course_narrative` 노드 신규
7. `GET /tourist/place-detail` 엔드포인트 신규
