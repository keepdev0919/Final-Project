"""기존 ChromaDB 청크 메타데이터에 has_gps 플래그를 백필.

재임베딩 없이 메타데이터만 업데이트한다. SSoT 는
`data/processed/folklore_gps.json` (lat/lng 유효 기준).
"""
from __future__ import annotations

import json
from pathlib import Path

import chromadb

ROOT = Path(__file__).resolve().parent.parent
GPS_FOLKLORE_JSON = ROOT / "data" / "processed" / "folklore_gps.json"
VECTOR_DB_DIR = ROOT / "storage" / "vector_db"
COLLECTION_NAME = "jeju_folklore_chunks"

# ChromaDB 의 update() 는 batch 가 너무 크면 메모리/내부 한계에 걸릴 수 있으므로
# 안전한 배치 사이즈로 나눠 처리.
BATCH_SIZE = 500


def load_gps_attached_codes() -> set[str]:
    if not GPS_FOLKLORE_JSON.exists():
        raise FileNotFoundError(f"GPS folklore SSoT not found: {GPS_FOLKLORE_JSON}")
    with GPS_FOLKLORE_JSON.open("r", encoding="utf-8") as fp:
        data = json.load(fp)
    return {
        entry["code_no"]
        for entry in data
        if entry.get("code_no") and entry.get("lat") is not None and entry.get("lng") is not None
    }


def main() -> None:
    gps_codes = load_gps_attached_codes()
    print(f"[info] GPS-attached code_no count: {len(gps_codes)}")

    client = chromadb.PersistentClient(path=str(VECTOR_DB_DIR))
    collection = client.get_collection(COLLECTION_NAME)
    total = collection.count()
    print(f"[info] collection={COLLECTION_NAME} total_chunks={total}")

    result = collection.get(include=["metadatas"])
    ids = result["ids"]
    metadatas = result["metadatas"]

    true_count = 0
    false_count = 0
    new_metadatas: list[dict] = []
    for meta in metadatas:
        # 사본을 만들어 mutate (원본 dict 가 ChromaDB 내부와 공유될 수 있어 안전).
        new_meta = dict(meta)
        flag = new_meta.get("code_no") in gps_codes
        new_meta["has_gps"] = flag
        new_metadatas.append(new_meta)
        if flag:
            true_count += 1
        else:
            false_count += 1

    print(f"[info] computed has_gps=True: {true_count}, has_gps=False: {false_count}")

    # 배치 업데이트
    updated = 0
    for start in range(0, len(ids), BATCH_SIZE):
        end = start + BATCH_SIZE
        collection.update(ids=ids[start:end], metadatas=new_metadatas[start:end])
        updated += end - start if end <= len(ids) else len(ids) - start
        print(f"[ok] updated batch {start}~{min(end, len(ids))}")

    print(f"[done] updated total chunks: {len(ids)}")

    # 검증: where 필터로 카운트 확인
    verify_true = collection.get(where={"has_gps": True}, include=[])
    verify_false = collection.get(where={"has_gps": False}, include=[])
    print(
        f"[verify] post-migration has_gps=True={len(verify_true['ids'])} "
        f"has_gps=False={len(verify_false['ids'])}"
    )


if __name__ == "__main__":
    main()
