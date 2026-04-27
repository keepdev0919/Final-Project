"""여행 중/여행 후 서비스 엔드포인트."""
import os
import json
from typing import Literal
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage
from pydantic import BaseModel
from services.folklore_search import search_folklore_by_place

router = APIRouter(prefix="/travel", tags=["travel"])
limiter = Limiter(key_func=get_remote_address)

llm_stream = ChatOpenAI(
    model="gpt-4o",
    temperature=0.7,
    streaming=True,
    api_key=os.getenv("OPENAI_API_KEY"),
)
llm = ChatOpenAI(
    model="gpt-4o",
    temperature=0.5,
    api_key=os.getenv("OPENAI_API_KEY"),
)

# ─── 제주 사투리 퓨샷 가이드 ─────────────────────────────────────────────────

JEJU_DIALECT_GUIDE = """
[제주 말투 가이드]
제주 할머니 신령의 말투입니다. 표준어 문장 구조에 아래 제주 표현을 자연스럽게 섞으세요.
한 문장에 제주 표현을 2개 이상 억지로 넣지 마세요 — 자연스러움이 우선입니다.

사용할 제주 표현:
- 혼저 옵서 → 어서 오세요 (환영 인사, 첫 만남에 사용)
- 아이고 → 감탄 (기쁨·놀람)
- 하영 → 많이, 매우
- 게난 → 그러니까, 그래서 (이야기 이어갈 때)
- 잘도 → 참으로, 정말
- 무사 → 왜
- 경 → 그렇게
- 몬딱 → 모두, 전부
- 삼춘 → 여행자를 부를 때 친근한 호칭
- ~마씸 → ~합니다요 (존댓말 어미, 가끔)
- ~수다 → ~합니다 (정중한 어미)

퓨샷 예시:
Q: [장소에 도착했어요]
A: 혼저 옵서, 삼춘. 이 당에 발걸음해 줬구나예. 아이고, 하영 반갑수다.

Q: 이 장소에 어떤 이야기가 있나요?
A: 게난, 이곳엔 오래된 이야기가 전해 내려오지마씸. 마을 사람들이 해마다 이 당에 모여 정성을 올렸다 하더마씸. 잘도 소중한 자리라.

Q: 왜 이 장소가 특별한가요?
A: 무사 특별하냐고? 아이고, 삼춘~ 이 땅은 수백 년 신령이 지켜온 곳이수다. 몬딱 마을 사람들의 소원이 담긴 자리라예.

Q: 다음엔 어디 가면 좋을까요?
A: 경 하면, 저쪽 바닷가 가까이 있는 당에도 한번 들러마씸. 거기도 잘도 이야기가 많은 곳이수다.

규칙:
- 표현은 문장당 1~2개만 자연스럽게 섞으세요.
- 목록 외 생소한 제주어는 쓰지 마세요.
- 어색하면 표준어로 써도 됩니다.
"""

# ─── 캐릭터 시스템 프롬프트 ───────────────────────────────────────────────────

CHARACTER_PROMPTS: dict[str, str] = {
    "마을 할망": """당신은 이 마을을 수백 년 지켜온 마을 할망(할머니 신)입니다.
마을에 전해 내려오는 이야기와 당제 의식을 정겹고 따뜻하게 들려주는 할머니입니다.
말투는 제주 방언이 자연스럽게 배어있되, 억지로 사투리를 넣으려 하지 마세요 — 진짜 제주 할머니처럼 편안하게 말하세요.
반드시 한국어로 대화하고, 3~4문장 이내로 간결하게 답하세요.""" + JEJU_DIALECT_GUIDE,
}

VALID_CHARACTERS = set(CHARACTER_PROMPTS.keys())


# ─── Request 모델 ──────────────────────────────────────────────────────────────

class ChatHistoryItem(BaseModel):
    role: Literal["user", "assistant"]
    content: str

class CompanionChatRequest(BaseModel):
    place_name: str
    folklore_summaries: list[str]
    companion_type: str
    message: str
    history: list[ChatHistoryItem] = []

class PlaceChatLogItem(BaseModel):
    place_name: str
    messages: list[ChatHistoryItem]

class JournalRequest(BaseModel):
    visited_places: list[str]
    chat_logs: list[PlaceChatLogItem]


# ─── 동행자 채팅 (SSE 스트리밍) ───────────────────────────────────────────────

@router.post("/companion")
@limiter.limit("15/minute")
async def companion_chat(request: Request, body: CompanionChatRequest):
    character = body.companion_type if body.companion_type in VALID_CHARACTERS else "마을 할망"
    system_text = CHARACTER_PROMPTS[character]

    # iOS가 보낸 summaries 우선, 없으면 ChromaDB RAG 검색
    summaries = [s for s in body.folklore_summaries if s.strip()]
    if not summaries:
        summaries = search_folklore_by_place(body.place_name, n=3)

    if summaries:
        folklore_ctx = "\n".join(f"- {s}" for s in summaries)
        system_text += f"\n\n현재 장소: {body.place_name}\n이 장소의 설화:\n{folklore_ctx}"
    else:
        system_text += f"\n\n현재 장소: {body.place_name}\n(이 장소에 특정 설화 기록은 없습니다. 제주 설화 전반적 맥락으로 대화해주세요.)"

    is_first = len(body.history) == 0 and body.message == "__GREETING__"

    messages = [SystemMessage(content=system_text)]
    for h in body.history[-8:]:
        if h.role == "user":
            messages.append(HumanMessage(content=h.content))
        else:
            messages.append(AIMessage(content=h.content))

    if is_first:
        messages.append(HumanMessage(content=f"{body.place_name}에 방금 도착했어요. 반갑게 인사해주세요."))
    else:
        messages.append(HumanMessage(content=body.message))

    async def stream_response():
        try:
            async for chunk in llm_stream.astream(messages):
                if chunk.content:
                    yield f"data: {json.dumps({'text': chunk.content}, ensure_ascii=False)}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)}, ensure_ascii=False)}\n\n"
        finally:
            yield "data: [DONE]\n\n"

    return StreamingResponse(stream_response(), media_type="text/event-stream")


# ─── 여행 일지 생성 ────────────────────────────────────────────────────────────

JOURNAL_SYSTEM_PROMPT = """당신은 감성적인 여행 기록 작가입니다.
사용자가 제주도를 여행하며 AI 동행자와 나눈 대화를 바탕으로,
개인화된 여행 일지를 작성해주세요.

가이드라인:
- 방문한 장소들을 시간 순서로 엮어 300~500자 한국어 산문으로 작성
- 대화에서 언급된 설화나 인상적인 내용을 자연스럽게 녹여내세요
- 관광 안내문이 아닌, 여행자의 1인칭 회고 형식으로 쓰세요
- 마지막 문장은 이 여행이 남긴 감상으로 마무리해주세요"""


@router.post("/journal")
@limiter.limit("5/minute")
async def generate_journal(request: Request, body: JournalRequest):
    places_text = ", ".join(body.visited_places) if body.visited_places else "방문 장소 없음"

    chat_summary_parts = []
    for log in body.chat_logs:
        msgs = [f"[{m.role}] {m.content}" for m in log.messages[:6]]
        chat_summary_parts.append(f"--- {log.place_name} ---\n" + "\n".join(msgs))
    chat_text = "\n\n".join(chat_summary_parts) if chat_summary_parts else "(대화 기록 없음)"

    prompt = (
        f"방문 장소: {places_text}\n\n"
        f"동행자와의 대화:\n{chat_text}\n\n"
        "위 여행을 회고하는 개인 여행 일지를 작성해주세요."
    )

    try:
        result = await llm.ainvoke([
            SystemMessage(content=JOURNAL_SYSTEM_PROMPT),
            HumanMessage(content=prompt),
        ])
        return {"journal_text": result.content}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
