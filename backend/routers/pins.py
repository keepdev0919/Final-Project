"""GPS 반경 내 설화·민담 핀 조회 + LLM 가공 콘텐츠 엔드포인트.

엔드포인트:
    GET /pins/all                       — 전체 핀 (hook 포함)
    GET /pins/{code_no}                 — 설화 원문
    GET /pins                           — GPS 반경 내 핀
    GET /pins/{code_no}/connection      — 장소×설화 한 줄 연결 (LLM, 캐시)
    GET /pins/{code_no}/story           — 장소×설화 스토리북 페이지 (LLM, 캐시)
"""
from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from pathlib import Path
import json
import math
import re
import time

from models.schemas import (
    Pin,
    PinConnectionResponse,
    PinDetail,
    PinStoryResponse,
    StoryPage,
)
from services.db import get_db_connection
from services import folklore_llm

BASE_DIR = Path(__file__).parent.parent.parent
EXTRACTED_DIR = BASE_DIR / "data" / "extracted"

router = APIRouter(prefix="/pins", tags=["pins"])
limiter = Limiter(key_func=get_remote_address)

SUMMARY_MAX_LEN = 80


def _haversine_m(lat1, lng1, lat2, lng2) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ── 원문 추출 유틸 ────────────────────────────────────────────────────────────


def _extract_full_text(path: Path) -> str:
    text = path.read_text(encoding="utf-8")

    # C_ 구조: 내용 섹션 추출
    match = re.search(r'\d+\s+내용\s*\n+(.*?)(?:\n\d+\s+\S|\Z)', text, re.DOTALL)
    if match:
        content = re.sub(r'\s+', ' ', match.group(1)).strip()
        return content

    # T_/W_ 구조: 구분선 이후 현대어 번역
    match2 = re.search(r'-{10,}\s*\n+(.*)', text, re.DOTALL)
    if match2:
        content = match2.group(1).strip()
        # 조사 메타 헤더 제거 (날짜, 조사자 등)
        content = re.sub(r'^\d{4}년.*?\n', '', content)
        return re.sub(r'\s+', ' ', content).strip()

    # 폴백: 전체 텍스트에서 제목 줄 제거
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    return ' '.join(lines[1:])[:2000]


def _load_folklore(code_no: str) -> dict | None:
    """LLM 입력용 설화 dict (title/primary_place/summary/full_text/source_type)."""
    conn = get_db_connection()
    row = conn.execute(
        "SELECT code_no, title, source_type, primary_place, summary "
        "FROM metadata WHERE code_no=?",
        (code_no,),
    ).fetchone()
    if not row:
        return None
    folder = "legend" if row["source_type"] == "legend" else "folktale"
    path = EXTRACTED_DIR / folder / f"{code_no}.txt"
    full_text = _extract_full_text(path) if path.exists() else (row["summary"] or "")
    return {
        "code_no": row["code_no"],
        "title": row["title"],
        "source_type": row["source_type"],
        "primary_place": row["primary_place"] or "",
        "summary": row["summary"] or "",
        "full_text": full_text,
    }


# ── /pins/all : hook 포함 ─────────────────────────────────────────────────────


@router.get("/all", response_model=list[Pin])
@limiter.limit("10/minute")
def get_all_pins(request: Request):
    """GPS 있는 설화·민담 핀 전체 반환 (앱 시작 시 1회 호출용).

    각 핀에 캐시된 hook(30~50자)을 포함한다. 캐시 miss여도 응답을 막지 않고
    None으로 반환한다 (백그라운드 배치/lazy 생성 전략).
    """
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT code_no, title, source_type, primary_place, lat, lng, summary, hook "
        "FROM metadata WHERE lat IS NOT NULL AND lng IS NOT NULL"
    ).fetchall()
    return [
        Pin(
            code_no=row["code_no"],
            title=row["title"],
            source_type=row["source_type"],
            summary=row["summary"] or row["title"],
            lat=row["lat"],
            lng=row["lng"],
            primary_place=row["primary_place"] or "",
            distance_m=0.0,
            hook=row["hook"] if "hook" in row.keys() else None,
        )
        for row in rows
    ]


# ── /pins/{code_no} : 원문 ────────────────────────────────────────────────────


@router.get("/{code_no}", response_model=PinDetail)
@limiter.limit("60/minute")
def get_pin_detail(request: Request, code_no: str):
    """설화·민담 원문 텍스트 반환."""
    conn = get_db_connection()
    row = conn.execute(
        "SELECT code_no, title, source_type, summary, primary_place, lat, lng FROM metadata WHERE code_no=?",
        (code_no,),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="설화를 찾을 수 없습니다.")

    folder = "legend" if row["source_type"] == "legend" else "folktale"
    path = EXTRACTED_DIR / folder / f"{code_no}.txt"
    full_text = _extract_full_text(path) if path.exists() else row["summary"] or row["title"]

    return PinDetail(
        code_no=row["code_no"],
        title=row["title"],
        source_type=row["source_type"],
        summary=row["summary"] or row["title"],
        full_text=full_text,
        primary_place=row["primary_place"] or "",
        lat=row["lat"] or 0.0,
        lng=row["lng"] or 0.0,
    )


# ── /pins?lat&lng : 반경 검색 ─────────────────────────────────────────────────


@router.get("", response_model=list[Pin])
@limiter.limit("60/minute")
def get_pins(request: Request, lat: float, lng: float, radius_m: float = 500):
    """GPS 좌표 반경 내 설화·민담 핀 반환."""
    conn = get_db_connection()

    # 위도 1도 ≈ 111km, 경도 1도 ≈ 88km (제주 위도 기준)
    lat_delta = radius_m / 111_000
    lng_delta = radius_m / 88_000

    rows = conn.execute(
        """
        SELECT code_no, title, source_type, primary_place, lat, lng, summary, hook
        FROM metadata
        WHERE lat IS NOT NULL
          AND lat BETWEEN ? AND ?
          AND lng BETWEEN ? AND ?
        """,
        (lat - lat_delta, lat + lat_delta, lng - lng_delta, lng + lng_delta),
    ).fetchall()

    pins = []
    for row in rows:
        dist = _haversine_m(lat, lng, row["lat"], row["lng"])
        if dist <= radius_m:
            pins.append(Pin(
                code_no=row["code_no"],
                title=row["title"],
                source_type=row["source_type"],
                summary=row["summary"] or row["title"],
                lat=row["lat"],
                lng=row["lng"],
                primary_place=row["primary_place"] or "",
                distance_m=round(dist, 1),
                hook=row["hook"] if "hook" in row.keys() else None,
            ))

    pins.sort(key=lambda p: p.distance_m)
    return pins


# ── /pins/{code_no}/connection : 장소×설화 한 줄 ──────────────────────────────


@router.get("/{code_no}/connection", response_model=PinConnectionResponse)
@limiter.limit("10/minute")
def get_pin_connection(
    request: Request,
    code_no: str,
    place: str = Query(..., min_length=1, max_length=120, description="여행자가 방문할 장소명"),
):
    """장소×설화 한 줄 연결을 반환한다. 캐시 우선, miss면 LLM 생성 후 영구 저장."""
    place_norm = place.strip()
    if not place_norm:
        raise HTTPException(status_code=400, detail="place 파라미터가 비어 있습니다.")

    conn = get_db_connection()
    cached = conn.execute(
        "SELECT connection FROM folklore_connection_cache WHERE code_no=? AND place=?",
        (code_no, place_norm),
    ).fetchone()
    if cached and cached["connection"]:
        return PinConnectionResponse(
            code_no=code_no, place=place_norm, connection=cached["connection"]
        )

    folklore = _load_folklore(code_no)
    if not folklore:
        raise HTTPException(status_code=404, detail="설화를 찾을 수 없습니다.")

    connection = folklore_llm.generate_connection(folklore, place_norm)
    if not connection:
        raise HTTPException(status_code=503, detail="연결 문구 생성에 실패했습니다.")

    conn.execute(
        "INSERT OR REPLACE INTO folklore_connection_cache(code_no, place, connection, cached_at)"
        " VALUES (?, ?, ?, ?)",
        (code_no, place_norm, connection, time.time()),
    )
    conn.commit()
    return PinConnectionResponse(
        code_no=code_no, place=place_norm, connection=connection
    )


# ── /pins/{code_no}/story : 페이지 단위 스토리북 ──────────────────────────────


@router.get("/{code_no}/story", response_model=PinStoryResponse)
@limiter.limit("10/minute")
def get_pin_story(
    request: Request,
    code_no: str,
    place: str = Query(..., min_length=1, max_length=120, description="여행자가 방문할 장소명"),
):
    """장소×설화 스토리북(5~7페이지)을 반환한다. 캐시 우선, miss면 LLM 생성."""
    place_norm = place.strip()
    if not place_norm:
        raise HTTPException(status_code=400, detail="place 파라미터가 비어 있습니다.")

    conn = get_db_connection()
    cached = conn.execute(
        "SELECT pages_json FROM folklore_story_cache WHERE code_no=? AND place=?",
        (code_no, place_norm),
    ).fetchone()
    if cached and cached["pages_json"]:
        try:
            pages = json.loads(cached["pages_json"])
            return PinStoryResponse(
                code_no=code_no,
                place=place_norm,
                pages=[StoryPage(**p) for p in pages],
            )
        except (json.JSONDecodeError, TypeError, ValueError):
            # 캐시가 깨졌으면 재생성하도록 fallthrough
            pass

    folklore = _load_folklore(code_no)
    if not folklore:
        raise HTTPException(status_code=404, detail="설화를 찾을 수 없습니다.")

    pages = folklore_llm.generate_story_pages(folklore, place_norm)
    if not pages:
        raise HTTPException(status_code=503, detail="스토리 생성에 실패했습니다.")

    conn.execute(
        "INSERT OR REPLACE INTO folklore_story_cache(code_no, place, pages_json, cached_at)"
        " VALUES (?, ?, ?, ?)",
        (code_no, place_norm, json.dumps(pages, ensure_ascii=False), time.time()),
    )
    conn.commit()

    # ── hook 캐시 miss라면 함께 채워둔다 (저비용 부수 작업) ───────────────
    try:
        row = conn.execute(
            "SELECT hook FROM metadata WHERE code_no=?", (code_no,)
        ).fetchone()
        if row and not row["hook"]:
            hook = folklore_llm.generate_hook(folklore)
            if hook:
                conn.execute(
                    "UPDATE metadata SET hook=? WHERE code_no=?", (hook, code_no)
                )
                conn.commit()
    except Exception as exc:  # noqa: BLE001
        print(f"[pins] hook lazy backfill 실패 ({code_no}): {exc}")

    return PinStoryResponse(
        code_no=code_no,
        place=place_norm,
        pages=[StoryPage(**p) for p in pages],
    )


# ── 운영용: hook 일괄 백필 ────────────────────────────────────────────────────


def _backfill_hooks(limit: int) -> None:
    """metadata.hook IS NULL 인 핀에 대해 hook을 생성/저장."""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT code_no FROM metadata "
        "WHERE lat IS NOT NULL AND lng IS NOT NULL AND (hook IS NULL OR hook = '') "
        "LIMIT ?",
        (limit,),
    ).fetchall()
    print(f"[pins] hook backfill 시작 — 대상 {len(rows)}건")
    ok = fail = 0
    for r in rows:
        code_no = r["code_no"]
        folklore = _load_folklore(code_no)
        if not folklore:
            fail += 1
            continue
        hook = folklore_llm.generate_hook(folklore)
        if not hook:
            fail += 1
            continue
        try:
            conn.execute("UPDATE metadata SET hook=? WHERE code_no=?", (hook, code_no))
            conn.commit()
            ok += 1
        except Exception as exc:  # noqa: BLE001
            print(f"[pins] hook UPDATE 실패 {code_no}: {exc}")
            fail += 1
    print(f"[pins] hook backfill 완료 — 성공 {ok} / 실패 {fail}")


@router.post("/hooks/backfill")
@limiter.limit("2/minute")
def trigger_hook_backfill(
    request: Request,
    background_tasks: BackgroundTasks,
    limit: int = Query(50, ge=1, le=500, description="이번 배치 처리 건수"),
):
    """hook 미생성 핀에 대해 백그라운드로 LLM 호출하여 캐시에 채워넣는다.

    운영용 엔드포인트. 첫 배포 후 1회만 호출하면 이후 /pins/all 응답이
    모두 hook을 포함하게 된다.
    """
    background_tasks.add_task(_backfill_hooks, limit)
    return {"status": "scheduled", "limit": limit}
