# TODOS

## TODO-001: 레거시 course_agent.py + /course/recommend 엔드포인트 제거

**What:** `backend/agents/course_agent.py` (445줄)과 `backend/routers/course.py`의 `/course/recommend` 엔드포인트 삭제.

**Why:** iOS TasteDiscoveryView는 신규 2-단계 API(`/course/list` + `/course/detail`)만 사용한다. 레거시 에이전트는 사용되지 않으면서 코드베이스 복잡도만 높이고, 신규 개발자가 "어떤 에이전트를 봐야 하나"를 혼동하게 만든다.

**Pros:** 코드 445줄 감소, 시스템 이해 단순화, 레거시 의존성(ChromaDB 쿼리) 분리.

**Cons:** 외부에서 `/course/recommend`를 직접 호출하는 코드가 있으면 깨짐. 제거 전 grep으로 확인 필요.

**Context:** plan-eng-review(2026-04-21)에서 발견. 현재 course_agent.py는 구형 설화 카테고리 기반 추천 방식으로, April 15 재설계 이후 사용되지 않는다.

**Depends on / blocked by:** iOS 빌드에서 CourseAPI.recommend()가 완전히 unused 상태임을 확인 후 제거.

---

## TODO-002: GPS 없는 설화를 코스 내러티브에 포함

**What:** `data/processed/folklore_gps.json` (228개 GPS 설화)에 없는 ~372개 설화를 코스 내러티브 생성에 활용할 방법 추가.

**Why:** 전체 설화 ~600개 중 GPS가 없는 설화가 60%를 차지한다. 코스 내 장소 이름 또는 지역명으로 텍스트 매핑하면 내러티브 품질이 크게 높아진다. 현재는 GPS 반경 3km 이내 설화만 내러티브에 녹여지므로 일부 코스는 설화 없는 내러티브가 생성된다.

**Pros:** 설화 커버리지 228개 → ~600개. 내러티브 풍부도 향상.

**Cons:** GPS 없는 설화는 "제주시 한림읍" 같은 행정구역 텍스트로만 연결 가능해서 정확도 낮음. 잘못된 매핑이 오히려 내러티브를 오염시킬 수 있음. 별도 매핑 파이프라인 필요.

**Context:** plan-eng-review(2026-04-21)에서 제안. scripts/derive_non_gps_folklore_notes.py 이미 존재 — 기존 스크립트 활용 가능성 확인.

**Depends on / blocked by:** scripts/derive_non_gps_folklore_notes.py 결과물 검토 후 진행.
