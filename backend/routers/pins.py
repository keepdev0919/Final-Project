"""GPS 반경 내 설화·민담 핀 조회."""
from fastapi import APIRouter, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
import math

from models.schemas import Pin
from services.db import get_db_connection

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
