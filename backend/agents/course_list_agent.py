"""코스 리스트 에이전트.

설화 테마 기반으로 Visit Jeju DB에서 후보 코스를 뽑고,
LLM이 get_folklore_near_place로 설화 연결이 풍부한 코스 3개를 선택한다.

흐름:
    initialize → call_model ⇄ call_tools (ReAct 루프) → format_output → END
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

from services.db import get_chroma_collection, get_db_connection, embed_query

BASE_DIR = Path(__file__).parent.parent.parent
FOLKLORE_GPS_PATH = BASE_DIR / "data" / "processed" / "folklore_gps.json"

llm = ChatOpenAI(model="gpt-4o", temperature=0.3, api_key=os.getenv("OPENAI_API_KEY"))

MAX_TOOL_CALLS = 8

# 지역 → SQL WHERE 조건 (course_places 서브쿼리용)
REGION_SQL_CONDITIONS = {
    "북부": "cp2.lat >= 33.38",
    "남부": "cp2.lat < 33.38",
    "동부": "cp2.lng >= 126.57",
    "서부": "cp2.lng < 126.57",
}

# 내부 카테고리명 → ChromaDB 검색 쿼리 (gps-folklore-final 5개 카테고리 기준)
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
사용자의 설화 취향에 맞는 제주 여행 코스 3개를 선택합니다.
Visit Jeju의 실제 여행 경로 중, 선택한 설화 테마와 가장 잘 연결되는 코스를 고릅니다.

작업 순서:
1. search_jeju_courses 도구로 코스 후보를 가져옵니다.
2. 후보 중 제목/장소 이름으로 봤을 때 설화 테마와 어울릴 것 같은 코스를 2~3개 추립니다.
3. 추린 코스의 주요 장소에 대해 get_folklore_near_place 도구로 인근 설화를 확인합니다.
4. 설화 연결이 가장 풍부한 코스 3개를 최종 선택합니다.

중요 규칙:
- 설화가 하나라도 있는 코스를 설화가 없는 코스보다 우선합니다.
- 설화가 없는 장소는 반경을 5000m로 늘려 get_folklore_near_place를 다시 호출하세요.
- 3개 코스가 서로 다른 지역/분위기를 갖도록 다양하게 구성하세요.
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


# ─── 도구 ────────────────────────────────────────────────────────────────────

@tool
def search_jeju_courses(duration_days: int, region: str) -> str:
    """Visit Jeju DB에서 지역·기간 조건에 맞는 코스 후보를 가져옵니다.

    Args:
        duration_days: 여행 일수 (1~5)
        region: 지역 (동부 | 서부 | 남부 | 북부 | 전체)

    Returns:
        코스 후보 목록 JSON. 각 코스: id, title, duration_days,
        places[{place_name, lat, lng, day}]
    """
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
        LIMIT 15
        """
    else:
        sql = """
        SELECT id, title, duration_days
        FROM courses
        WHERE duration_days BETWEEN ? AND ?
          AND place_count >= ?
        ORDER BY RANDOM()
        LIMIT 15
        """

    rows = conn.execute(sql, (duration_min, duration_max, min_places)).fetchall()

    courses = []
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

        places = [
            {"place_name": p["place_name"], "lat": p["lat"], "lng": p["lng"], "day": p["day"]}
            for p in place_rows
            if p["lat"] is not None and p["lng"] is not None
        ]

        if places:
            courses.append({
                "id": row["id"],
                "title": row["title"],
                "duration_days": row["duration_days"],
                "places": places,
            })

    return json.dumps(courses, ensure_ascii=False)


@tool
def get_folklore_near_place(lat: float, lng: float, query: str, radius_m: int = 3000) -> str:
    """특정 GPS 좌표 주변에서 테마와 관련된 설화를 ChromaDB로 검색합니다.

    Args:
        lat: 위도
        lng: 경도
        query: 설화 검색 키워드 (테마, 분위기 관련 한국어 문장)
        radius_m: 검색 반경 미터 (기본 3000, 설화 없으면 5000으로 재시도)

    Returns:
        인근 관련 설화 목록 JSON. 각 항목: code_no, title, source_type, distance_m
    """
    collection = get_chroma_collection()
    rag_results = collection.query(
        query_embeddings=[embed_query(query)],
        n_results=min(60, collection.count()),
        include=["metadatas", "distances"],
    )

    relevant_code_nos: set[str] = set()
    for meta, dist in zip(rag_results["metadatas"][0], rag_results["distances"][0]):
        if dist < 0.70:
            code_no = meta.get("code_no", "")
            if code_no:
                relevant_code_nos.add(code_no)

    all_folklore = _load_folklore_gps()
    nearby: list[dict] = []
    for f in all_folklore:
        if f.get("code_no") not in relevant_code_nos:
            continue
        if f.get("lat") is None or f.get("lng") is None:
            continue
        dist = _haversine_m(lat, lng, f["lat"], f["lng"])
        if dist <= radius_m:
            nearby.append({
                "code_no": f["code_no"],
                "title": f.get("title", ""),
                "source_type": f.get("source_type", "legend"),
                "distance_m": round(dist),
            })

    nearby.sort(key=lambda x: x["distance_m"])
    return json.dumps(nearby[:10], ensure_ascii=False)


# ─── State ───────────────────────────────────────────────────────────────────

class ListAgentState(TypedDict):
    messages: Annotated[list, add_messages]
    region: str
    category_scores: dict[str, int]
    duration_days: int
    result_courses: list[dict]
    error: str


# ─── Structured Output ────────────────────────────────────────────────────────

class CourseSelection(BaseModel):
    """LLM이 선택하는 코스 ID 목록 (GPS 없음, id만)"""
    course_ids: list[str] = Field(description="선택된 코스 id 3개", min_length=1, max_length=3)


# ─── 노드 ────────────────────────────────────────────────────────────────────

_tools = [search_jeju_courses, get_folklore_near_place]
_tool_node = ToolNode(_tools)
_llm_with_tools = llm.bind_tools(_tools)


def _scores_to_theme_text(scores: dict[str, int]) -> str:
    sorted_cats = sorted(scores.items(), key=lambda x: -x[1])
    lines = []
    for cat, score in sorted_cats:
        if score > 0:
            query = CATEGORY_QUERIES.get(cat, cat)
            lines.append(f"- {cat} ({score}점): {query[:100]}")
    return "\n".join(lines) if lines else "특별한 취향 없음 (다양한 설화 포함)"


def initialize(state: ListAgentState) -> dict:
    theme_text = _scores_to_theme_text(state.get("category_scores", {}))
    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=(
            f"제주 여행 코스 후보 3개를 선택해주세요.\n\n"
            f"조건:\n"
            f"- 지역: {state['region']}\n"
            f"- 설화 취향 (점수 높은 순):\n{theme_text}\n"
            f"- 여행 일수: {state['duration_days']}일\n\n"
            f"search_jeju_courses 도구로 후보를 가져온 뒤, "
            f"get_folklore_near_place 로 설화 연결이 풍부한 코스를 확인해 "
            f"가장 잘 맞는 3개를 선택해주세요."
        )),
    ]
    return {"messages": messages}


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


def _extract_tool_results(messages: list) -> dict[str, dict]:
    """state 메시지에서 ToolMessage JSON 결과를 파싱해 id → course dict 매핑 반환."""
    result = {}
    for m in messages:
        content = getattr(m, "content", "")
        if not isinstance(content, str):
            continue
        try:
            parsed = json.loads(content)
            if isinstance(parsed, list):
                for course in parsed:
                    if isinstance(course, dict) and "id" in course:
                        result[course["id"]] = course
        except Exception:
            pass
    return result


def format_output(state: ListAgentState) -> dict:
    structured_llm = llm.with_structured_output(CourseSelection)

    tool_courses = _extract_tool_results(state["messages"])

    # 유효 course id → title 매핑 (LLM에 명시적으로 전달해 가짜 ID 생성 방지)
    valid_courses_text = "\n".join(
        f"  - id={cid}, title={c.get('title', '')}"
        for cid, c in tool_courses.items()
    )

    # 설화 발견 내역 (messages에서 folklore tool 결과만 추출)
    folklore_lines = []
    pending_call: dict | None = None
    for m in state["messages"]:
        if hasattr(m, "tool_calls") and m.tool_calls:
            for tc in m.tool_calls:
                if tc["name"] == "get_folklore_near_place":
                    pending_call = tc["args"]
        content = getattr(m, "content", "")
        if isinstance(content, str) and content:
            try:
                parsed = json.loads(content)
                if isinstance(parsed, list) and parsed and "code_no" in parsed[0]:
                    titles = [f.get("title", "") for f in parsed]
                    call_info = json.dumps(pending_call or {}, ensure_ascii=False)[:80]
                    folklore_lines.append(f"  위치 {call_info}: 설화 {len(titles)}개 — {', '.join(titles[:4])}")
                    pending_call = None
                elif isinstance(parsed, list) and "code_no" not in (parsed[0] if parsed else {}):
                    # 빈 설화 결과
                    if pending_call is not None:
                        call_info = json.dumps(pending_call, ensure_ascii=False)[:80]
                        folklore_lines.append(f"  위치 {call_info}: 설화 0개")
                        pending_call = None
            except Exception:
                pass

    folklore_text = "\n".join(folklore_lines) if folklore_lines else "  (설화 검색 결과 없음)"
    scores = state.get("category_scores", {})
    sorted_cats = sorted(scores.items(), key=lambda x: -x[1])
    scores_text = ", ".join(f"{c}({s}점)" for c, s in sorted_cats if s > 0) or "없음"
    top_query = CATEGORY_QUERIES.get(sorted_cats[0][0], "") if sorted_cats else ""

    extraction_prompt = (
        f"아래 코스 목록과 설화 발견 내역을 보고 설화 취향에 가장 잘 맞는 코스 3개의 id를 골라주세요.\n\n"
        f"설화 취향 (점수 높은 순): {scores_text}\n"
        f"주요 테마 설명: {top_query[:150]}\n\n"
        f"[유효한 코스 목록 — 반드시 이 목록의 id만 사용]\n{valid_courses_text}\n\n"
        f"[설화 발견 내역 — 설화가 많은 위치의 코스를 우선]\n{folklore_text}\n\n"
        f"규칙: course_ids에는 위 '유효한 코스 목록'의 id 값만 넣으세요. "
        f"설화 code_no(W_F_xxx 형태)는 course id가 아닙니다."
    )

    try:
        selection: CourseSelection = structured_llm.invoke(
            [HumanMessage(content=extraction_prompt)]
        )
        courses = []
        for cid in selection.course_ids:
            course = tool_courses.get(cid)
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
            return {"result_courses": [], "error": "선택된 코스 id가 tool 결과에 없습니다."}
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
