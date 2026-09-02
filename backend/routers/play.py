"""PLAY · Place 엔드포인트.

## Place 와 PLAY 를 나눠서 답한다 (2026-09-02 결정)

    Place   "여기가 어떤 곳이고, 실제로 갈 수 있는가"   → KTO OpenAPI 관광정보
    PLAY    "여기서 내가 무슨 게임을 하게 되는가"        → 우리 콘텐츠

한 Place 에 PLAY 가 여러 개 생길 수 있다. 그래서 `Place 1 : N PLAY` 이고,
`GET /places/{place_id}/plays` 가 목록을 돌려준다.

## 진입 경로를 하나로 강제하지 않는다

전에는 홈·지도·코스가 전부 장소 상세로만 들어갔다. 이제 게임으로 들어오는
길과 장소 정보로 들어오는 길을 따로 둔다.

    코스   → Place  → (PLAY 가 있으면) PLAY
    홈     → PLAY
    지도   → PLAY (활성 핀) 또는 Place (준비 중 핀)
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from models.play import MapPin, Play, PlaySummary
from services import place_registry as registry
from services import play_loader
from services.db import get_db_connection

router = APIRouter(tags=["play"])
limiter = Limiter(key_func=get_remote_address)


def _conn():
    conn = get_db_connection()
    # Place 레지스트리가 비어 있으면 채운다. 몇 번 불러도 id 는 그대로다.
    registry.ensure_synced(conn)
    return conn


# ── PLAY ──────────────────────────────────────────────────────────────────────

@router.get("/plays")
@limiter.limit("60/minute")
def list_plays(request: Request) -> dict[str, list[PlaySummary]]:
    """플레이할 수 있는 PLAY 전부. 홈이 쓴다."""
    conn = _conn()
    return {"plays": [play_loader.summarize(conn, p) for p in play_loader.load_all(conn)]}


@router.get("/plays/{play_id}", response_model=Play)
@limiter.limit("60/minute")
def get_play(request: Request, play_id: str) -> Play:
    """PLAY 하나 전체 — Point · Mission · Step · Story 까지.

    ⚠️ 정답이 그대로 들어 있다. V1 에서는 이것을 감추지 않는다 —
    감추려면 매 Step 마다 서버 왕복이 필요한데, 현장은 통신이 불안하고
    이 게임은 경쟁이 아니라 자기 속도 관광이다. 답을 미리 보는 것은
    `[정답과 이야기 보기]` 로 이미 열려 있다.
    """
    play = play_loader.get(_conn(), play_id)
    if play is None:
        raise HTTPException(status_code=404, detail="그런 PLAY 가 없습니다")
    return play


# ── Place ─────────────────────────────────────────────────────────────────────

@router.get("/places/{place_id}")
@limiter.limit("60/minute")
def get_place(request: Request, place_id: str) -> dict:
    """Place 하나. 붙어 있는 외부 식별자를 함께 돌려준다.

    관광정보 본문(운영시간·사진·개요)은 `GET /place/detail` 이 KTO OpenAPI 로
    그 자리에서 불러온다. 여기서는 **정체성과 연결 정보**만 답한다.
    """
    place = registry.get(_conn(), place_id)
    if place is None:
        raise HTTPException(status_code=404, detail="그런 장소가 없습니다")
    return place


@router.get("/places/{place_id}/plays")
@limiter.limit("60/minute")
def plays_for_place(request: Request, place_id: str) -> dict[str, list[PlaySummary]]:
    """이 장소에서 할 수 있는 PLAY. **장소 상세의 「PLAY」 섹션이 쓴다.**

    비어 있는 것이 정상이다 — 121곳 중 PLAY 가 있는 곳은 아직 한 곳뿐이다.
    """
    conn = _conn()
    if registry.get(conn, place_id) is None:
        raise HTTPException(status_code=404, detail="그런 장소가 없습니다")
    return {"plays": [play_loader.summarize(conn, p)
                      for p in play_loader.for_place(conn, place_id)]}


# ── 지도 ──────────────────────────────────────────────────────────────────────

@router.get("/map/pins")
@limiter.limit("60/minute")
def map_pins(request: Request) -> dict:
    """PLAY 지도.

    오디 해설 121곳을 뿌리던 화면을 대체한다. 이제 지도가 답하는 질문은
    **"제주 어디서 놀멍봅서를 할 수 있고, 앞으로 어디에 생기나"** 다.

    개수를 서버가 세어서 같이 준다. 화면에 숫자를 박아두면 콘텐츠가 늘어날 때
    조용히 거짓이 된다.
    """
    pins = play_loader.map_pins(_conn())
    return {
        "pins": pins,
        "active_count": sum(1 for p in pins if p.status == "active"),
        "preparing_count": sum(1 for p in pins if p.status == "preparing"),
    }
