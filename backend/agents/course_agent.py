"""설화 중심 코스 추천 LangGraph 에이전트 (LLM-driven ReAct).

LLM이 중심이 되어:
1. search_jeju_courses 도구로 비짓제주 코스 후보 탐색
2. get_folklore_near_place 도구로 각 장소 인근 설화 검색
3. 사용자 취향에 맞는 코스를 선택하고 제목 생성

흐름:
    initialize → call_model ⇄ call_tools (ReAct 루프) → format_output → END
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
from typing import Annotated, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
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

# ChromaDB와 SQLite를 모듈 로드 시점에 미리 초기화
# (ToolNode 멀티스레드 풀에서의 동시 초기화 충돌 방지)
get_db_connection()
get_chroma_collection()

MAX_TOOL_CALLS = 12

CATEGORY_QUERIES = {
    "무속신화·신격 전승": (
        "제주 무속신화 본풀이 신격 전승 이야기. "
        "본향당 당신 심방 굿 좌정 천지왕 옥황상제 서천꽃밭 영등신 세경신. "
        "신이 인간 세상에 내려와 마을과 당에 자리 잡는 서사."
    ),
    "생활민담·교훈담": (
        "제주 생활민담 교훈담 해학 이야기. "
        "재치 지혜 욕심 벌 교훈 권선징악 속고 속이는 이야기. "
        "일상 속 인간의 행동과 선택이 드러나는 민담."
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

_CATEGORY_QUERY_HINTS = "\n".join(
    f'  - "{cat}": {query[:80]}...'
    for cat, query in CATEGORY_QUERIES.items()
)

SYSTEM_PROMPT = f"""당신은 제주도 설화 여행 전문 AI 플래너입니다.

역할:
사용자의 취향(카테고리 점수)과 여행 일수를 바탕으로 최적의 제주 여행 코스를 계획합니다.
Visit Jeju의 실제 여행 경로 데이터를 기반으로, 각 장소에 관련 제주 설화를 연결합니다.

작업 순서:
1. search_jeju_courses 도구로 여행 일수에 맞는 코스 목록을 가져옵니다.
2. 코스 목록을 검토하고 사용자 취향에 가장 잘 맞을 코스를 1~2개 선택합니다.
3. 선택한 코스의 장소들에 대해 get_folklore_near_place 도구로 인근 설화를 검색합니다.
   - 설화가 없는 장소는 반경을 5000m로 늘려 재시도하세요.
4. 설화가 가장 풍부하게 연결된 코스를 최종 선택합니다.

설화 검색 query 작성 가이드:
단어 1~2개가 아닌, 관련 키워드를 문장으로 엮어 길게 써야 검색 품질이 높아집니다.
카테고리별 권장 query 예시:
{_CATEGORY_QUERY_HINTS}

중요 규칙:
- GPS 좌표(lat, lng)는 절대 직접 만들지 마세요. 도구에서 받은 실제 데이터만 사용하세요.
- 설화가 하나도 없는 코스보다 설화가 조금이라도 있는 코스를 선택하세요.
- 모든 주요 장소(최소 절반 이상)에 설화가 연결되도록 노력하세요.
- 충분한 데이터를 수집했다고 판단되면 도구 호출을 중단하고 결론을 내리세요."""


# ─── folklore GPS 캐시 ────────────────────────────────────────────────────────

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
def search_jeju_courses(duration_days: int) -> str:
    """Visit Jeju DB에서 여행 일수에 맞는 제주 여행 코스 목록을 가져옵니다.

    Args:
        duration_days: 여행 일수 (1~5)

    Returns:
        여행 코스 목록 JSON. 각 코스: id, title, duration_days,
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
        LIMIT 15
        """,
        (duration_min, duration_max, min_places),
    ).fetchall()

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
            {
                "place_name": p["place_name"],
                "lat": p["lat"],
                "lng": p["lng"],
                "day": p["day"],
            }
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

        if len(courses) >= 10:
            break

    return json.dumps(courses, ensure_ascii=False)


@tool
def get_folklore_near_place(
    lat: float,
    lng: float,
    query: str,
    radius_m: int = 3000,
) -> str:
    """특정 GPS 좌표 주변의 관련 설화를 검색합니다.

    Args:
        lat: 위도
        lng: 경도
        query: 설화 검색 키워드 (테마, 분위기 관련 한국어)
        radius_m: 검색 반경 미터 (기본 3000)

    Returns:
        인근 설화 목록 JSON. 각 항목: code_no, title, source_type,
        distance_m, lat, lng
    """
    # 카테고리 이름이 포함된 짧은 query는 풀 텍스트로 자동 확장 (RAG 품질 향상)
    expanded_query = query
    for cat_name, cat_query in CATEGORY_QUERIES.items():
        if cat_name in query:
            expanded_query = cat_query
            break

    collection = get_chroma_collection()
    rag_results = collection.query(
        query_embeddings=[embed_query(expanded_query)],
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
                "lat": f["lat"],
                "lng": f["lng"],
            })

    nearby.sort(key=lambda x: x["distance_m"])
    return json.dumps(nearby[:10], ensure_ascii=False)


_tools = [search_jeju_courses, get_folklore_near_place]
_tool_node = ToolNode(_tools)
_llm_with_tools = llm.bind_tools(_tools)


# ─── State ───────────────────────────────────────────────────────────────────

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]
    user_input: str
    category_scores: dict[str, int]
    duration_days: int
    final_course: dict
    course_title: str
    error: str


# ─── Structured Output 스키마 ─────────────────────────────────────────────────

class FolkloreRef(BaseModel):
    code_no: str
    title: str
    source_type: str = "legend"
    lat: float
    lng: float
    distance_m: float = 0.0


class PlaceRef(BaseModel):
    place_name: str
    lat: float
    lng: float
    day: int
    folklore_nearby: list[FolkloreRef] = Field(default_factory=list)


class CourseOutput(BaseModel):
    course_id: str = Field(description="선택한 Visit Jeju 코스 ID")
    course_title: str = Field(description="설화 주제를 반영한 창의적인 코스 제목")
    places: list[PlaceRef] = Field(description="방문 장소 목록")


# ─── 헬퍼 ────────────────────────────────────────────────────────────────────

def _category_scores_to_text(scores: dict[str, int]) -> str:
    if not scores:
        return "특별한 취향 없음 (다양한 설화 포함)"
    sorted_cats = sorted(scores.items(), key=lambda x: -x[1])
    lines = [f"  - {cat}: {score}점" for cat, score in sorted_cats if score > 0]
    return "\n".join(lines) if lines else "특별한 취향 없음"


def _count_tool_calls(messages: list) -> int:
    return sum(
        1 for m in messages
        if hasattr(m, "tool_calls") and m.tool_calls
    )


# ─── 노드 ────────────────────────────────────────────────────────────────────

def initialize(state: AgentState) -> dict:
    """초기 메시지 생성: 시스템 프롬프트 + 사용자 요청."""
    duration = state.get("duration_days", 1)
    category_text = _category_scores_to_text(state.get("category_scores", {}))

    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=(
            f"제주 여행 코스를 계획해주세요.\n\n"
            f"여행 일수: {duration}일\n"
            f"취향 카테고리 점수:\n{category_text}\n\n"
            f"도구를 사용해 비짓제주 코스를 검색하고, "
            f"각 장소 인근 설화를 찾아 최적의 코스를 완성해주세요."
        )),
    ]
    return {"messages": messages}


def call_model(state: AgentState) -> dict:
    """LLM 호출 (도구 바인딩 포함)."""
    response = _llm_with_tools.invoke(state["messages"])
    return {"messages": [response]}


def format_output(state: AgentState) -> dict:
    """ReAct 루프 종료 후 대화 히스토리에서 구조화된 코스 추출."""
    structured_llm = llm.with_structured_output(CourseOutput)

    # 대화 히스토리를 텍스트로 요약 (최근 30개 메시지)
    history_lines = []
    for m in state["messages"][-30:]:
        role = getattr(m, "type", "unknown")
        content = getattr(m, "content", "")
        if isinstance(content, str) and content:
            history_lines.append(f"[{role}]: {content[:800]}")
        elif hasattr(m, "tool_calls") and m.tool_calls:
            for tc in m.tool_calls:
                history_lines.append(
                    f"[tool_call]: {tc['name']}({json.dumps(tc['args'], ensure_ascii=False)[:200]})"
                )

    history_text = "\n".join(history_lines)

    extraction_prompt = (
        f"아래 대화에서 최종 결정된 여행 코스를 구조화된 형식으로 추출해주세요.\n\n"
        f"대화 내용:\n{history_text}\n\n"
        f"주의사항:\n"
        f"- GPS 좌표(lat, lng)는 반드시 도구 결과에서 나온 실제 값을 사용하세요.\n"
        f"- 설화 정보(code_no, title 등)도 도구 결과 그대로 사용하세요.\n"
        f"- course_id는 search_jeju_courses 결과의 id 값이어야 합니다."
    )

    try:
        result: CourseOutput = structured_llm.invoke(
            [HumanMessage(content=extraction_prompt)]
        )

        final_course = {
            "id": result.course_id,
            "title": result.course_title,
            "places": [
                {
                    "place_name": p.place_name,
                    "lat": p.lat,
                    "lng": p.lng,
                    "day": p.day,
                    "folklore_nearby": [
                        {
                            "code_no": f.code_no,
                            "title": f.title,
                            "source_type": f.source_type,
                            "lat": f.lat,
                            "lng": f.lng,
                            "distance_m": f.distance_m,
                        }
                        for f in p.folklore_nearby
                    ],
                }
                for p in result.places
            ],
        }

        return {
            "final_course": final_course,
            "course_title": result.course_title,
            "error": "",
        }

    except Exception as e:
        return {
            "final_course": {},
            "course_title": "",
            "error": f"코스 생성 실패: {e}",
        }


# ─── 라우터 ──────────────────────────────────────────────────────────────────

def should_continue(state: AgentState) -> Literal["tools", "format_output"]:
    last_message = state["messages"][-1]

    # 도구 호출 횟수 초과 시 강제 종료
    if _count_tool_calls(state["messages"]) >= MAX_TOOL_CALLS:
        return "format_output"

    if hasattr(last_message, "tool_calls") and last_message.tool_calls:
        return "tools"

    return "format_output"


# ─── 그래프 조립 ──────────────────────────────────────────────────────────────

def build_graph():
    g = StateGraph(AgentState)

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


course_graph = build_graph()
