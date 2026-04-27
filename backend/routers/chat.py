"""ReAct 챗봇 엔드포인트 (SSE 스트리밍)."""
import os
import math
import json
from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from langgraph.prebuilt import create_react_agent

from models.schemas import ChatRequest
from services.db import get_db_connection, get_chroma_collection, embed_query
from services.folklore_search import search_folklore_by_place

router = APIRouter(prefix="/chat", tags=["chat"])
limiter = Limiter(key_func=get_remote_address)

llm = ChatOpenAI(model="gpt-4o", temperature=0.5, streaming=True,
                 api_key=os.getenv("OPENAI_API_KEY"))


def _haversine_m(lat1, lng1, lat2, lng2) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


@tool
def search_folklore(query: str) -> str:
    """제주 설화(신화·전설) 검색. 사용자가 이야기나 배경을 물어볼 때 사용."""
    collection = get_chroma_collection()
    results = collection.query(
        query_embeddings=[embed_query(query)],
        n_results=3,
        where={"source_type": "legend"},
        include=["documents", "metadatas", "distances"],
    )
    out = []
    for doc, meta, dist in zip(
        results["documents"][0],
        results["metadatas"][0],
        results["distances"][0],
    ):
        if dist < 0.65:
            title = meta.get("title", "")
            place = meta.get("primary_place", "")
            out.append(f"[{title} / {place}]\n{doc[:200]}")
    return "\n\n".join(out) if out else "관련 설화를 찾지 못했습니다."


@tool
def search_folktale(query: str) -> str:
    """제주 민담(구술 채록) 검색. 생활 이야기, 인물 이야기를 물어볼 때 사용."""
    collection = get_chroma_collection()
    results = collection.query(
        query_embeddings=[embed_query(query)],
        n_results=3,
        where={"source_type": "folktale"},
        include=["documents", "metadatas", "distances"],
    )
    out = []
    for doc, meta, dist in zip(
        results["documents"][0],
        results["metadatas"][0],
        results["distances"][0],
    ):
        if dist < 0.65:
            title = meta.get("title", "")
            place = meta.get("primary_place", "")
            out.append(f"[{title} / {place}]\n{doc[:200]}")
    return "\n\n".join(out) if out else "관련 민담을 찾지 못했습니다."


@tool
def get_nearby_pins(location: str) -> str:
    """장소명 근처의 설화·민담 핀 조회. '성산일출봉 근처 이야기' 같은 요청에 사용."""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT title, source_type, primary_place, lat, lng FROM metadata WHERE primary_place LIKE ? AND lat IS NOT NULL LIMIT 5",
        (f"%{location}%",),
    ).fetchall()
    if not rows:
        return f"{location} 근처에서 설화를 찾지 못했습니다."
    return "\n".join(f"- {r['title']} ({r['source_type']}, {r['primary_place']})" for r in rows)


TOOLS = [search_folklore, search_folktale, get_nearby_pins]

SYSTEM_PROMPT = """당신은 제주도 설화·민담 전문 안내자입니다.
사용자의 질문에 설화 검색 툴을 활용해 답변하세요.
설화 이야기를 할 때는 배경 장소도 함께 언급하고,
"이 장소에 가보고 싶으시면 코스를 만들어드릴까요?" 로 자연스럽게 코스 생성을 유도하세요.
출처는 [제목 (코드번호)] 형식으로 답변 끝에 붙이세요.
항상 한국어로 답변하세요."""


@router.post("")
@limiter.limit("20/minute")
async def chat(request: Request, body: ChatRequest):
    history_text = "\n".join(
        f"{m.role}: {m.content}" for m in body.history[-6:]
    )
    full_input = f"{history_text}\nuser: {body.message}" if history_text else body.message

    async def stream_response():
        try:
            agent = create_react_agent(llm, TOOLS, prompt=SYSTEM_PROMPT)
            async for chunk in agent.astream({"messages": [("user", full_input)]}):
                if "agent" in chunk:
                    for msg in chunk["agent"].get("messages", []):
                        if hasattr(msg, "content") and msg.content:
                            yield f"data: {json.dumps({'text': msg.content}, ensure_ascii=False)}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)}, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(stream_response(), media_type="text/event-stream")
