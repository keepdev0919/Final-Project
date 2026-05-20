"""설화 데이터를 사용자 친화적 콘텐츠로 가공하는 LLM 모듈.

3가지 생성 함수:
    - generate_hook(folklore)             → 30~50자 후크 한 줄
    - generate_connection(folklore, place)→ 30~60자 장소 연결 한 줄
    - generate_story_pages(folklore, place)→ 5~7페이지의 동화체 스토리

모든 함수는 retry 1회 후 실패 시 None을 반환한다. 호출자는 None을
받으면 캐시에 저장하지 않고 다음 요청 때 재시도하도록 설계되어 있다.
"""
from __future__ import annotations

import os
from typing import Optional

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

# 짧은 한 줄 생성용 — 빠르고 저렴한 모델
_llm_short = ChatOpenAI(
    model="gpt-4o-mini",
    temperature=0.6,
    api_key=os.getenv("OPENAI_API_KEY"),
)

# 길고 톤이 일관된 스토리 생성용
_llm_story = ChatOpenAI(
    model="gpt-4o",
    temperature=0.7,
    api_key=os.getenv("OPENAI_API_KEY"),
)

# ── Structured Output 스키마 ──────────────────────────────────────────────────


class _HookOutput(BaseModel):
    hook: str = Field(description="설화의 핵심을 호기심 자극형으로 표현한 한 줄 (30~50자)")


class _ConnectionOutput(BaseModel):
    connection: str = Field(
        description="장소와 설화를 묶어 왜 이 장소에서 이 설화를 봐야 하는지 설명하는 한 줄 (30~60자)"
    )


class _StoryPage(BaseModel):
    title: str = Field(description="페이지 제목 (프롤로그/1막/2막/.../에필로그)")
    body: str = Field(description="동화체 본문 100~150자")


class _StoryOutput(BaseModel):
    pages: list[_StoryPage] = Field(description="5~7개의 스토리 페이지")


# ── 프롬프트 ──────────────────────────────────────────────────────────────────

_HOOK_SYS = """당신은 제주 설화 큐레이터입니다.
독자가 한 줄만 보고도 '이 이야기 더 알고 싶다'고 느끼게 만드는 후크를 씁니다.

규칙:
- 정확히 한 줄, 한국어 30~50자
- 학술 어투 금지 ("~의 내력을 담은 신화이다" 같은 문장 절대 금지)
- 호기심·신비·반전 중 하나를 자극할 것
- 명사구 또는 짧은 평서문으로 끝낼 것
- 인물·사건·반전 요소 중 가장 강렬한 하나를 노출"""

_CONNECTION_SYS = """당신은 제주 여행 스토리텔러입니다.
특정 장소에서 특정 설화를 마주칠 때, 왜 여기서 이 이야기를 들어야 하는지를
한 줄로 설명합니다.

규칙:
- 정확히 한 줄, 한국어 30~60자
- 장소와 설화를 자연스럽게 묶을 것
- "~한 이야기", "~를 만나는 자리" 등 장소-이야기 결합형 표현 활용
- 학술/위키 어투 금지"""

_STORY_SYS = """당신은 제주 설화를 동화로 풀어주는 작가입니다.
원본 설화를 5~7페이지의 짧은 스토리북으로 재구성합니다.

규칙:
- 첫 페이지 title은 반드시 "프롤로그", 마지막 페이지 title은 반드시 "에필로그"
- 중간 페이지는 "1막", "2막", "3막", ... 순서
- 각 페이지 body는 한국어 100~150자
- 어투는 동화/구전 스토리텔링 (옛날 옛적에, ~했답니다, ~였대요 등)
- 학술 요약 어투 절대 금지
- 장소명을 자연스럽게 본문에 녹일 것
- 설화의 핵심 인물·사건·반전을 시간순으로 배치"""


# ── 내부 유틸 ─────────────────────────────────────────────────────────────────


def _trim(text: str | None, limit: int = 1200) -> str:
    if not text:
        return ""
    return text.strip()[:limit]


def _folklore_context(folklore: dict) -> str:
    title = _trim(folklore.get("title"), 80)
    primary_place = _trim(folklore.get("primary_place"), 80)
    summary = _trim(folklore.get("summary"), 400)
    full_text = _trim(folklore.get("full_text"), 1200)
    body = full_text or summary or title
    return (
        f"제목: {title}\n"
        f"주요 장소: {primary_place}\n"
        f"본문: {body}"
    )


def _invoke_with_retry(structured_llm, messages, attempts: int = 2):
    """LLM 호출 + retry 1회. 모두 실패하면 None."""
    last_err: Exception | None = None
    for _ in range(attempts):
        try:
            return structured_llm.invoke(messages)
        except Exception as exc:  # noqa: BLE001
            last_err = exc
    if last_err:
        print(f"[folklore_llm] LLM 호출 실패: {type(last_err).__name__}: {last_err}")
    return None


# ── 공개 API ──────────────────────────────────────────────────────────────────


def generate_hook(folklore: dict) -> Optional[str]:
    """설화 1건에 대해 30~50자 후크를 생성한다.

    folklore dict 권장 키: title, primary_place, summary, full_text
    실패 시 None.
    """
    structured = _llm_short.with_structured_output(_HookOutput)
    user_prompt = (
        f"{_folklore_context(folklore)}\n\n"
        f"위 설화를 한 줄 후크(30~50자)로 표현해주세요."
    )
    result = _invoke_with_retry(
        structured,
        [SystemMessage(content=_HOOK_SYS), HumanMessage(content=user_prompt)],
    )
    if not result or not result.hook:
        return None
    hook = result.hook.strip().replace("\n", " ")
    # 안전장치: 너무 길면 절단
    if len(hook) > 80:
        hook = hook[:80]
    return hook or None


def generate_connection(folklore: dict, place: str) -> Optional[str]:
    """장소-설화 연결 한 줄(30~60자) 생성. 실패 시 None."""
    if not place:
        return None
    structured = _llm_short.with_structured_output(_ConnectionOutput)
    user_prompt = (
        f"{_folklore_context(folklore)}\n\n"
        f"여행자가 방문할 장소: {place}\n\n"
        f"이 장소에서 위 설화를 마주칠 때 왜 들을 만한지 한 줄(30~60자)로 써주세요."
    )
    result = _invoke_with_retry(
        structured,
        [SystemMessage(content=_CONNECTION_SYS), HumanMessage(content=user_prompt)],
    )
    if not result or not result.connection:
        return None
    connection = result.connection.strip().replace("\n", " ")
    if len(connection) > 100:
        connection = connection[:100]
    return connection or None


def generate_story_pages(folklore: dict, place: str) -> Optional[list[dict]]:
    """원본 설화를 5~7페이지의 동화체 스토리로 재구성. 실패 시 None.

    반환 형식: [{"title": "프롤로그", "body": "..."}, ...]
    """
    if not place:
        return None
    structured = _llm_story.with_structured_output(_StoryOutput)
    user_prompt = (
        f"{_folklore_context(folklore)}\n\n"
        f"여행자가 방문할 장소: {place}\n\n"
        f"위 설화를 5~7페이지 분량의 동화체 스토리북으로 재구성해주세요.\n"
        f"첫 페이지는 반드시 '프롤로그', 마지막은 '에필로그'로 시작/마무리합니다."
    )
    result = _invoke_with_retry(
        structured,
        [SystemMessage(content=_STORY_SYS), HumanMessage(content=user_prompt)],
    )
    if not result or not result.pages:
        return None

    pages: list[dict] = []
    for page in result.pages:
        title = (page.title or "").strip()
        body = (page.body or "").strip().replace("\n", " ")
        if not title or not body:
            continue
        pages.append({"title": title, "body": body})

    # 5~7 페이지 검증
    if len(pages) < 3:
        return None
    if len(pages) > 7:
        pages = pages[:7]

    # 첫/마지막 타이틀 보정
    pages[0]["title"] = "프롤로그"
    pages[-1]["title"] = "에필로그"
    return pages
