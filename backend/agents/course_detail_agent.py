"""코스 상세 에이전트.

course_id로 장소 목록을 조회하고, 코드가 직접 GPS 설화 매핑 처리 (LLM 환각 방지).
매핑 결과 + 스타일 힌트를 LLM에 전달해 여행 내러티브를 생성한다.

흐름:
    1. SQLite에서 course_id로 장소 목록 조회
    2. 각 장소 GPS 기준 반경 3km 내 설화 매핑 (folklore_gps.json)
    3. 매핑 결과를 LLM에 전달 → 내러티브 생성
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
from typing import Optional

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

from services.db import get_db_connection

BASE_DIR = Path(__file__).parent.parent.parent
FOLKLORE_GPS_PATH = BASE_DIR / "data" / "processed" / "folklore_gps.json"

llm = ChatOpenAI(model="gpt-4o", temperature=0.5, api_key=os.getenv("OPENAI_API_KEY"))

STYLE_DESCRIPTIONS = {
    "nature": "자연과 오름 중심 여행. 한라산, 오름, 숲, 트레킹 코스.",
    "ocean": "해변과 바다 중심 여행. 해안 절경, 해수욕, 해양 활동.",
    "food": "맛집과 카페 중심 여행. 제주 로컬 음식, 흑돼지, 해산물, 감성 카페.",
    "culture": "문화와 역사 중심 여행. 제주 역사 유적, 민속촌, 박물관.",
}

NARRATIVE_SYSTEM_PROMPT = """당신은 제주도 여행 스토리텔러입니다.

역할:
여행 코스의 장소들과 그 주변에 깃든 설화를 엮어,
여행자가 읽으면 설레는 여행 내러티브를 작성합니다.

내러티브 가이드라인:
- 전체 여행을 관통하는 주제나 흐름을 만들어주세요
- 각 장소를 방문하는 감각적인 묘사를 포함하세요
- 설화가 있는 장소는 그 이야기를 자연스럽게 녹여주세요
- 설화가 없는 장소도 분위기 있게 소개해주세요
- 전체 길이: 300~500자 내외 한국어
- 여행 팸플릿이 아닌, 이야기처럼 써주세요"""


# ─── 설화 GPS 캐시 ────────────────────────────────────────────────────────────

_folklore_gps_cache: list[dict] | None = None


def _load_folklore_gps() -> list[dict]:
    global _folklore_gps_cache
    if _folklore_gps_cache is None:
        with open(FOLKLORE_GPS_PATH, encoding="utf-8") as f:
            _folklore_gps_cache = json.load(f)
    return _folklore_gps_cache


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


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
    return [
        {
            "place_name": r["place_name"],
            "lat": r["lat"],
            "lng": r["lng"],
            "day": r["day"],
        }
        for r in rows
        if r["lat"] is not None and r["lng"] is not None
    ]


def get_course_title(course_id: str) -> tuple[str, int]:
    """SQLite에서 코스 제목 조회."""
    conn = get_db_connection()
    row = conn.execute(
        "SELECT title, duration_days FROM courses WHERE id = ?",
        (course_id,),
    ).fetchone()
    return (row["title"] if row else "", row["duration_days"] if row else 1)


def map_folklore_to_places(places: list[dict], radius_m: int = 3000) -> list[dict]:
    """각 장소 GPS 기준 반경 내 설화를 매핑한다. 코드로 처리 (LLM 환각 방지)."""
    all_folklore = _load_folklore_gps()
    result = []

    for place in places:
        lat, lng = place["lat"], place["lng"]
        nearby = []
        for f in all_folklore:
            if f.get("lat") is None or f.get("lng") is None:
                continue
            dist = _haversine_m(lat, lng, f["lat"], f["lng"])
            if dist <= radius_m:
                nearby.append({
                    "code_no": f.get("code_no", ""),
                    "title": f.get("title", ""),
                    "source_type": f.get("source_type", "legend"),
                    "summary": f.get("summary", ""),
                    "lat": f["lat"],
                    "lng": f["lng"],
                    "distance_m": round(dist),
                })
        nearby.sort(key=lambda x: x["distance_m"])
        result.append({
            **place,
            "folklore_pins": nearby[:3],  # 장소당 최대 3개
        })

    return result


def generate_narrative(places_with_folklore: list[dict], style: str, course_title: str) -> str:
    """LLM에게 매핑된 설화 데이터를 전달해 여행 내러티브 생성."""
    style_desc = STYLE_DESCRIPTIONS.get(style, style)

    # LLM에 전달할 장소+설화 요약
    place_summaries = []
    for p in places_with_folklore:
        folklore_titles = [f["title"] for f in p.get("folklore_pins", [])]
        folklore_text = f" (관련 설화: {', '.join(folklore_titles)})" if folklore_titles else " (설화 없음)"
        place_summaries.append(f"- Day {p['day']}: {p['place_name']}{folklore_text}")

    places_text = "\n".join(place_summaries)

    prompt = (
        f"코스 제목: {course_title}\n"
        f"여행 스타일: {style_desc}\n\n"
        f"방문 장소와 설화:\n{places_text}\n\n"
        f"위 코스를 여행하는 사람이 읽을 여행 내러티브를 작성해주세요."
    )

    structured_llm = llm.with_structured_output(NarrativeOutput)
    try:
        result: NarrativeOutput = structured_llm.invoke([
            SystemMessage(content=NARRATIVE_SYSTEM_PROMPT),
            HumanMessage(content=prompt),
        ])
        return result.narrative
    except Exception:
        return ""


def run_detail_agent(course_id: str, style: str) -> dict:
    """Detail 에이전트 진입점. Course 딕셔너리 반환."""
    course_title, duration_days = get_course_title(course_id)
    if not course_title:
        return {"error": f"코스를 찾을 수 없습니다: {course_id}"}

    places = get_places_for_course(course_id)
    if not places:
        return {"error": f"코스 장소 데이터가 없습니다: {course_id}"}

    places_with_folklore = map_folklore_to_places(places, radius_m=3000)
    narrative = generate_narrative(places_with_folklore, style, course_title)

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
