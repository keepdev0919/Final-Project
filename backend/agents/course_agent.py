"""설화 중심 코스 추천 LangGraph 에이전트.

흐름:
    understand_interest → search_folklore → extract_locations
        → build_route → enrich_with_visitjeju → fill_gaps → finish
"""
from __future__ import annotations

import json
import math
import os
import sqlite3
import uuid
from pathlib import Path
from typing import TypedDict

from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, END

from services.db import get_db_connection, get_chroma_collection, embed_query

BASE_DIR = Path(__file__).parent.parent.parent
FOLKLORE_GPS_PATH = BASE_DIR / "data" / "processed" / "folklore_gps.json"

llm = ChatOpenAI(model="gpt-4o", temperature=0.3, api_key=os.getenv("OPENAI_API_KEY"))

# 실제 설화 텍스트 전수 분석(505개) 기반 키워드
# 단어 나열이 아닌 문장 형태로 구성 → OpenAI 임베딩 품질 향상
THEME_QUERIES = {
    "신화": (
        "제주 무속신화 본풀이 당신화. "
        "본향당 심방 굿 좌정 천지왕 옥황상제 서천꽃밭 환생꽃. "
        "세경 초공 이공 삼공 차사 칠성 지장 문전 삼승 원천강 영등. "
        "조상신 이승과 저승 귀양정배 적강 신격화."
    ),
    "도깨비": (
        "제주 도깨비 귀신 초자연적 존재 이야기. "
        "도체비 도깨빗불 헛게 그슨새 기신 혼령 유령 헛것 불미귀신. "
        "여우 구렁이 호랑이 둔갑 변신 요괴 저승사자. "
        "밤에 나타나는 존재 신비한 현상 무서운 이야기."
    ),
    "사랑과이별": (
        "제주 사랑 이별 혼인 인간 감정 이야기. "
        "신랑 신부 처녀 총각 낭군 그리움 눈물 비극 원한. "
        "콩데기 계모 다슴어멍 효자 전생업보 인연 팔자. "
        "한이 맺힌 설운 서로운 가족 부부 사이 슬픈 이야기."
    ),
    "바다해녀": (
        "제주 바다 해녀 어촌 생활 이야기. "
        "잠수 물질 전복 소라 멸치 멜 어장 고기잡이 바당. "
        "용왕 영등할망 어부 선박 해신 풍어제. "
        "바다에서 살아가는 제주 사람들 삶."
    ),
    "오름자연": (
        "제주 오름 자연 지형 지명 유래 이야기. "
        "한라산 설문대할망 백록담 화산 산신 폭포 동굴 바위 연못. "
        "고종달 마을 설촌 지명유래 명당 지세 영기. "
        "제주 땅과 자연에 얽힌 전설."
    ),
}

# 하위 호환을 위한 별칭 (understand_interest 노드에서 테마 목록 참조)
THEME_KEYWORDS = {k: [] for k in THEME_QUERIES}


def _haversine_m(lat1, lng1, lat2, lng2) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ─── State ───────────────────────────────────────────────────────────────────

class AgentState(TypedDict):
    user_input: str
    theme: str
    duration_days: int
    transport: str
    folklore_results: list[dict]    # RAG 검색 결과
    folklore_locations: list[dict]  # GPS 있는 설화 장소
    route: list[dict]               # 동선 최적화된 장소 순서
    enriched_route: list[dict]      # Visit Jeju 보완 후
    course_title: str
    error: str


# ─── Nodes ───────────────────────────────────────────────────────────────────

def understand_interest(state: AgentState) -> AgentState:
    """사용자 입력에서 테마 파악. 명시된 경우 그대로 사용."""
    theme = state.get("theme", "")
    if theme not in THEME_QUERIES:
        # LLM으로 테마 분류
        prompt = f"""다음 사용자 요청에서 가장 잘 맞는 설화 테마를 골라줘.
테마 목록: {list(THEME_QUERIES.keys())}
사용자 요청: {state['user_input']}
테마 이름만 답해줘."""
        result = llm.invoke(prompt).content.strip()
        theme = result if result in THEME_QUERIES else "신화"
    return {**state, "theme": theme}


def search_folklore(state: AgentState) -> AgentState:
    """ChromaDB RAG로 테마 관련 설화 검색."""
    collection = get_chroma_collection()
    query = THEME_QUERIES[state["theme"]]

    results = collection.query(
        query_embeddings=[embed_query(query)],
        n_results=min(20, collection.count()),
        include=["documents", "metadatas", "distances"],
    )

    folklore_results = []
    for doc, meta, dist in zip(
        results["documents"][0],
        results["metadatas"][0],
        results["distances"][0],
    ):
        if dist < 0.65:  # 관련성 임계값
            folklore_results.append({
                "code_no": meta.get("code_no", ""),
                "title": meta.get("title", ""),
                "text": doc[:300],
                "distance": dist,
            })

    return {**state, "folklore_results": folklore_results}


def extract_locations(state: AgentState) -> AgentState:
    """설화 검색 결과에서 GPS 좌표 추출."""
    with open(FOLKLORE_GPS_PATH, encoding="utf-8") as f:
        gps_data = {item["code_no"]: item for item in json.load(f)}

    locations = []
    seen_places = set()
    for item in state["folklore_results"]:
        code_no = item["code_no"]
        if code_no in gps_data:
            gps = gps_data[code_no]
            place_key = gps["primary_place"]
            if place_key not in seen_places:
                seen_places.add(place_key)
                locations.append({
                    "code_no": code_no,
                    "title": gps["title"],
                    "place": gps["primary_place"],
                    "lat": gps["lat"],
                    "lng": gps["lng"],
                    "text": item["text"],
                })

    return {**state, "folklore_locations": locations}


def build_route(state: AgentState) -> AgentState:
    """설화 장소들을 일수에 맞게 동선 최적화 (greedy nearest neighbor)."""
    locations = state["folklore_locations"]
    duration_days = state["duration_days"]

    if not locations:
        return {**state, "route": [], "error": "관련 설화 장소를 찾지 못했습니다."}

    # 제주공항 시작점
    start = {"place": "제주국제공항", "lat": 33.5071, "lng": 126.4934, "is_waypoint": True}
    unvisited = list(locations[:duration_days * 4])  # 하루 최대 4곳

    route = []
    current = start
    while unvisited:
        nearest = min(unvisited, key=lambda x: _haversine_m(
            current["lat"], current["lng"], x["lat"], x["lng"]
        ))
        unvisited.remove(nearest)
        route.append({**nearest, "day": (len(route) // 4) + 1})
        current = nearest

    # day 재배분 (duration_days 초과 방지)
    for i, place in enumerate(route):
        place["day"] = min((i // max(1, len(route) // duration_days)) + 1, duration_days)

    return {**state, "route": route}


def enrich_with_visitjeju(state: AgentState) -> AgentState:
    """Visit Jeju DB에서 설화 장소 인근 실용 장소(식당·카페) 추가."""
    if not state["route"]:
        return {**state, "enriched_route": []}

    conn = get_db_connection()
    enriched = list(state["route"])

    for folklore_place in state["route"]:
        lat, lng = folklore_place["lat"], folklore_place["lng"]
        radius_deg = 0.01  # 약 1km

        nearby = conn.execute(
            """
            SELECT DISTINCT place_name, AVG(lat) as lat, AVG(lng) as lng
            FROM course_places
            WHERE lat BETWEEN ? AND ?
              AND lng BETWEEN ? AND ?
              AND in_jeju = 1
            GROUP BY place_name
            LIMIT 3
            """,
            (lat - radius_deg, lat + radius_deg, lng - radius_deg, lng + radius_deg),
        ).fetchall()

        for row in nearby:
            dist = _haversine_m(lat, lng, row["lat"], row["lng"])
            if dist > 50:  # 설화 장소 자체 제외
                enriched.append({
                    "place": row["place_name"],
                    "lat": row["lat"],
                    "lng": row["lng"],
                    "day": folklore_place["day"],
                    "is_practical": True,  # 식당·카페 등 실용 장소
                })

    return {**state, "enriched_route": enriched}


def fill_gaps(state: AgentState) -> AgentState:
    """설화 장소 간 거리가 20km 이상이면 중간 관광지 추가."""
    route = state["enriched_route"]
    if len(route) < 2:
        return {**state, "enriched_route": route}

    conn = get_db_connection()
    filled = [route[0]]

    for i in range(1, len(route)):
        prev, curr = route[i - 1], route[i]
        dist = _haversine_m(prev["lat"], prev["lng"], curr["lat"], curr["lng"])

        if dist > 20_000:
            mid_lat = (prev["lat"] + curr["lat"]) / 2
            mid_lng = (prev["lng"] + curr["lng"]) / 2
            radius_deg = 0.05

            gap_place = conn.execute(
                """
                SELECT place_name, AVG(lat) as lat, AVG(lng) as lng, COUNT(*) as cnt
                FROM course_places
                WHERE lat BETWEEN ? AND ?
                  AND lng BETWEEN ? AND ?
                  AND in_jeju = 1
                GROUP BY place_name
                ORDER BY cnt DESC
                LIMIT 1
                """,
                (mid_lat - radius_deg, mid_lat + radius_deg,
                 mid_lng - radius_deg, mid_lng + radius_deg),
            ).fetchone()

            if gap_place:
                filled.append({
                    "place": gap_place["place_name"],
                    "lat": gap_place["lat"],
                    "lng": gap_place["lng"],
                    "day": curr["day"],
                    "is_gap_filler": True,
                })

        filled.append(curr)

    return {**state, "enriched_route": filled}


def finish(state: AgentState) -> AgentState:
    """코스 제목 생성."""
    theme = state["theme"]
    titles = {
        "신화": "신화의 땅 제주를 걷다",
        "도깨비": "도깨비 이야기를 따라서",
        "사랑과이별": "제주의 사랑과 이별 기행",
        "바다해녀": "해녀의 바다, 제주를 만나다",
        "오름자연": "오름과 자연 전설 탐험",
    }
    return {**state, "course_title": titles.get(theme, f"제주 {theme} 설화 기행")}


# ─── Graph ───────────────────────────────────────────────────────────────────

def build_graph():
    g = StateGraph(AgentState)
    g.add_node("understand_interest", understand_interest)
    g.add_node("search_folklore", search_folklore)
    g.add_node("extract_locations", extract_locations)
    g.add_node("build_route", build_route)
    g.add_node("enrich_with_visitjeju", enrich_with_visitjeju)
    g.add_node("fill_gaps", fill_gaps)
    g.add_node("finish", finish)

    g.set_entry_point("understand_interest")
    g.add_edge("understand_interest", "search_folklore")
    g.add_edge("search_folklore", "extract_locations")
    g.add_edge("extract_locations", "build_route")
    g.add_edge("build_route", "enrich_with_visitjeju")
    g.add_edge("enrich_with_visitjeju", "fill_gaps")
    g.add_edge("fill_gaps", "finish")
    g.add_edge("finish", END)

    return g.compile()


course_graph = build_graph()
