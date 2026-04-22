"""코스 리스트 에이전트.

흐름:
    initialize (SQL 50개 추출 → Python 설화 점수 계산 → 상위 15개 선별)
    → call_model ⇄ call_tools (LLM이 get_folklore_near_place로 심층 확인)
    → format_output (최종 3개 선택)
    → END
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
from typing import Annotated, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from langgraph.graph import END, StateGraph
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode
from pydantic import BaseModel, Field

from services.db import get_db_connection

BASE_DIR = Path(__file__).parent.parent.parent
FOLKLORE_GPS_PATH = BASE_DIR / "data" / "processed" / "folklore_gps.json"

llm = ChatOpenAI(model="gpt-4o", temperature=0.3, api_key=os.getenv("OPENAI_API_KEY"))

MAX_TOOL_CALLS = 6

# 지역 → SQL WHERE 조건 (course_places 서브쿼리용)
REGION_SQL_CONDITIONS = {
    "북부": "cp2.lat >= 33.38",
    "남부": "cp2.lat < 33.38",
    "동부": "cp2.lng >= 126.57",
    "서부": "cp2.lng < 126.57",
}

# 내부 카테고리명 → 설명 텍스트 (LLM 컨텍스트용)
CATEGORY_QUERIES = {
    "무속신화·신격 전승": (
        "제주 무속신화 본풀이 신격 전승 이야기. "
        "천지왕 설문대할망 삼성혈 탄생 신화 당오름 성소. "
        "본향당 당신 심방 굿 좌정 옥황상제 서천꽃밭 영등신 세경신. "
        "신이 인간 세상에 내려와 마을과 당에 자리 잡는 서사."
    ),
    "생활민담·교훈담": (
        "제주 생활민담 교훈담 해학 이야기. "
        "재치 지혜 욕심 벌 교훈 권선징악 속고 속이는 이야기. "
        "일상 속 인간의 행동과 선택이 드러나는 민담. "
        "마을 사람들의 삶 사랑 이별 제주 생활 풍속."
    ),
    "마을 공동체 전승": (
        "제주 마을 공동체 전승 이야기. "
        "본향당 마을신 당제 동네 사람들이 함께 믿고 전해온 전승. "
        "공동체 기억과 마을 수호에 관한 설화."
    ),
    "해양·어촌 전승": (
        "제주 바다 어촌 해양 전승 이야기. "
        "해녀 잠수 물질 어부 용왕 영등신 풍어제 바당과 해안 마을. "
        "바다에서 살아가는 제주 사람들의 삶과 신앙."
    ),
    "초자연 존재담": (
        "제주 초자연 존재 이야기. "
        "도체비 귀신 혼령 요괴 변신 둔갑 신비하고 으스스한 존재. "
        "밤과 경계 공간에서 벌어지는 기이한 설화."
    ),
}

SYSTEM_PROMPT = """당신은 제주 설화 여행 코스 큐레이터입니다.

역할:
설화 점수로 사전 선별된 코스 후보를 받아,
사용자 취향과 가장 잘 맞는 코스 3개를 최종 선택합니다.

작업 순서:
1. 전달받은 후보 목록과 각 코스의 설화 점수·설화 목록을 확인합니다.
2. 점수가 높은 코스를 우선 검토하되, 필요하면 get_folklore_near_place로 특정 장소의 설화를 더 확인합니다.
3. 설화 연결이 풍부하고 서로 분위기가 다른 코스 3개를 최종 선택합니다.

중요 규칙:
- 설화 점수 0인 코스는 점수가 있는 코스를 모두 검토한 뒤에만 선택하세요.
- 3개 코스가 서로 다른 지역·분위기를 갖도록 다양하게 구성하세요.
- get_folklore_near_place 호출 시 categories는 사용자 취향 카테고리를 점수 높은 순으로 전달하세요.
- GPS 좌표는 절대 직접 만들지 마세요. 도구에서 받은 값만 사용하세요."""


# ─── 설화 GPS 캐시 ─────────────────────────────────────────────────────────────

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


# ─── Python 사전 선별 ─────────────────────────────────────────────────────────

def _map_folklore_for_place(lat: float, lng: float, radius_m: int = 3000) -> list[dict]:
    """장소 GPS 기준 반경 내 설화 목록 반환 (거리순)."""
    all_folklore = _load_folklore_gps()
    nearby = []
    for f in all_folklore:
        if f.get("lat") is None or f.get("lng") is None:
            continue
        dist = _haversine_m(lat, lng, f["lat"], f["lng"])
        if dist <= radius_m:
            nearby.append({
                "code_no": f.get("code_no", ""),
                "title": f.get("title", ""),
                "final_category": f.get("final_category", ""),
                "distance_m": round(dist),
            })
    nearby.sort(key=lambda x: x["distance_m"])
    return nearby[:3]


def _fetch_and_score_courses(
    region: str,
    duration_days: int,
    category_scores: dict[str, int],
    pool_size: int = 50,
    top_n: int = 15,
) -> list[dict]:
    """SQL에서 pool_size개 추출 → 설화 가중치 점수 계산 → 상위 top_n개 반환."""
    conn = get_db_connection()
    duration_min = max(1, duration_days - 1)
    duration_max = duration_days + 1
    min_places = max(2, duration_days * 2)

    region_cond = REGION_SQL_CONDITIONS.get(region)

    if region_cond:
        sql = f"""
        SELECT id, title, duration_days FROM (
            SELECT c.id, c.title, c.duration_days,
                   (SELECT COUNT(*) FROM course_places cp2
                    WHERE cp2.course_id = c.id AND cp2.in_jeju = 1
                      AND cp2.lat IS NOT NULL AND cp2.lng IS NOT NULL
                      AND {region_cond}) AS region_count,
                   (SELECT COUNT(*) FROM course_places cp2
                    WHERE cp2.course_id = c.id AND cp2.in_jeju = 1
                      AND cp2.lat IS NOT NULL AND cp2.lng IS NOT NULL) AS total_count
            FROM courses c
            WHERE c.duration_days BETWEEN ? AND ?
              AND c.place_count >= ?
        )
        WHERE total_count > 0
          AND region_count * 2 >= total_count
        ORDER BY RANDOM()
        LIMIT ?
        """
        rows = conn.execute(sql, (duration_min, duration_max, min_places, pool_size)).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT id, title, duration_days
            FROM courses
            WHERE duration_days BETWEEN ? AND ?
              AND place_count >= ?
            ORDER BY RANDOM()
            LIMIT ?
            """,
            (duration_min, duration_max, min_places, pool_size),
        ).fetchall()

    scored = []
    for row in rows:
        place_rows = conn.execute(
            """
            SELECT place_name, lat, lng, day
            FROM course_places
            WHERE course_id = ? AND in_jeju = 1
            ORDER BY day, start_time
            """,
            (row["id"],),
        ).fetchall()

        places = []
        for p in place_rows:
            if p["lat"] is None or p["lng"] is None:
                continue
            folklore_pins = _map_folklore_for_place(p["lat"], p["lng"])
            places.append({
                "place_name": p["place_name"],
                "lat": p["lat"],
                "lng": p["lng"],
                "day": p["day"],
                "folklore_pins": folklore_pins,
            })

        if not places:
            continue

        folklore_score = sum(
            category_scores.get(pin["final_category"], 0)
            for p in places
            for pin in p["folklore_pins"]
        )

        scored.append({
            "id": row["id"],
            "title": row["title"],
            "duration_days": row["duration_days"],
            "places": places,
            "folklore_score": folklore_score,
        })

    scored.sort(key=lambda x: -x["folklore_score"])
    return scored[:top_n]


# ─── 도구 (LLM 전용) ──────────────────────────────────────────────────────────

@tool
def get_folklore_near_place(
    lat: float, lng: float, categories: list[str], radius_m: int = 3000
) -> str:
    """특정 GPS 좌표 주변에서 카테고리에 맞는 설화를 검색합니다.

    Args:
        lat: 위도
        lng: 경도
        categories: 우선 탐색할 설화 카테고리 목록 (점수 높은 순).
                    예: ["무속신화·신격 전승", "마을 공동체 전승"]
        radius_m: 검색 반경 미터 (기본 3000, 설화 없으면 5000으로 재시도)

    Returns:
        인근 설화 목록 JSON. 각 항목: code_no, title, source_type, final_category, distance_m
    """
    all_folklore = _load_folklore_gps()
    cat_rank = {cat: i for i, cat in enumerate(categories)}

    nearby: list[dict] = []
    for f in all_folklore:
        if f.get("lat") is None or f.get("lng") is None:
            continue
        dist = _haversine_m(lat, lng, f["lat"], f["lng"])
        if dist > radius_m:
            continue
        cat = f.get("final_category", "")
        nearby.append({
            "code_no": f["code_no"],
            "title": f.get("title", ""),
            "source_type": f.get("source_type", "legend"),
            "final_category": cat,
            "distance_m": round(dist),
            "_rank": cat_rank.get(cat, len(categories)),
        })

    nearby.sort(key=lambda x: (x.pop("_rank"), x["distance_m"]))
    return json.dumps(nearby[:10], ensure_ascii=False)


# ─── State ───────────────────────────────────────────────────────────────────

class ListAgentState(TypedDict):
    messages: Annotated[list, add_messages]
    region: str
    category_scores: dict[str, int]
    duration_days: int
    candidates: list[dict]   # initialize에서 채워지는 사전 선별 코스
    result_courses: list[dict]
    error: str


# ─── Structured Output ────────────────────────────────────────────────────────

class CourseSelection(BaseModel):
    course_ids: list[str] = Field(description="선택된 코스 id 3개", min_length=1, max_length=3)


# ─── 노드 ────────────────────────────────────────────────────────────────────

_tools = [get_folklore_near_place]
_tool_node = ToolNode(_tools)
_llm_with_tools = llm.bind_tools(_tools)


def _scores_to_theme_text(scores: dict[str, int]) -> str:
    sorted_cats = sorted(scores.items(), key=lambda x: -x[1])
    lines = []
    for cat, score in sorted_cats:
        if score > 0:
            query = CATEGORY_QUERIES.get(cat, cat)
            lines.append(f"- {cat} ({score}점): {query[:80]}")
    return "\n".join(lines) if lines else "특별한 취향 없음 (다양한 설화 포함)"


def initialize(state: ListAgentState) -> dict:
    category_scores = state.get("category_scores", {})
    candidates = _fetch_and_score_courses(
        region=state["region"],
        duration_days=state["duration_days"],
        category_scores=category_scores,
    )

    theme_text = _scores_to_theme_text(category_scores)

    candidate_lines = []
    for c in candidates:
        place_names = " → ".join(p["place_name"] for p in c["places"][:4])
        folklore_items = []
        for p in c["places"]:
            for pin in p.get("folklore_pins", []):
                folklore_items.append(f"{pin['title']}[{pin['final_category']}]")
        folklore_text = " / ".join(folklore_items[:5]) if folklore_items else "설화 없음"
        candidate_lines.append(
            f"- id={c['id']} | 설화점수={c['folklore_score']} | {c['title']}\n"
            f"  장소: {place_names}\n"
            f"  인근 설화: {folklore_text}"
        )

    candidates_text = "\n".join(candidate_lines) if candidate_lines else "후보 없음"

    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=(
            f"제주 여행 코스 3개를 선택해주세요.\n\n"
            f"조건:\n"
            f"- 지역: {state['region']}\n"
            f"- 설화 취향 (점수 높은 순):\n{theme_text}\n"
            f"- 여행 일수: {state['duration_days']}일\n\n"
            f"[사전 선별 후보 {len(candidates)}개 — 설화 점수 내림차순]\n"
            f"{candidates_text}\n\n"
            f"위 후보 중 취향에 가장 잘 맞는 코스 3개를 선택해주세요. "
            f"필요하면 get_folklore_near_place로 특정 장소의 설화를 더 확인하세요."
        )),
    ]
    return {"messages": messages, "candidates": candidates}


def call_model(state: ListAgentState) -> dict:
    response = _llm_with_tools.invoke(state["messages"])
    return {"messages": [response]}


def _count_tool_calls(messages: list) -> int:
    return sum(1 for m in messages if hasattr(m, "tool_calls") and m.tool_calls)


def should_continue(state: ListAgentState) -> Literal["tools", "format_output"]:
    last = state["messages"][-1]
    if _count_tool_calls(state["messages"]) >= MAX_TOOL_CALLS:
        return "format_output"
    if hasattr(last, "tool_calls") and last.tool_calls:
        return "tools"
    return "format_output"


def format_output(state: ListAgentState) -> dict:
    structured_llm = llm.with_structured_output(CourseSelection)

    candidates = state.get("candidates", [])
    candidate_map = {c["id"]: c for c in candidates}

    valid_courses_text = "\n".join(
        f"  - id={c['id']}, title={c['title']}, 설화점수={c['folklore_score']}"
        for c in candidates
    )

    scores = state.get("category_scores", {})
    sorted_cats = sorted(scores.items(), key=lambda x: -x[1])
    scores_text = ", ".join(f"{c}({s}점)" for c, s in sorted_cats if s > 0) or "없음"

    extraction_prompt = (
        f"아래 후보 중 설화 취향에 가장 잘 맞는 코스 3개의 id를 골라주세요.\n\n"
        f"설화 취향: {scores_text}\n\n"
        f"[후보 목록 — 반드시 이 목록의 id만 사용]\n{valid_courses_text}\n\n"
        f"규칙: course_ids에는 위 목록의 id 값만 넣으세요. 서로 다른 분위기의 코스로 구성하세요."
    )

    try:
        selection: CourseSelection = structured_llm.invoke(
            [HumanMessage(content=extraction_prompt)]
        )
        courses = []
        for cid in selection.course_ids:
            course = candidate_map.get(cid)
            if course:
                courses.append({
                    "id": course["id"],
                    "title": course["title"],
                    "duration_days": course["duration_days"],
                    "places": [
                        {
                            "place_name": p["place_name"],
                            "lat": p["lat"],
                            "lng": p["lng"],
                            "day": p["day"],
                        }
                        for p in course.get("places", [])
                        if p.get("lat") is not None and p.get("lng") is not None
                    ],
                })
        if courses:
            return {"result_courses": courses, "error": ""}
        else:
            return {"result_courses": [], "error": "선택된 코스 id가 후보 목록에 없습니다."}
    except Exception as e:
        return {"result_courses": [], "error": f"코스 리스트 생성 실패: {e}"}


# ─── 그래프 조립 ──────────────────────────────────────────────────────────────

def build_list_graph():
    g = StateGraph(ListAgentState)
    g.add_node("initialize", initialize)
    g.add_node("call_model", call_model)
    g.add_node("call_tools", _tool_node)
    g.add_node("format_output", format_output)

    g.set_entry_point("initialize")
    g.add_edge("initialize", "call_model")
    g.add_conditional_edges(
        "call_model",
        should_continue,
        {"tools": "call_tools", "format_output": "format_output"},
    )
    g.add_edge("call_tools", "call_model")
    g.add_edge("format_output", END)

    return g.compile()


course_list_graph = build_list_graph()
