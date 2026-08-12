"""storage/metadata.db 의 metadata 테이블을 data/processed/folklore_gps.json 으로 복구.

metadata.db 는 .gitignore 된 빌드 산출물이라, 새 체크아웃/파일 이동 후 비어 있을 수 있다.
이 스크립트는 커밋된 folklore_gps.json(228건, 지오코딩 완료) 으로 앱 라우터가 필요로 하는
metadata 테이블을 API 호출 없이 재생성한다. 멱등(idempotent) — 여러 번 실행해도 안전.

사용:
    python scripts/rebuild_metadata_from_gps.py

앱 라우터가 metadata 에서 SELECT 하는 컬럼:
    code_no, title, source_type, primary_place, lat, lng, summary, hook(지연 생성)
"""
from __future__ import annotations

import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "storage" / "metadata.db"
GPS_JSON = ROOT / "data" / "processed" / "folklore_gps.json"


def main() -> None:
    rows = json.loads(GPS_JSON.read_text(encoding="utf-8"))
    print(f"소스: {GPS_JSON.relative_to(ROOT)} → {len(rows)}건")

    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS metadata (
            source_type   TEXT NOT NULL,
            code_no       TEXT NOT NULL,
            title         TEXT NOT NULL,
            primary_place TEXT,
            lat           REAL,
            lng           REAL,
            summary       TEXT,
            category      TEXT,
            hook          TEXT,
            PRIMARY KEY (source_type, code_no)
        )
        """
    )

    inserted = 0
    for r in rows:
        conn.execute(
            """
            INSERT INTO metadata
                (source_type, code_no, title, primary_place, lat, lng, summary, category)
            VALUES (:source_type, :code_no, :title, :primary_place, :lat, :lng, :summary, :category)
            ON CONFLICT(source_type, code_no) DO UPDATE SET
                title=excluded.title,
                primary_place=excluded.primary_place,
                lat=excluded.lat,
                lng=excluded.lng,
                summary=excluded.summary,
                category=excluded.category
            """,
            {
                "source_type": r.get("source_type") or "legend",
                "code_no": r["code_no"],
                "title": r["title"],
                "primary_place": r.get("primary_place"),
                "lat": r.get("lat"),
                "lng": r.get("lng"),
                "summary": r.get("summary"),
                "category": r.get("final_category"),
            },
        )
        inserted += 1

    conn.commit()
    total = conn.execute("SELECT COUNT(*) FROM metadata").fetchone()[0]
    with_gps = conn.execute(
        "SELECT COUNT(*) FROM metadata WHERE lat IS NOT NULL AND lng IS NOT NULL"
    ).fetchone()[0]
    conn.close()
    print(f"완료: metadata {total}건 (upsert {inserted}) · GPS 보유 {with_gps}건 → {DB_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
