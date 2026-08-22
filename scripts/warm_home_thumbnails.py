"""홈 장소 카드 사진을 미리 받아 둔다.

카드마다 KTO를 부르면 홈 한 번 열 때 호출이 10건 나가고 분당 한도에 걸린다.
그래서 사진 주소를 `home_places.thumbnail`에 박아 두고, 그걸 이 스크립트가 채운다.

    .venv/bin/python3 scripts/warm_home_thumbnails.py          # 상위 20곳
    .venv/bin/python3 scripts/warm_home_thumbnails.py 103      # 전체

**언제 돌리나** — 오디 목록을 갱신했거나(`POST /odii/sync`) 순위를 다시 계산한 뒤.
사진이 이미 있는 항목은 건너뛰므로 여러 번 돌려도 안전하다.

출시 전에 한 번은 돌려 둔다. 안 돌리면 홈 카드가 도트 아이콘 자리로 뜬다.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from services import home_places  # noqa: E402
from services.db import get_db_connection  # noqa: E402


def main() -> None:
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    conn = get_db_connection()
    home_places.ensure_built(conn)

    total = conn.execute("SELECT COUNT(*) FROM home_places").fetchone()[0]
    before = conn.execute(
        "SELECT COUNT(*) FROM home_places WHERE thumbnail IS NOT NULL"
    ).fetchone()[0]
    print(f"장소 {total}곳 · 사진 있음 {before}곳 → 상위 {limit}곳 시도")

    result = home_places.warm_thumbnails(conn, limit=limit)
    print(f"시도 {result['tried']}곳 · 새로 받음 {result['filled']}곳")

    for row in conn.execute(
        "SELECT rank, name, thumbnail FROM home_places ORDER BY rank LIMIT ?", (limit,)
    ):
        mark = "○" if row["thumbnail"] else "✗"
        print(f"  {mark} {row['rank'] + 1:>3}. {row['name']}")


if __name__ == "__main__":
    main()
