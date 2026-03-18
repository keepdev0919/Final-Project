from __future__ import annotations

import argparse
from dataclasses import dataclass

from common import (
    DEFAULT_COLLECTION_NAME,
    EMBEDDING_MODEL,
    VECTOR_DB_DIR,
    load_env_file,
)


SYSTEM_PROMPT = """당신은 제주 설화·민담 설명 챗봇입니다.
- 반드시 제공된 검색 문맥만 근거로 답변하세요.
- 문맥에 없는 내용을 지어내지 마세요.
- 답변은 한국어로 작성하세요.
- 사용자가 쉽게 이해할 수 있게 설명형 문장으로 답변하세요.
- 출처는 시스템이 별도로 붙이므로 본문 답변에는 출처 문장을 직접 쓰지 마세요.
- 관련 문맥이 부족하면 `제공된 설화 자료에는 해당 내용이 없습니다.`라고 분명히 말하세요.
"""


@dataclass
class RetrievedChunk:
    chunk_id: str
    text: str
    metadata: dict
    distance: float | None


def get_openai_client():
    load_env_file()
    try:
        from openai import OpenAI
    except ImportError as exc:
        raise RuntimeError("openai package is not installed. Activate .venv and install requirements.txt.") from exc

    import os

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is missing. Set it in .env or your shell environment.")
    return OpenAI(api_key=api_key)


def get_chroma_collection(collection_name: str):
    try:
        import chromadb
    except ImportError as exc:
        raise RuntimeError("chromadb package is not installed. Activate .venv and install requirements.txt.") from exc

    client = chromadb.PersistentClient(path=str(VECTOR_DB_DIR))
    return client.get_collection(collection_name)


def embed_query(client, query: str, model: str) -> list[float]:
    response = client.embeddings.create(model=model, input=[query])
    return response.data[0].embedding


def retrieve_chunks(
    collection,
    query_embedding: list[float],
    *,
    n_results: int,
    source_type: str | None,
) -> list[RetrievedChunk]:
    where = {"source_type": source_type} if source_type else None
    result = collection.query(
        query_embeddings=[query_embedding],
        n_results=n_results,
        where=where,
        include=["documents", "metadatas", "distances"],
    )

    ids = result.get("ids", [[]])[0]
    documents = result.get("documents", [[]])[0]
    metadatas = result.get("metadatas", [[]])[0]
    distances = result.get("distances", [[]])[0] if result.get("distances") else []

    chunks: list[RetrievedChunk] = []
    for idx, chunk_id in enumerate(ids):
        chunks.append(
            RetrievedChunk(
                chunk_id=chunk_id,
                text=documents[idx],
                metadata=metadatas[idx] or {},
                distance=distances[idx] if idx < len(distances) else None,
            )
        )
    return chunks


def format_context(chunks: list[RetrievedChunk]) -> str:
    blocks = []
    for idx, chunk in enumerate(chunks, start=1):
        title = chunk.metadata.get("title", "")
        code_no = chunk.metadata.get("code_no", "")
        source_type = chunk.metadata.get("source_type", "")
        category = chunk.metadata.get("category", "")
        category2 = chunk.metadata.get("category2", "")
        tags = chunk.metadata.get("tags", "")
        blocks.append(
            "\n".join(
                [
                    f"[문맥 {idx}]",
                    f"제목: {title}",
                    f"코드번호: {code_no}",
                    f"자료유형: {source_type}",
                    f"분류1: {category}",
                    f"분류2: {category2}",
                    f"태그: {tags}",
                    "본문:",
                    chunk.text,
                ]
            )
        )
    return "\n\n".join(blocks)


def format_history(history: list[tuple[str, str]], max_turns: int) -> str:
    if not history:
        return ""
    recent = history[-max_turns:]
    lines = ["이전 대화 요약:"]
    for question, answer in recent:
        lines.append(f"- 사용자: {question}")
        lines.append(f"- 답변: {answer}")
    return "\n".join(lines)


def filter_chunks_by_distance(
    chunks: list[RetrievedChunk],
    *,
    max_distance: float | None,
) -> list[RetrievedChunk]:
    if max_distance is None:
        return chunks
    filtered: list[RetrievedChunk] = []
    for chunk in chunks:
        if chunk.distance is None or chunk.distance <= max_distance:
            filtered.append(chunk)
    return filtered


def build_citation(chunks: list[RetrievedChunk]) -> str:
    if not chunks:
        return "출처: 없음"

    seen: set[tuple[str, str]] = set()
    parts: list[str] = []
    for chunk in chunks:
        title = str(chunk.metadata.get("title", "")).strip()
        code_no = str(chunk.metadata.get("code_no", "")).strip()
        key = (title, code_no)
        if key in seen:
            continue
        seen.add(key)
        if title and code_no:
            parts.append(f"{title} (코드: {code_no})")
        elif title:
            parts.append(title)
        elif code_no:
            parts.append(f"코드: {code_no}")

    if not parts:
        return "출처: 없음"
    return "출처: " + "; ".join(parts)


def generate_answer(
    client,
    *,
    model: str,
    question: str,
    chunks: list[RetrievedChunk],
    history: list[tuple[str, str]],
    memory_turns: int,
) -> str:
    if not chunks:
        return "제공된 설화 자료에는 해당 내용이 없습니다.\n\n출처: 없음"

    context = format_context(chunks)
    history_block = format_history(history, memory_turns)
    user_prompt = "\n\n".join(
        part
        for part in [
            history_block,
            f"사용자 질문:\n{question}",
            f"검색 문맥:\n{context}" if context else "검색 문맥:\n없음",
        ]
        if part
    )

    response = client.chat.completions.create(
        model=model,
        temperature=0,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    )
    body = response.choices[0].message.content.strip()
    return f"{body}\n\n{build_citation(chunks)}"


def print_retrieval_debug(chunks: list[RetrievedChunk]) -> None:
    print("\n[retrieval]")
    if not chunks:
        print("검색 결과 없음")
        return
    for idx, chunk in enumerate(chunks, start=1):
        title = chunk.metadata.get("title", "")
        code_no = chunk.metadata.get("code_no", "")
        distance = f"{chunk.distance:.4f}" if chunk.distance is not None else "n/a"
        print(f"{idx}. {title} ({code_no}) distance={distance}")


def answer_question(
    client,
    collection,
    *,
    question: str,
    source: str | None,
    k: int,
    embedding_model: str,
    chat_model: str,
    memory_turns: int,
    max_distance: float | None,
    history: list[tuple[str, str]] | None = None,
) -> tuple[list[RetrievedChunk], str]:
    query_embedding = embed_query(client, question, embedding_model)
    chunks = retrieve_chunks(
        collection,
        query_embedding,
        n_results=k,
        source_type=source,
    )
    chunks = filter_chunks_by_distance(chunks, max_distance=max_distance)
    answer = generate_answer(
        client,
        model=chat_model,
        question=question,
        chunks=chunks,
        history=history or [],
        memory_turns=memory_turns,
    )
    return chunks, answer


def run_once(args) -> None:
    client = get_openai_client()
    collection = get_chroma_collection(args.collection_name)
    chunks, answer = answer_question(
        client,
        collection,
        question=args.query,
        source=args.source,
        k=args.k,
        embedding_model=args.embedding_model,
        chat_model=args.chat_model,
        memory_turns=args.memory_turns,
        max_distance=args.max_distance,
        history=[],
    )
    if args.show_retrieval:
        print_retrieval_debug(chunks)
    print("\n[answer]")
    print(answer)


def interactive_loop(args) -> None:
    client = get_openai_client()
    collection = get_chroma_collection(args.collection_name)
    history: list[tuple[str, str]] = []

    print("제주 설화·민담 챗 엔진을 시작합니다. 종료하려면 `exit` 또는 `quit`를 입력하세요.")

    while True:
        try:
            question = input("\n질문> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n종료합니다.")
            return

        if not question:
            continue
        if question.lower() in {"exit", "quit"}:
            print("종료합니다.")
            return

        chunks, answer = answer_question(
            client,
            collection,
            question=question,
            source=args.source,
            k=args.k,
            embedding_model=args.embedding_model,
            chat_model=args.chat_model,
            memory_turns=args.memory_turns,
            max_distance=args.max_distance,
            history=history,
        )
        if args.show_retrieval:
            print_retrieval_debug(chunks)
        print("\n답변>")
        print(answer)
        history.append((question, answer))


def main() -> None:
    parser = argparse.ArgumentParser(description="ChromaDB + OpenAI 기반 제주 설화·민담 RAG 챗 엔진")
    parser.add_argument("--query", help="한 번만 질문하고 종료")
    parser.add_argument("--source", choices=["legend", "folktale"], default=None)
    parser.add_argument("--k", type=int, default=5, help="검색할 청크 수")
    parser.add_argument("--chat-model", default="gpt-4o", help="답변 생성 모델")
    parser.add_argument("--embedding-model", default=EMBEDDING_MODEL, help="질문 임베딩 모델")
    parser.add_argument("--collection-name", default=DEFAULT_COLLECTION_NAME)
    parser.add_argument("--memory-turns", type=int, default=3, help="유지할 최근 대화 턴 수")
    parser.add_argument("--show-retrieval", action="store_true", help="검색된 청크 메타데이터 출력")
    parser.add_argument(
        "--max-distance",
        type=float,
        default=0.62,
        help="이 값보다 큰 거리의 청크는 버려 환각을 억제",
    )
    args = parser.parse_args()

    if args.query:
        run_once(args)
    else:
        interactive_loop(args)


if __name__ == "__main__":
    main()
