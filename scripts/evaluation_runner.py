from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

from chat_engine import (
    RetrievedChunk,
    answer_question,
    get_chroma_collection,
    get_openai_client,
)
from common import (
    DEFAULT_COLLECTION_NAME,
    EMBEDDING_MODEL,
    EVALUATIONS_DIR,
    load_jsonl,
    utc_now_iso,
)


@dataclass
class EvaluationResult:
    question_id: str
    question: str
    category: str
    subtype: str
    source_hint: str
    expected_behavior: str
    expected_keywords: list[str]
    rejection_expected: bool
    retrieval_count: int
    retrieval_titles: list[str]
    retrieval_codes: list[str]
    answer: str
    verdict: str
    notes: list[str]


def load_questions(path: Path) -> list[dict]:
    return load_jsonl(path)


def normalize_source_hint(source_hint: str | None, cli_source: str | None) -> str | None:
    if cli_source:
        return cli_source
    if source_hint in {None, "", "all"}:
        return None
    return source_hint


def summarize_chunks(chunks: list[RetrievedChunk]) -> tuple[list[str], list[str]]:
    titles: list[str] = []
    codes: list[str] = []
    for chunk in chunks:
        title = str(chunk.metadata.get("title", "")).strip()
        code = str(chunk.metadata.get("code_no", "")).strip()
        if title and title not in titles:
            titles.append(title)
        if code and code not in codes:
            codes.append(code)
    return titles, codes


def evaluate_answer(question: dict, chunks: list[RetrievedChunk], answer: str) -> tuple[str, list[str]]:
    notes: list[str] = []
    expected_keywords = [str(item) for item in question.get("expected_keywords", [])]
    content_keywords = [keyword for keyword in expected_keywords if keyword != "출처"]
    rejection_expected = bool(question.get("rejection_expected", False))
    rejection_markers = [
        "제공된 설화 자료에는",
        "해당 내용이 없습니다",
        "내용이 없습니다",
    ]
    has_rejection = any(marker in answer for marker in rejection_markers)

    if rejection_expected:
        if not has_rejection:
            notes.append("거부 문구가 없음")
        if "출처: 없음" not in answer:
            notes.append("무관 질문인데 출처 없음 형식이 아님")
        if chunks:
            notes.append("무관 질문인데 검색 결과가 반환됨")
        return ("pass" if not notes else "fail", notes)

    if has_rejection:
        notes.append("정상 질문인데 답변이 거부됨")

    matched = 0
    matched_content = 0
    for keyword in expected_keywords:
        if keyword in answer:
            matched += 1
    for keyword in content_keywords:
        if keyword in answer:
            matched_content += 1

    if "출처:" not in answer:
        notes.append("출처 형식이 없음")
    if not chunks:
        notes.append("검색 결과 없음")
    if matched == 0 and expected_keywords:
        notes.append("기대 키워드가 답변에 없음")
    if content_keywords and matched_content == 0:
        notes.append("핵심 키워드가 답변에 없음")

    if not notes:
        return "pass", notes
    if (
        "출처 형식이 없음" in notes
        or "검색 결과 없음" in notes
        or "정상 질문인데 답변이 거부됨" in notes
    ):
        return "fail", notes
    return "partial", notes


def result_to_dict(result: EvaluationResult) -> dict:
    return {
        "question_id": result.question_id,
        "question": result.question,
        "category": result.category,
        "subtype": result.subtype,
        "source_hint": result.source_hint,
        "expected_behavior": result.expected_behavior,
        "expected_keywords": result.expected_keywords,
        "rejection_expected": result.rejection_expected,
        "retrieval_count": result.retrieval_count,
        "retrieval_titles": result.retrieval_titles,
        "retrieval_codes": result.retrieval_codes,
        "answer": result.answer,
        "verdict": result.verdict,
        "notes": result.notes,
    }


def render_markdown(results: list[EvaluationResult], *, run_id: str, args) -> str:
    pass_count = sum(1 for item in results if item.verdict == "pass")
    partial_count = sum(1 for item in results if item.verdict == "partial")
    fail_count = sum(1 for item in results if item.verdict == "fail")

    lines = [
        f"# 평가 실행 결과",
        "",
        f"- 실행 ID: `{run_id}`",
        f"- 질문 수: `{len(results)}`",
        f"- 통과: `{pass_count}`",
        f"- 부분 통과: `{partial_count}`",
        f"- 실패: `{fail_count}`",
        f"- k: `{args.k}`",
        f"- max-distance: `{args.max_distance}`",
        f"- chat-model: `{args.chat_model}`",
        f"- embedding-model: `{args.embedding_model}`",
        "",
        "## 요약",
        "",
        "| ID | 유형 | 질문 | 판정 | 검색 건수 | 메모 |",
        "|---|---|---|---|---:|---|",
    ]

    for item in results:
        memo = "; ".join(item.notes) if item.notes else "-"
        lines.append(
            f"| {item.question_id} | {item.category}/{item.subtype} | {item.question} | {item.verdict} | {item.retrieval_count} | {memo} |"
        )

    lines.extend(["", "## 상세 결과", ""])
    for item in results:
        lines.extend(
            [
                f"### {item.question_id}",
                f"- 질문: {item.question}",
                f"- 판정: {item.verdict}",
                f"- 기대 동작: {item.expected_behavior}",
                f"- 검색 제목: {', '.join(item.retrieval_titles) if item.retrieval_titles else '없음'}",
                f"- 메모: {'; '.join(item.notes) if item.notes else '없음'}",
                "",
                "```text",
                item.answer,
                "```",
                "",
            ]
        )

    return "\n".join(lines)


def save_jsonl(path: Path, results: list[EvaluationResult]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for result in results:
            handle.write(json.dumps(result_to_dict(result), ensure_ascii=False) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="제주 설화·민담 챗봇 평가 실행기")
    parser.add_argument(
        "--questions-path",
        type=Path,
        default=Path("data/processed/evaluation_questions.jsonl"),
        help="평가 질문셋 JSONL 경로",
    )
    parser.add_argument("--limit", type=int, default=None, help="앞에서부터 일부 질문만 실행")
    parser.add_argument("--source", choices=["legend", "folktale"], default=None)
    parser.add_argument("--k", type=int, default=5)
    parser.add_argument("--chat-model", default="gpt-4o")
    parser.add_argument("--embedding-model", default=EMBEDDING_MODEL)
    parser.add_argument("--collection-name", default=DEFAULT_COLLECTION_NAME)
    parser.add_argument("--memory-turns", type=int, default=0)
    parser.add_argument("--max-distance", type=float, default=0.62)
    args = parser.parse_args()

    EVALUATIONS_DIR.mkdir(parents=True, exist_ok=True)
    run_id = utc_now_iso().replace(":", "-")
    jsonl_path = EVALUATIONS_DIR / f"{run_id}.jsonl"
    md_path = EVALUATIONS_DIR / f"{run_id}.md"

    questions = load_questions(args.questions_path)
    if args.limit is not None:
        questions = questions[: args.limit]

    client = get_openai_client()
    collection = get_chroma_collection(args.collection_name)

    results: list[EvaluationResult] = []
    for item in questions:
        source = normalize_source_hint(item.get("source_hint"), args.source)
        chunks, answer = answer_question(
            client,
            collection,
            question=str(item["question"]),
            source=source,
            k=args.k,
            embedding_model=args.embedding_model,
            chat_model=args.chat_model,
            memory_turns=args.memory_turns,
            max_distance=args.max_distance,
            history=[],
        )
        titles, codes = summarize_chunks(chunks)
        verdict, notes = evaluate_answer(item, chunks, answer)
        result = EvaluationResult(
            question_id=str(item["id"]),
            question=str(item["question"]),
            category=str(item.get("category", "")),
            subtype=str(item.get("subtype", "")),
            source_hint=str(item.get("source_hint", "all")),
            expected_behavior=str(item.get("expected_behavior", "")),
            expected_keywords=[str(keyword) for keyword in item.get("expected_keywords", [])],
            rejection_expected=bool(item.get("rejection_expected", False)),
            retrieval_count=len(chunks),
            retrieval_titles=titles,
            retrieval_codes=codes,
            answer=answer,
            verdict=verdict,
            notes=notes,
        )
        results.append(result)
        print(f"[ok] {result.question_id} verdict={result.verdict} retrieval={result.retrieval_count}")

    save_jsonl(jsonl_path, results)
    md_path.write_text(render_markdown(results, run_id=run_id, args=args), encoding="utf-8")

    print(f"saved jsonl={jsonl_path}")
    print(f"saved markdown={md_path}")


if __name__ == "__main__":
    main()
