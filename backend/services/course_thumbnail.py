"""코스 카드에 붙는 대표 사진.

## 어느 장소의 사진인가

**제목에 이미 나와 있는 그 장소**다. 카드가 「곽지해수욕장 외 5곳」이라고 말하는데
사진이 딴 데면 카드가 두 말을 한다.

대표 장소는 코스를 만들 때 이미 정해졌다
(`scripts/build_curated_courses.py::_make_title`) — 교통시설을 뺀 뒤 관광지로 분류된
곳 우선, 없으면 첫 방문지. 그 결과가 제목에 박힌다:

    {권역} {일수}일 · {대표장소} 외 {N}곳
    {권역} {일수}일 · {대표장소}
    {권역} {일수}일 코스              ← 대표 장소를 못 고른 코스

## 왜 제목에서 되뽑나

`is_attraction` 은 빌드 스크립트가 읽는 **파일**(`data/places.json`)에만 있고 DB에는
없다. 서빙 중에 같은 규칙을 다시 돌릴 수 없다. 대신 그 규칙의 **결과**가 제목에
남아 있으므로 그것을 되읽는다.

⚠️ 그래서 `_make_title` 의 형식을 바꾸면 여기가 조용히 깨진다. 사진이 사라지는 게
아니라 **엉뚱한 장소의 사진이 붙는다.** `tests/test_course_thumbnail.py` 가 두 함수의
형식을 함께 못 박는다.

## 왜 여기서 KTO를 부르지 않나

대표 장소는 1,255개 코스를 통틀어 265종류뿐이다. 미리 데워두면
(`scripts/warm_course_thumbnails.py`) 캐시만 읽어도 거의 다 덮인다. 요청마다 KTO를
부르면 목록 한 번에 다섯 곳을 조회하게 되어 첫 화면이 눈에 띄게 느려진다.
"""
import json as _json
import logging
import re

from services.image_url import to_https
from services.place_display_names import origin_names

logger = logging.getLogger(__name__)

_REST_SUFFIX = re.compile(r"\s*외\s*\d+\s*곳$")



def lead_place_name(title: str) -> str | None:
    """코스 제목에서 대표 장소 이름을 되뽑는다. 못 뽑으면 None."""
    if " · " not in title:
        return None
    tail = title.split(" · ", 1)[1]
    name = _REST_SUFFIX.sub("", tail).strip()
    return name or None


def thumbnail_for(conn, place_name: str | None) -> str | None:
    """장소 이름으로 캐시에서 대표 사진 URL을 꺼낸다. 없으면 None.

    좌표는 보지 않는다 — 같은 이름의 장소가 코스마다 소수점 아래가 다른 좌표로
    들어 있어서, 좌표까지 맞추면 캐시가 있어도 못 찾는다.

    **원본 이름으로도 한 번 더 찾는다.** 코스 제목은 정리된 표시 이름을 쓰는데
    (`성산일출봉`), 사진 캐시는 KTO·비짓제주에서 받은 원본 이름으로 쌓여 있어
    (`성산일출봉(UNESCO 세계자연유산)`) 한쪽만 보면 276개 코스가 사진을 잃는다.
    """
    if not place_name:
        return None
    candidates = [place_name]
    origin = origin_names().get(place_name)
    if origin:
        candidates.append(origin)
    row = None
    for name in candidates:
        try:
            row = conn.execute(
                "SELECT images FROM place_detail_cache "
                "WHERE name = ? AND images IS NOT NULL AND images != '' AND images != '[]' "
                "LIMIT 1",
                (name,),
            ).fetchone()
        except Exception as exc:
            logger.warning("코스 썸네일 조회 실패 (%s): %s", name, exc)
            return None
        if row:
            break
    if not row:
        return None
    try:
        images = _json.loads(row["images"] or "[]")
    except Exception:
        return None
    if isinstance(images, list) and images and isinstance(images[0], str) and images[0]:
        # KTO 는 http 로 준다. 그대로 내보내면 iOS 가 막아 사진이 조용히 사라진다.
        return to_https(images[0])
    return None


def attach_thumbnails(conn, courses: list[dict]) -> None:
    """코스 목록에 `thumbnail` 을 채워 넣는다 (제자리 수정)."""
    for c in courses:
        c["thumbnail"] = thumbnail_for(conn, lead_place_name(c.get("title", "")))
