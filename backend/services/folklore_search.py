"""장소명 기반 설화 RAG 검색 — chat.py와 travel.py에서 공유."""
from services.db import get_chroma_collection, embed_query


def search_folklore_by_place(place_name: str, n: int = 3) -> list[str]:
    """장소명으로 ChromaDB를 검색해 관련 설화 요약 반환."""
    collection = get_chroma_collection()
    try:
        results = collection.query(
            query_embeddings=[embed_query(place_name)],
            n_results=n,
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
