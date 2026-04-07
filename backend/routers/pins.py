"""GPS 반경 내 설화·민담 핀 조회."""
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from pathlib import Path
import math, re

from models.schemas import Pin, PinDetail
from services.db import get_db_connection

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


@router.get("/all", response_model=list[Pin])
@limiter.limit("10/minute")
def get_all_pins(request: Request):
    """GPS 있는 설화·민담 핀 전체 반환 (앱 시작 시 1회 호출용)."""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT code_no, title, source_type, primary_place, lat, lng, summary FROM metadata WHERE lat IS NOT NULL AND lng IS NOT NULL"
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
        )
        for row in rows
    ]


@router.get("/{code_no}", response_model=PinDetail)
@limiter.limit("60/minute")
def get_pin_detail(request: Request, code_no: str):
    """설화·민담 원문 텍스트 반환."""
    conn = get_db_connection()
    row = conn.execute(
        "SELECT code_no, title, source_type, summary, primary_place, lat, lng FROM metadata WHERE code_no=?",
        (code_no,)
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
        SELECT code_no, title, source_type, primary_place, lat, lng, summary
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
            ))

    pins.sort(key=lambda p: p.distance_m)
    return pins
