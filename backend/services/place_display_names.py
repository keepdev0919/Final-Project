"""코스 장소의 표시용 이름.

원본 이름(`course_places.place_name`)은 **identity**다. 장소 메타 조회 키이자
사진 캐시 키라 건드리지 않는다. 화면에 내보낼 때만 여기 이름으로 바꾼다.

    성산일출봉(UNESCO 세계자연유산)  →  성산일출봉
    이호테우해수욕장_old            →  이호테우해수욕장

매핑은 `backend/scripts/build_place_display_names.py`가 만든다. 그 스크립트의
문서에 규칙과 예외(괄호가 구분 정보인 경우 등)가 적혀 있다.
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

JSON_PATH = Path(__file__).parent.parent.parent / "data" / "course_place_display_names.json"


@lru_cache(maxsize=1)
def _load() -> dict:
    if not JSON_PATH.exists():
        return {"display_names": {}, "closed": []}
    return json.loads(JSON_PATH.read_text(encoding="utf-8"))


def display_names() -> dict[str, str]:
    """원본 이름 → 표시 이름. 바꿀 필요가 없는 이름은 들어 있지 않다."""
    return _load()["display_names"]


def shown(place_name: str) -> str:
    """화면에 쓸 이름. 매핑이 없으면 원본 그대로."""
    return display_names().get(place_name, place_name)


@lru_cache(maxsize=1)
def origin_names() -> dict[str, str]:
    """표시 이름 → 원본 이름. 사진 캐시가 원본 이름으로 쌓여 있어 필요하다.

    표시 이름 하나에 원본이 여럿 붙는 경우(`소노벨제주` ← `소노벨제주(미공개)`)는
    아무거나 하나면 된다. 어차피 같은 장소다.
    """
    return {shown_name: origin for origin, shown_name in display_names().items()}
