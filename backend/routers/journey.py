"""여정(장소 1개 = 유료 상품) 조회.

v1의 여정은 성산 1개다(설계 §9 "양산 지양"). 파일에서 읽는 이유는 콘텐츠가
원고에서 오기 때문이며, 이야기 본문·오디오는 묶음 B에서 이 위에 얹는다.

⚠️ 좌표를 **받지** 않는다. 위치 판정은 단말에서만 한다 (위치정보법, 설계 §6).
"""
from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from models.schemas import JourneySummary
from services.db import get_db_connection

BASE_DIR = Path(__file__).parent.parent.parent
JOURNEY_DIR = BASE_DIR / "data" / "journeys"

router = APIRouter(prefix="/journeys", tags=["journeys"])
limiter = Limiter(key_func=get_remote_address)


def _cached_photo(title: str) -> str | None:
    """KTO 관광사진 캐시에서 첫 장을 꺼낸다.

    카드 썸네일은 실사 사진이다(DESIGN.md §1). 여정 JSON에 사진 URL을 적어두지
    않는 이유: KTO 사진이 바뀌면 우리 파일이 낡는다. 장소 화면이 이미 채워 둔
    `place_detail_cache`를 재사용한다.

    ⚠️ 첫 장이 안내판 사진인 경우가 있다(성산 실측). 데모에 쓸 곳은 손으로 고르는
    게 낫다 → DESIGN.md §9.
    """
    if not title:
        return None
    try:
        conn = get_db_connection()
        row = conn.execute(
            "SELECT images FROM place_detail_cache "
            "WHERE name = ? AND images IS NOT NULL AND images NOT IN ('', '[]') LIMIT 1",
            (title,),
        ).fetchone()
    except Exception:
        return None
    if not row:
        return None
    try:
        imgs = json.loads(row["images"] or "[]")
    except (json.JSONDecodeError, TypeError):
        return None
    return imgs[0] if isinstance(imgs, list) and imgs and isinstance(imgs[0], str) else None


def _load_journeys() -> dict[str, JourneySummary]:
    """⚠️ 캐시하지 않는다. 사진이 나중에 캐시에 들어오면 바로 반영돼야 한다."""
    journeys: dict[str, JourneySummary] = {}
    if not JOURNEY_DIR.exists():
        return journeys
    for path in sorted(JOURNEY_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not data.get("cover_image"):
            # 제목 앞부분("성산일출봉 — …")으로 사진을 찾는다.
            base = data.get("title", "").split(" — ")[0].split(" - ")[0].strip()
            data["cover_image"] = _cached_photo(base)
        summary = JourneySummary(**data)
        journeys[summary.journey_id] = summary
    return journeys


@router.get("")
@limiter.limit("60/minute")
def list_journeys(request: Request) -> dict[str, list[JourneySummary]]:
    return {"journeys": list(_load_journeys().values())}


@router.get("/{journey_id}", response_model=JourneySummary)
@limiter.limit("60/minute")
def get_journey(request: Request, journey_id: str) -> JourneySummary:
    journey = _load_journeys().get(journey_id)
    if journey is None:
        raise HTTPException(status_code=404, detail="여정을 찾을 수 없습니다.")
    return journey
