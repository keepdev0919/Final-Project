"""코스 장소의 **표시용 이름**을 만든다.

실행:
    .venv/bin/python backend/scripts/build_place_display_names.py

## 왜 필요한가

`course_places.place_name`은 비짓제주 원본 이름 그대로다. 그게 코스 제목
(`build_curated_courses.py::_make_title`)에도, 앱의 코스 상세·지도에도 그대로 나온다.
그런데 원본에 이런 것이 섞여 있다:

    성산일출봉(UNESCO 세계자연유산)              2,668개 코스
    만장굴(안전점검 및 내부공사로 운영중단)          967개 코스
    이호테우해수욕장_old                          237개 코스
    수목원테마파크_2025.11.11 영업종료(리모델링공사) / 2026.03.01 재오픈 예정

3,279개 이름 중 **239개**가 이 상태이고, 코스로 치면 13,536건에 걸린다.
첫 화면은 이런 제목을 아예 걸러내고 있었는데(`run_featured_courses`), 그러느라
멀쩡한 코스 1,200개가 같이 빠졌다. 이름만 고치면 다 살아난다.

원본 이름은 **identity**라 건드리지 않는다 (장소 메타 조회 키로 쓰인다).
표시용 이름을 따로 만들어 화면에서만 쓴다 — `places` 테이블이 `place_key`와
`display_name`을 나눠 둔 것과 같은 구조다.

## 규칙

1. `_` 뒤를 자른다 — `이호테우해수욕장_old`, `수목원테마파크_2025.11.11 …`
2. `[...]`를 뗀다 — `제주공룡랜드[휴장중]`
3. `(...)`를 뗀다 — `성산일출봉(UNESCO 세계자연유산)`

단, **3번에는 예외가 있다.** 괄호를 뗐더니 다른 장소와 이름이 같아지는 경우,
그 괄호는 장식이 아니라 **구분 정보**다:

    민오름(조천읍) · 민오름(오라동) · 민오름(구좌읍)      ← 서로 다른 오름
    고집돌우럭(제주공항점) · 고집돌우럭(중문)              ← 서로 다른 지점

이런 이름은 원본 그대로 둔다. 반대로 괄호 안이 비짓제주 운영 메모인 경우
(`미공개`, `중복 콘텐츠로 미공개`)는 충돌하더라도 떼서 원본과 합친다 —
`소노벨제주(미공개)`와 `소노벨제주`는 같은 곳이다.

## 폐업 장소

이름에서 상태 표기는 떼되(`명월국민학교(폐업)` → `명월국민학교`), 그 장소를
**코스 제목의 대표 장소로는 쓰지 않는다.** 「북부 2일 · 명월국민학교 외 5곳」처럼
없어진 곳이 코스를 대표하면 안 된다. 코스에서 장소를 빼지는 않는다 — 실제
운영정보는 Place Detail의 한국관광공사 OpenAPI가 담당한다.

**폐업·철거만 본다.** 휴장·공사·점검은 일시적이라 제외하지 않는다. 예를 들어
`만장굴(안전점검 및 내부공사로 운영중단)`은 967개 코스에 걸린 대표 관광지인데,
공사가 끝났는지 여기서는 알 수 없으므로 이름만 정리하고 그대로 쓴다.

`영업종료`도 폐업으로 치지 않는다. 이런 이름 때문이다:

    수목원테마파크_2025.11.11 영업종료(리모델링공사) / 2026.03.01 재오픈 예정

비짓제주가 적어둔 시점 정보인데 재오픈 예정일이 이미 지났다(오늘 2026-09-10).
낡은 안내를 근거로 장소를 내리지 않는다.
"""
from __future__ import annotations

import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent.parent
DB_PATH = BASE_DIR / "storage" / "metadata.db"
OUT_PATH = BASE_DIR / "data" / "course_place_display_names.json"

# 괄호 안이 이것이면 비짓제주 운영 메모다. 충돌하더라도 뗀다.
JUNK_PAREN = re.compile(r"미공개|중복\s*콘텐츠|중복콘텐츠")

# 이름에 이게 있으면 없어진 곳으로 본다. 휴장·공사·점검은 일시적이라 뺐다.
CLOSED = re.compile(r"폐업|철거")

# 괄호가 구분이 아니라 **옛 이름**인 경우. 떼서 원본과 합친다.
# 자동으로는 「민오름(조천읍)」과 구별할 수 없어 손으로 적는다.
ALIAS_PAREN = {
    "제주국제공항(정뜨르비행장)",
    "한모살 (표선백사장)",
}


def strip_decorations(name: str) -> str:
    """장식을 뗀 이름. 충돌 검사는 하지 않는다."""
    t = name.split("_")[0]
    t = re.sub(r"\[[^\]]*\]", "", t)
    t = re.sub(r"\([^)]*\)", "", t)
    return re.sub(r"\s+", " ", t).strip(" ,·-")


def main() -> None:
    if not DB_PATH.exists():
        sys.exit(f"❌ DB 없음: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    counts = {
        r["place_name"]: r["n"]
        for r in conn.execute(
            "SELECT place_name, COUNT(DISTINCT course_id) n FROM course_places "
            "WHERE in_jeju = 1 GROUP BY place_name"
        )
    }
    conn.close()
    print(f"제주 장소 이름 {len(counts)}개")

    # 1차: 장식을 뗀 결과로 묶어 충돌을 찾는다
    grouped: dict[str, list[str]] = defaultdict(list)
    for name in counts:
        grouped[strip_decorations(name)].append(name)

    display: dict[str, str] = {}
    kept: list[str] = []
    for stripped, originals in grouped.items():
        if not stripped:
            continue
        if len(originals) == 1:
            if originals[0] != stripped:
                display[originals[0]] = stripped
            continue

        # 충돌 — 운영 메모만 떼고, 진짜 구분 정보는 원본을 남긴다
        for name in originals:
            if JUNK_PAREN.search(name) or "_" in name or name in ALIAS_PAREN:
                display[name] = stripped
            elif name != stripped:
                kept.append(name)

    closed = sorted({display.get(n, n) for n in counts if CLOSED.search(n)})

    payload = {
        "_읽어보세요": [
            "코스 장소의 표시용 이름이다. 원본 이름(identity)은 course_places.place_name 그대로 둔다.",
            "backend/scripts/build_place_display_names.py 가 만든다. 손으로 고치지 말고 스크립트를 고쳐라.",
            "",
            "display_names — 화면에 이 이름으로 보여준다.",
            "keep_as_is   — 괄호가 구분 정보라 원본을 그대로 쓰는 이름. 참고용 기록이다.",
            "closed       — 폐업·휴장 표기가 있던 곳. 코스 제목의 대표 장소로 쓰지 않는다.",
        ],
        "display_names": dict(sorted(display.items())),
        "keep_as_is": sorted(kept),
        "closed": closed,
    }
    OUT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    affected = sum(counts[n] for n in display)
    print(f"  표시 이름 교체 {len(display)}개 (코스 {affected}건)")
    print(f"  원본 유지(구분 정보) {len(kept)}개")
    print(f"  폐업·휴장 {len(closed)}개")
    print(f"\n✅ {OUT_PATH.relative_to(BASE_DIR)}")


if __name__ == "__main__":
    main()
