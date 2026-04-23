"""여행 중/여행 후 서비스 엔드포인트."""
import os
import json
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel

router = APIRouter(prefix="/travel", tags=["travel"])

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

# ─── 캐릭터 시스템 프롬프트 ───────────────────────────────────────────────────

CHARACTER_PROMPTS: dict[str, str] = {
    "당신/심방": """당신은 제주 마을을 수호하는 당신(堂神)이자 심방(무당)입니다.
이 장소에 깃든 신화와 신격 전승을 엄숙하면서도 따뜻하게 전해줍니다.
말투: 고풍스럽고 신비롭지만, 여행자를 가족처럼 맞이하는 온기가 있습니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "도깨비": """당신은 재치 있고 장난기 많은 제주 도깨비입니다.
생활민담과 교훈담 속 인물들의 이야기를 유머와 함께 풀어냅니다.
말투: 경쾌하고 익살스럽지만, 교훈의 핵심은 놓치지 않습니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "마을 할망": """당신은 이 마을을 수백 년 지켜온 마을 할망(할머니 신)입니다.
마을 공동체가 함께 전해온 이야기와 당제 의식을 정겹게 들려줍니다.
말투: 제주 사투리가 살짝 섞인 따뜻한 할머니 말투입니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "영등신/해녀 선배": """당신은 바다와 바람의 여신 영등신이자, 수십 년 경력의 할망 해녀입니다.
바다, 어부, 용왕, 해녀의 삶에 얽힌 전승을 들려줍니다.
말투: 바다처럼 시원하고 강인하지만, 물질의 고됨을 아는 깊이가 있습니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",

    "도체비": """당신은 제주의 으스스한 도체비(귀신·초자연 존재)입니다.
초자연 존재담과 기이한 전설을 신비롭고 오싹하게 풀어냅니다.
말투: 속삭이듯 말하다가 갑자기 단도직입적이 되는, 예측 불가능한 방식입니다.
반드시 한국어로 대화하고, 3~5문장 이내로 답하세요.""",
}

VALID_CHARACTERS = set(CHARACTER_PROMPTS.keys())


# ─── Request 모델 ──────────────────────────────────────────────────────────────

class ChatHistoryItem(BaseModel):
    role: str   # "user" | "assistant"
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
async def companion_chat(body: CompanionChatRequest):
    character = body.companion_type if body.companion_type in VALID_CHARACTERS else "도깨비"
    system_text = CHARACTER_PROMPTS[character]

    if body.folklore_summaries:
        folklore_ctx = "\n".join(f"- {s}" for s in body.folklore_summaries[:3])
        system_text += f"\n\n현재 장소: {body.place_name}\n이 장소의 설화:\n{folklore_ctx}"
    else:
        system_text += f"\n\n현재 장소: {body.place_name}\n(이 장소에 특정 설화 기록은 없습니다. 제주 설화 전반적 맥락으로 대화해주세요.)"

    is_first = len(body.history) == 0 and body.message == "__GREETING__"

    messages = [SystemMessage(content=system_text)]
    for h in body.history[-8:]:
        if h.role == "user":
            messages.append(HumanMessage(content=h.content))
        else:
            from langchain_core.messages import AIMessage
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
async def generate_journal(body: JournalRequest):
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
        return {"journal_text": "", "error": str(e)}
