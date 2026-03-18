from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sqlite3
import urllib.error
import urllib.request
from typing import Iterable

from common import (
    DEFAULT_COLLECTION_NAME,
    EMBEDDING_MODEL,
    VECTOR_DB_DIR,
    get_db_connection,
    load_env_file,
)


OPENAI_EMBEDDING_URL = "https://api.openai.com/v1/embeddings"
OPENAI_EMBEDDING_DIMS = 1536


def fetch_chunks(source_type: str | None, limit: int | None) -> list[sqlite3.Row]:
    query = """
        SELECT
            chunk_id,
            doc_id,
            source_type,
            code_no,
            title,
            category,
            category2,
            tags,
            chunk_index,
            text
        FROM chunks
    """
    params: list[object] = []
    clauses = []

    if source_type:
        clauses.append("source_type = ?")
        params.append(source_type)

    if clauses:
        query += " WHERE " + " AND ".join(clauses)

    query += " ORDER BY source_type, code_no, chunk_index"

    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)

    with get_db_connection() as conn:
        return conn.execute(query, params).fetchall()


def chunked(items: list[sqlite3.Row], batch_size: int) -> Iterable[list[sqlite3.Row]]:
    for start in range(0, len(items), batch_size):
        yield items[start : start + batch_size]


def build_dummy_embedding(text: str, dims: int = OPENAI_EMBEDDING_DIMS) -> list[float]:
    vector: list[float] = []
    seed = text.encode("utf-8")
    while len(vector) < dims:
        seed = hashlib.sha256(seed).digest()
        for idx in range(0, len(seed), 4):
            chunk = seed[idx : idx + 4]
            if len(chunk) < 4:
                continue
            raw = int.from_bytes(chunk, "big", signed=False)
            value = (raw / 0xFFFFFFFF) * 2.0 - 1.0
            vector.append(value)
            if len(vector) == dims:
                break

    norm = math.sqrt(sum(value * value for value in vector)) or 1.0
    return [value / norm for value in vector]


def embed_with_dummy(texts: list[str]) -> list[list[float]]:
    return [build_dummy_embedding(text) for text in texts]


def require_openai_key() -> str:
    load_env_file()
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY environment variable is required for provider=openai")
    return api_key


def embed_with_openai(texts: list[str], model: str) -> list[list[float]]:
    api_key = require_openai_key()
    payload = json.dumps({"input": texts, "model": model}).encode("utf-8")
    request = urllib.request.Request(
        OPENAI_EMBEDDING_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"OpenAI embedding request failed: {exc.code} {detail}") from exc

    data = body.get("data", [])
    if len(data) != len(texts):
        raise RuntimeError(f"Unexpected embedding response count: expected {len(texts)}, got {len(data)}")

    return [item["embedding"] for item in data]


def get_embedder(provider: str, model: str):
    if provider == "dummy":
        return embed_with_dummy
    if provider == "openai":
        return lambda texts: embed_with_openai(texts, model)
    raise ValueError(f"Unsupported provider: {provider}")


def get_chroma_collection(collection_name: str):
    try:
        import chromadb
    except ImportError as exc:
        raise RuntimeError("chromadb is not installed. Install dependencies from requirements.txt first.") from exc

    client = chromadb.PersistentClient(path=str(VECTOR_DB_DIR))
    return client, client.get_or_create_collection(
        name=collection_name,
        metadata={"hnsw:space": "cosine"},
    )


def get_existing_ids(collection, ids: list[str]) -> set[str]:
    if not ids:
        return set()
    result = collection.get(ids=ids)
    return set(result.get("ids", []))


def delete_collection_if_requested(client, collection_name: str, reset: bool) -> None:
    if not reset:
        return
    try:
        client.delete_collection(collection_name)
    except Exception:
        pass


def ingest_rows(rows: list[sqlite3.Row], *, provider: str, model: str, collection_name: str, batch_size: int, reset: bool) -> tuple[int, int]:
    client, collection = get_chroma_collection(collection_name)
    if reset:
        delete_collection_if_requested(client, collection_name, reset=True)
        _, collection = get_chroma_collection(collection_name)

    embed_texts = get_embedder(provider, model)
    processed = 0
    skipped = 0

    for batch in chunked(rows, batch_size):
        ids = [row["chunk_id"] for row in batch]
        existing_ids = get_existing_ids(collection, ids)
        pending = [row for row in batch if row["chunk_id"] not in existing_ids]
        skipped += len(batch) - len(pending)

        if not pending:
            print(f"[skip] batch size={len(batch)} all ids already exist")
            continue

        texts = [row["text"] for row in pending]
        embeddings = embed_texts(texts)
        metadatas = []
        documents = []
        insert_ids = []

        for row, embedding in zip(pending, embeddings):
            _ = embedding  # keeps zip explicit for readability
            insert_ids.append(row["chunk_id"])
            documents.append(row["text"])
            metadatas.append(
                {
                    "doc_id": row["doc_id"],
                    "source_type": row["source_type"],
                    "code_no": row["code_no"],
                    "title": row["title"],
                    "category": row["category"] or "",
                    "category2": row["category2"] or "",
                    "tags": row["tags"] or "",
                    "chunk_index": int(row["chunk_index"]),
                    "embedding_provider": provider,
                    "embedding_model": model,
                }
            )

        collection.add(
            ids=insert_ids,
            documents=documents,
            metadatas=metadatas,
            embeddings=embeddings,
        )
        processed += len(insert_ids)
        print(
            f"[ok] ingested batch pending={len(insert_ids)} skipped_existing={len(batch) - len(insert_ids)} "
            f"processed_total={processed}"
        )

    return processed, skipped


def main() -> None:
    parser = argparse.ArgumentParser(description="SQLite chunks를 ChromaDB에 임베딩 적재")
    parser.add_argument("--source", choices=["legend", "folktale"], default=None)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--batch-size", type=int, default=100)
    parser.add_argument("--provider", choices=["openai", "dummy"], default="openai")
    parser.add_argument("--model", default=EMBEDDING_MODEL)
    parser.add_argument("--collection-name", default=DEFAULT_COLLECTION_NAME)
    parser.add_argument("--reset", action="store_true", help="기존 컬렉션을 삭제하고 다시 적재")
    args = parser.parse_args()

    rows = fetch_chunks(args.source, args.limit)
    print(
        f"ingest candidates={len(rows)} source={args.source or 'all'} "
        f"provider={args.provider} collection={args.collection_name}"
    )

    processed, skipped = ingest_rows(
        rows,
        provider=args.provider,
        model=args.model,
        collection_name=args.collection_name,
        batch_size=args.batch_size,
        reset=args.reset,
    )
    print(f"done processed={processed} skipped_existing={skipped}")


if __name__ == "__main__":
    main()
