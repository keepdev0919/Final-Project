"""코스 카드에 쓸 대표 사진을 미리 받아 캐시에 채운다.

## 왜 미리 받나

코스 목록 응답은 `place_detail_cache` 만 읽는다 (`services/course_thumbnail.py`).
요청마다 KTO 를 부르면 「이런 코스는 어때요?」 다섯 장을 그릴 때마다 KTO 조회가
다섯 번 붙어 첫 화면이 눈에 띄게 느려진다.

미리 받아도 되는 이유는 **대표 장소가 몇 개 없기 때문**이다 — 코스 1,255개를
통틀어 265종류다. 한 번 돌려두면 거의 모든 카드가 덮인다.

## 쓰는 법

    .venv/bin/python3 backend/scripts/warm_course_thumbnails.py          # 전체
    .venv/bin/python3 backend/scripts/warm_course_thumbnails.py --limit 20   # 맛보기

이미 사진이 있는 장소는 건너뛴다. 중간에 끊겨도 다시 돌리면 이어서 채운다.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"
sys.path.insert(0, str(BASE_DIR / "backend"))

from routers.place import _fetch_detail, _fetch_images, find_content_id  # noqa: E402
from services.course_thumbnail import lead_place_name  # noqa: E402

# KTO 를 몰아치지 않으려고 조회 사이에 쉰다. 265곳이면 전체 4분 남짓이다.
PAUSE_SEC = 0.8


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="이만큼만 처리 (0이면 전체)")
    args = ap.parse_args()

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # 대표 장소 목록 — 제목에서 되뽑고, 좌표는 course_places 에서 가져온다.
    titles = [r["title"] for r in conn.execute("SELECT title FROM curated_courses")]
    names = sorted({n for n in (lead_place_name(t) for t in titles) if n})
    print(f"코스 {len(titles)}개 → 대표 장소 {len(names)}종류")

    todo: list[tuple[str, float, float]] = []
    for name in names:
        has = conn.execute(
            "SELECT 1 FROM place_detail_cache WHERE name = ? "
            "AND images IS NOT NULL AND images != '' AND images != '[]' LIMIT 1",
            (name,),
        ).fetchone()
        if has:
            continue
        coord = conn.execute(
            "SELECT lat, lng FROM course_places WHERE place_name = ? "
            "AND lat IS NOT NULL AND lng IS NOT NULL LIMIT 1",
            (name,),
        ).fetchone()
        if not coord:
            continue
        todo.append((name, coord["lat"], coord["lng"]))

    if args.limit:
        todo = todo[: args.limit]
    print(f"받을 것 {len(todo)}곳 (이미 있는 것은 건너뜀)")

    ok = miss = fail = 0
    for i, (name, lat, lng) in enumerate(todo, 1):
        try:
            # 이름이 맞는 것만 받는다 — 대표 장소가 식당일 수도 있어 종류는 안 좁힌다.
            found = find_content_id(name, lat, lng)
            if not found:
                miss += 1
                print(f"  [{i}/{len(todo)}] {name} — KTO 에 없음")
                time.sleep(PAUSE_SEC)
                continue
            content_id, content_type_id = found
            detail = _fetch_detail(content_id)
            images = _fetch_images(content_id)
            first = detail.get("firstimage", "")
            if first and first not in images:
                images = [first] + images
            if not images:
                miss += 1
                print(f"  [{i}/{len(todo)}] {name} — 사진 없음")
                time.sleep(PAUSE_SEC)
                continue

            conn.execute(
                """INSERT OR REPLACE INTO place_detail_cache
                   (name, lat, lng, overview, images, address, tel,
                    open_time, rest_date, use_fee, parking, content_type_id, cached_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (name, round(lat, 5), round(lng, 5),
                 detail.get("overview", ""),
                 json.dumps(images, ensure_ascii=False),
                 detail.get("addr1", ""), detail.get("tel", ""),
                 "", "", "", "", content_type_id, time.time()),
            )
            conn.commit()
            ok += 1
            print(f"  [{i}/{len(todo)}] {name} — 사진 {len(images)}장")
        except Exception as exc:
            fail += 1
            print(f"  [{i}/{len(todo)}] {name} — 실패: {exc}")
        time.sleep(PAUSE_SEC)

    print(f"\n받음 {ok} · KTO 에 없거나 사진 없음 {miss} · 실패 {fail}")


if __name__ == "__main__":
    main()
