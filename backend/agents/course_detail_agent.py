"""코스 상세 에이전트.

course_id로 장소 목록과 코스 제목을 조회해 Course 딕셔너리를 만든다.
LLM 없이 DB 조회만으로 동작한다.

## 설화 의존 제거 (2026-08-13)

이전에는 `place_folklore_mapping`에서 장소별 설화를 가져와 붙이고, 그 설화를 엮어
LLM으로 여행 내러티브를 생성했다. 코스 추천에서 설화를 분리하기로 결정해 둘 다 제거했다
(근거는 `attach_empty_folklore_pins` 문서 참조).

`folklore_pins`와 `narrative` **필드는 남긴다** — iOS 모델과 Pydantic 스키마가
요구하기 때문이다. 필드 제거는 단계 1의 설화 전면 제거와 함께 한다.
"""
from __future__ import annotations

import os
from pathlib import Path

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

from services.db import get_db_connection

BASE_DIR = Path(__file__).parent.parent.parent

llm = ChatOpenAI(model="gpt-4o", temperature=0.5, api_key=os.getenv("OPENAI_API_KEY"))

CATEGORY_DESCRIPTIONS = {
    "무속신화·신격 전승": "신이 마을에 내려오는 이야기. 본향당·당신·심방·굿·좌정 중심의 무속신화.",
    "생활민담·교훈담": "재치와 교훈이 담긴 이야기. 권선징악과 생활 속 지혜의 민담.",
    "마을 공동체 전승": "마을 사람들이 함께 전해온 이야기. 본향당·마을신·당제 중심의 공동체 전승.",
    "해양·어촌 전승": "바다와 어촌의 이야기. 해녀·어부·용왕·영등신의 해양 전승.",
    "초자연 존재담": "도체비·귀신·혼령 등 으스스하고 기이한 초자연 존재의 설화.",
}

NARRATIVE_SYSTEM_PROMPT = """당신은 제주도 여행 스토리텔러입니다.

역할:
여행 코스의 장소들과 그 주변에 깃든 설화를 엮어,
여행자가 읽으면 이 코스를 걷고 싶어지는 한두 문장을 씁니다.

내러티브 가이드라인:
- 반드시 2문장 이내, 60~90자 한국어
- 첫 문장: 이 여정을 관통하는 설화적 분위기나 주제
- 둘째 문장: 여행자를 초대하는 감각적 표현
- 관광 안내문 느낌 금지. 이야기처럼 써주세요"""




# ─── Structured Output ────────────────────────────────────────────────────────

class NarrativeOutput(BaseModel):
    narrative: str = Field(description="코스 전체를 관통하는 여행 내러티브 텍스트")


# ─── 핵심 함수 ────────────────────────────────────────────────────────────────

def get_places_for_course(course_id: str) -> list[dict]:
    """SQLite에서 코스 장소 목록 조회."""
    conn = get_db_connection()
    rows = conn.execute(
        """
        SELECT place_name, lat, lng, day
        FROM course_places
        WHERE course_id = ? AND in_jeju = 1
        ORDER BY day, start_time
        """,
        (course_id,),
    ).fetchall()
    seen: set[tuple] = set()
    result = []
    for r in rows:
        if r["lat"] is None or r["lng"] is None:
            continue
        key = (r["place_name"], r["day"])
        if key in seen:
            continue
        seen.add(key)
        result.append({
            "place_name": r["place_name"],
            "lat": r["lat"],
            "lng": r["lng"],
            "day": r["day"],
        })
    return result


def get_course_title(course_id: str) -> tuple[str, int]:
    """코스 제목·일수 조회.

    **`curated_courses`를 먼저 본다.** 원본 `courses.title`은 비짓제주 사용자가 쓴
    개인 메모라 그대로 노출할 수 없다 — "^^", "z", "우리의 첫 비행기 여행♥".
    `build_curated_courses.py`가 `{지역} {일수}일 · {대표장소} 외 N곳` 형태로 생성해
    저장해 두므로 그것을 쓴다.

    이 조회가 원본을 보면 목록과 상세의 제목이 달라진다 — 목록은 curated 제목을,
    상세는 원본 제목을 보여주는 불일치가 실제로 발생했다(2026-08-13 수정).

    큐레이션에 없는 코스(직접 저장 등)는 원본으로 폴백한다.
    """
    conn = get_db_connection()
    row = conn.execute(
        "SELECT title, duration_days FROM curated_courses WHERE id = ?",
        (course_id,),
    ).fetchone()
    if row:
        return (row["title"], row["duration_days"] or 1)

    row = conn.execute(
        "SELECT title, duration_days FROM courses WHERE id = ?",
        (course_id,),
    ).fetchone()
    return (row["title"] if row else "", row["duration_days"] if row else 1)


def attach_empty_folklore_pins(places: list[dict]) -> list[dict]:
    """장소 목록에 빈 `folklore_pins`를 붙인다.

    설화 매핑을 2026-08-13에 제거했다. 이전에는 `place_folklore_mapping`을 조회해
    장소마다 설화 3개를 붙였다(`map_folklore_to_places`). 제거 이유:

    - 코스는 "어디를 갈지", 설화는 "그 장소의 이야기"다. 코스 추천에 넣을 근거가 없다
    - 장소에 강하게 얽힌 설화가 실제로 거의 없다 (설화-장소 매핑 작업에서 확인)
    - 설화는 로컬 파일 데이터라 공모전 데이터 활용 점수에 기여하지 않는다

    ⚠️ `folklore_pins` 키 자체는 남긴다 — iOS `CoursePlace`가 이 필드를 디코딩하고,
    Pydantic 스키마(`models/schemas.py`의 `CoursePlace.folklore_pins`)도 요구한다.
    필드를 없애는 것은 iOS 모델 변경을 수반하므로 단계 1의 설화 전면 제거와 함께 한다.
    """
    return [{**place, "folklore_pins": []} for place in places]


def run_detail_agent(course_id: str, category_scores: dict[str, int]) -> dict:
    """Detail 에이전트 진입점. Course 딕셔너리 반환."""
    course_title, duration_days = get_course_title(course_id)
    if not course_title:
        return {"error": f"코스를 찾을 수 없습니다: {course_id}"}

    places = get_places_for_course(course_id)
    if not places:
        return {"error": f"코스 장소 데이터가 없습니다: {course_id}"}

    places_with_folklore = attach_empty_folklore_pins(places)
    # 내러티브는 설화를 엮어 만들던 것이라 함께 제거했다. 필드는 스키마 호환을 위해
    # 빈 문자열로 유지한다 — iOS Course 모델이 narrative를 디코딩한다.
    narrative = ""

    return {
        "id": course_id,
        "title": course_title,
        "duration_days": duration_days,
        "places": places_with_folklore,
        "narrative": narrative,
        "error": "",
    }

# eager init — FastAPI worker 시작 시점에 DB 커넥션 확보
get_db_connection()
