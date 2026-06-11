"""장소명 기반 설화 RAG 검색 — chat.py와 travel.py에서 공유."""
from services.db import get_chroma_collection, embed_query


def search_folklore_by_place(place_name: str, n: int = 3) -> list[str]:
    """장소명으로 ChromaDB를 검색해 관련 설화 요약 반환.

    장소 매핑된 397 설화·민담 (is_mapped=True) 만 검색 대상으로 제한하여
    장소 정합성을 보장한다. 매핑 SSoT 는 SQLite `place_folklore_mapping`
    테이블의 `source != 'gps_assist'` 조건 (이름 매치 + 채록지) distinct
    folklore_code_no.
    """
    collection = get_chroma_collection()
    try:
        results = collection.query(
            query_embeddings=[embed_query(place_name)],
            n_results=n,
            where={"is_mapped": True},
            include=["documents", "metadatas", "distances"],
        )
    except Exception:
        return []

    out = []
    for doc, meta, dist in zip(
        results["documents"][0],
        results["metadatas"][0],
        results["distances"][0],
    ):
        if dist < 0.75:
            title = meta.get("title", "")
            place = meta.get("primary_place", "")
            out.append(f"[{title} / {place}] {doc[:200]}")
    return out
