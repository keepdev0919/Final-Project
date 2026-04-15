"""코스 리스트 에이전트.

지역/스타일/기간 조건으로 Visit Jeju DB에서 후보를 뽑고,
LLM이 스타일 힌트를 보고 3개를 선택해 반환한다.
설화 매핑 없음 → 빠른 응답 목표.

흐름:
    initialize → call_model ⇄ call_tools (ReAct 루프) → format_output → END
"""
from __future__ import annotations

import json
import os
from typing import Annotated, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from langgraph.graph import END, StateGraph
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode
from pydantic import BaseModel, Field

from services.db import get_db_connection

llm = ChatOpenAI(model="gpt-4o", temperature=0.3, api_key=os.getenv("OPENAI_API_KEY"))

MAX_TOOL_CALLS = 5

# 지역 필터 적용 여부 (전체는 필터 없음)
REGION_HAS_FILTER = {"북부", "남부", "동부", "서부"}

STYLE_HINTS = {
    "nature": "자연, 오름, 산, 숲, 트레킹, 한라산, 절물, 비자림, 곶자왈",
    "ocean": "해변, 바다, 해수욕장, 해안, 섭지코지, 성산일출봉, 우도, 용두암",
    "food": "맛집, 카페, 음식, 흑돼지, 해산물, 로컬, 시장, 올레시장",
    "culture": "문화, 역사, 박물관, 제주목관아, 항몽유적지, 민속촌, 성읍, 문화재",
}

SYSTEM_PROMPT = """당신은 제주 여행 코스 큐레이터입니다.

역할:
search_jeju_courses 도구로 조건에 맞는 코스 후보를 가져온 뒤,
사용자의 스타일과 가장 잘 맞는 코스 3개를 선택합니다.

선택 기준:
- 코스 제목에 스타일 키워드가 포함되어 있으면 우선순위 높음
- 장소 목록에 스타일과 관련된 지명(해변, 오름, 박물관 등)이 많을수록 좋음
- 3개는 서로 비슷하지 않고 다양하게 구성하세요

주의사항:
- 도구 결과의 코스 id, title, duration_days, places 값을 그대로 사용하세요
- GPS 좌표는 절대 직접 만들지 마세요"""


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

    rows = conn.execute(
        """
        SELECT id, title, duration_days
        FROM courses
        WHERE duration_days BETWEEN ? AND ?
          AND place_count >= ?
        ORDER BY RANDOM()
        LIMIT 30
        """,
        (duration_min, duration_max, min_places),
    ).fetchall()

    courses = []
    for row in rows:
        place_query = """
            SELECT place_name, lat, lng, day
            FROM course_places
            WHERE course_id = ? AND in_jeju = 1
            ORDER BY day, start_time
        """
        place_rows = conn.execute(place_query, (row["id"],)).fetchall()

        places = [
            {
                "place_name": p["place_name"],
                "lat": p["lat"],
                "lng": p["lng"],
                "day": p["day"],
            }
            for p in place_rows
            if p["lat"] is not None and p["lng"] is not None
        ]

        # 지역 필터 적용 (전체가 아닐 때)
        if region in REGION_HAS_FILTER and places:
            filtered = _filter_places_by_region(places, region)
            if not filtered:
                continue

        if places:
            courses.append({
                "id": row["id"],
                "title": row["title"],
                "duration_days": row["duration_days"],
                "places": places,
            })

        if len(courses) >= 15:
            break

    return json.dumps(courses, ensure_ascii=False)


def _filter_places_by_region(places: list[dict], region: str) -> list[dict]:
    """지역 GPS 조건으로 장소를 필터링. 코스 내 과반수 장소가 해당 지역이면 통과."""
    def in_region(p: dict) -> bool:
        lat, lng = p.get("lat", 0), p.get("lng", 0)
        if region == "북부":
            return lat >= 33.45
        elif region == "남부":
            return lat < 33.30
        elif region == "동부":
            return lng >= 126.70
        elif region == "서부":
            return lng < 126.40
        return True

    matched = [p for p in places if in_region(p)]
    return matched if len(matched) >= len(places) * 0.5 else []


# ─── State ───────────────────────────────────────────────────────────────────

class ListAgentState(TypedDict):
    messages: Annotated[list, add_messages]
    region: str
    style: str
    duration_days: int
    result_courses: list[dict]
    error: str


# ─── Structured Output ────────────────────────────────────────────────────────

class PlaceItem(BaseModel):
    place_name: str
    lat: float
    lng: float
    day: int


class CourseItem(BaseModel):
    id: str = Field(description="search_jeju_courses에서 받은 코스 id")
    title: str = Field(description="원본 코스 제목")
    duration_days: int
    places: list[PlaceItem]


class CourseListOutput(BaseModel):
    courses: list[CourseItem] = Field(description="선택된 코스 3개", min_length=1, max_length=3)


# ─── 노드 ────────────────────────────────────────────────────────────────────

_tools = [search_jeju_courses]
_tool_node = ToolNode(_tools)
_llm_with_tools = llm.bind_tools(_tools)


def initialize(state: ListAgentState) -> dict:
    style_hint = STYLE_HINTS.get(state["style"], state["style"])
    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=(
            f"제주 여행 코스 후보 3개를 선택해주세요.\n\n"
            f"조건:\n"
            f"- 지역: {state['region']}\n"
            f"- 여행 스타일: {state['style']} ({style_hint})\n"
            f"- 여행 일수: {state['duration_days']}일\n\n"
            f"search_jeju_courses 도구로 후보를 가져온 뒤, "
            f"스타일에 가장 잘 맞는 3개를 골라주세요."
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


def format_output(state: ListAgentState) -> dict:
    structured_llm = llm.with_structured_output(CourseListOutput)

    history_lines = []
    for m in state["messages"][-20:]:
        role = getattr(m, "type", "unknown")
        content = getattr(m, "content", "")
        if isinstance(content, str) and content:
            history_lines.append(f"[{role}]: {content[:600]}")
        elif hasattr(m, "tool_calls") and m.tool_calls:
            for tc in m.tool_calls:
                history_lines.append(
                    f"[tool_call]: {tc['name']}({json.dumps(tc['args'], ensure_ascii=False)[:200]})"
                )

    history_text = "\n".join(history_lines)
    style_hint = STYLE_HINTS.get(state["style"], state["style"])

    extraction_prompt = (
        f"아래 대화에서 선택된 코스 3개를 구조화된 형식으로 추출해주세요.\n\n"
        f"스타일 힌트: {style_hint}\n\n"
        f"대화 내용:\n{history_text}\n\n"
        f"주의:\n"
        f"- 도구 결과에서 받은 id, title, places 값을 그대로 사용하세요\n"
        f"- GPS 좌표는 도구 결과 값만 사용하세요\n"
        f"- 정확히 3개를 반환하세요"
    )

    try:
        result: CourseListOutput = structured_llm.invoke(
            [HumanMessage(content=extraction_prompt)]
        )
        courses = [
            {
                "id": c.id,
                "title": c.title,
                "duration_days": c.duration_days,
                "places": [
                    {
                        "place_name": p.place_name,
                        "lat": p.lat,
                        "lng": p.lng,
                        "day": p.day,
                    }
                    for p in c.places
                ],
            }
            for c in result.courses
        ]
        return {"result_courses": courses, "error": ""}
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
