"""기존 ChromaDB 청크 메타데이터의 has_gps 키를 is_mapped 키로 교체.

SSoT 는 SQLite `place_folklore_mapping` 테이블의
`source != 'gps_assist'` 조건 distinct folklore_code_no (397건).

- 재임베딩 없이 메타데이터만 update.
- 기존 has_gps 키는 제거.
- 새 is_mapped 키 추가 (값: code_no 가 397 set 에 포함되는지).
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

import chromadb

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "storage" / "metadata.db"
VECTOR_DB_DIR = ROOT / "storage" / "vector_db"
COLLECTION_NAME = "jeju_folklore_chunks"

# ChromaDB update() 안전 배치 사이즈.
BATCH_SIZE = 500


def load_mapped_code_set() -> set[str]:
    """place_folklore_mapping 에서 진짜 장소 매핑된 code_no 397건 set."""
    if not DB_PATH.exists():
        raise FileNotFoundError(f"metadata.db not found: {DB_PATH}")
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            """
            SELECT DISTINCT folklore_code_no
            FROM place_folklore_mapping
            WHERE source != 'gps_assist'
            """
        ).fetchall()
    finally:
        conn.close()
    return {row["folklore_code_no"] for row in rows if row["folklore_code_no"]}


def main() -> None:
    mapped_codes = load_mapped_code_set()
    print(f"[info] place-mapped code_no count (SSoT): {len(mapped_codes)}")

    client = chromadb.PersistentClient(path=str(VECTOR_DB_DIR))
    collection = client.get_collection(COLLECTION_NAME)
    total = collection.count()
    print(f"[info] collection={COLLECTION_NAME} total_chunks={total}")

    result = collection.get(include=["metadatas"])
    ids = result["ids"]
    metadatas = result["metadatas"]

    true_count = 0
    false_count = 0
    had_has_gps = 0
    new_metadatas: list[dict] = []
    for meta in metadatas:
        # 원본 dict 가 ChromaDB 내부와 공유될 수 있어 사본 생성 후 mutate.
        new_meta = dict(meta)
        # ChromaDB update() 는 metadata 를 merge 하므로, 키 제거를 명시하려면
        # None 값으로 patch 해야 한다 (Chroma 가 내부적으로 None 을 삭제로 처리).
        if "has_gps" in new_meta:
            had_has_gps += 1
        new_meta["has_gps"] = None
        flag = new_meta.get("code_no") in mapped_codes
        new_meta["is_mapped"] = flag
        new_metadatas.append(new_meta)
        if flag:
            true_count += 1
        else:
            false_count += 1

    print(
        f"[info] computed is_mapped=True: {true_count}, is_mapped=False: {false_count}, "
        f"has_gps present in {had_has_gps} chunks (to be removed)"
    )

    # 배치 update.
    for start in range(0, len(ids), BATCH_SIZE):
        end = start + BATCH_SIZE
        collection.update(ids=ids[start:end], metadatas=new_metadatas[start:end])
        print(f"[ok] updated batch {start}~{min(end, len(ids))}")

    print(f"[done] updated total chunks: {len(ids)}")

    # 검증: where 필터 카운트 확인.
    verify_true = collection.get(where={"is_mapped": True}, include=[])
    verify_false = collection.get(where={"is_mapped": False}, include=[])
    print(
        f"[verify] post-migration is_mapped=True={len(verify_true['ids'])} "
        f"is_mapped=False={len(verify_false['ids'])}"
    )

    # has_gps 키가 남아있는지 확인. 비어 있어야 정상.
    try:
        leftover_true = collection.get(where={"has_gps": True}, include=[])
        leftover_false = collection.get(where={"has_gps": False}, include=[])
        leftover = len(leftover_true["ids"]) + len(leftover_false["ids"])
        print(f"[verify] leftover has_gps chunks: {leftover}")
    except Exception as exc:
        print(f"[verify] has_gps key fully removed (where query failed as expected): {exc}")


if __name__ == "__main__":
    main()
