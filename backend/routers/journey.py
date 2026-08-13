"""여정(장소 1개 = 유료 상품) 조회.

v1의 여정은 성산 1개다(설계 §9 "양산 지양"). 파일에서 읽는 이유는 콘텐츠가
원고에서 오기 때문이며, 이야기 본문·오디오는 묶음 B에서 이 위에 얹는다.

⚠️ 좌표를 **받지** 않는다. 위치 판정은 단말에서만 한다 (위치정보법, 설계 §6).
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from models.schemas import JourneySummary

BASE_DIR = Path(__file__).parent.parent.parent
JOURNEY_DIR = BASE_DIR / "data" / "journeys"

router = APIRouter(prefix="/journeys", tags=["journeys"])
limiter = Limiter(key_func=get_remote_address)


@lru_cache(maxsize=1)
def _load_journeys() -> dict[str, JourneySummary]:
    journeys: dict[str, JourneySummary] = {}
    if not JOURNEY_DIR.exists():
        return journeys
    for path in sorted(JOURNEY_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
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
