"""오디 제주 원본 데이터를 가공 없이 파일로 뽑는다.

앱이 쓰려고 가공한 것(`data/exports/오디_제주_*.csv`)이 아니라, **관광공사가 준 그대로**가
필요할 때 쓴다. 외부 도구·다른 사람에게 데이터를 보여줄 때가 그런 경우다.

    .venv/bin/python3 scripts/dump_odii_raw.py

⚠️ 결과물 중 `오디_원본_API응답.{json,csv}`에는 **대본 전문**이 들어 있다.
저장소에 커밋하지 않는다(`.gitignore`에 있다) — `backend/routers/odii.py`의
「대본은 저장하지 않는다」 결정과 충돌한다. 필요할 때 다시 뽑아 쓰는 파일이다.
"""
from __future__ import annotations

import csv
import json
import pathlib
import sqlite3
import sys

BASE = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE / "backend"))

from routers.tourist import _kto_get  # noqa: E402

OUT = BASE / "data" / "exports"

# backend/routers/odii.py 와 같은 값. 제주 전역이 한 번에 들어온다.
JEJU_CENTER = (126.55, 33.38)
JEJU_RADIUS = 50000


def fetch() -> tuple[dict, list[dict]]:
    data = _kto_get("Odii", "storyLocationBasedList", {
        "langCode": "ko",
        "mapX": JEJU_CENTER[0],
        "mapY": JEJU_CENTER[1],
        "radius": JEJU_RADIUS,
        "numOfRows": 300,
        "pageNo": 1,
    })
    body = data.get("response", {}).get("body", data)
    items = body.get("items")
    if isinstance(items, dict):
        items = items.get("item")
    return data, items or []


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data, items = fetch()

    # ① 응답 전체를 손대지 않고 그대로
    (OUT / "오디_원본_API응답.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    # ② 같은 내용을 표로. 필드명·값 모두 원본 그대로 둔다
    fields = list(items[0].keys())
    with open(OUT / "오디_원본_API응답.csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for it in items:
            w.writerow({k: it.get(k, "") for k in fields})

    # ③ 우리 DB에 저장된 형태 그대로(대본은 애초에 없다)
    conn = sqlite3.connect(BASE / "storage" / "metadata.db")
    conn.row_factory = sqlite3.Row
    rows = list(conn.execute(
        "SELECT * FROM odii_places ORDER BY CAST(stid AS INTEGER)"))
    with open(OUT / "오디_원본_DB테이블.csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(rows[0].keys())
        for r in rows:
            w.writerow(list(r))

    print(f"API 응답 {len(items)}건 · {len(fields)}필드 → {fields}")
    print(f"DB 테이블 {len(rows)}행")
    print(f"대본 있음 {sum(1 for i in items if (i.get('script') or '').strip())}건 · "
          f"음성 있음 {sum(1 for i in items if (i.get('audioUrl') or '').strip())}건 · "
          f"사진 있음 {sum(1 for i in items if (i.get('imageUrl') or '').strip())}건")


if __name__ == "__main__":
    main()
