"""장소 리뷰 엔드포인트."""
import json
from fastapi import APIRouter, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from models.schemas import PlaceReviewRequest, PlaceReviewsResponse, VALID_REVIEW_TAGS
from services.db import get_db_connection

router = APIRouter(prefix="/place", tags=["review"])
limiter = Limiter(key_func=get_remote_address)


@router.post("/review", status_code=201)
@limiter.limit("30/minute")
def submit_review(request: Request, body: PlaceReviewRequest):
    if not body.tags:
        raise HTTPException(status_code=400, detail="태그를 1개 이상 선택해주세요.")
    invalid = set(body.tags) - VALID_REVIEW_TAGS
    if invalid:
        raise HTTPException(status_code=400, detail=f"유효하지 않은 태그: {invalid}")
    if body.note and len(body.note) > 200:
        raise HTTPException(status_code=400, detail="노트는 200자 이내로 작성해주세요.")

    conn = get_db_connection()
    conn.execute(
        """
        INSERT OR REPLACE INTO place_reviews (place_name, tags, note, device_id)
        VALUES (?, ?, ?, ?)
        """,
        (
            body.place_name,
            json.dumps(body.tags, ensure_ascii=False),
            body.note,
            body.device_id,
        ),
    )
    conn.commit()
    return {"ok": True}


@router.get("/reviews/{place_name}", response_model=PlaceReviewsResponse)
def get_reviews(place_name: str):
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT tags, note FROM place_reviews WHERE place_name = ? ORDER BY created_at DESC",
        (place_name,),
    ).fetchall()

    total = len(rows)
    tag_counts = {tag: 0 for tag in VALID_REVIEW_TAGS}
    recent_notes: list[str] = []

    for row in rows:
        for tag in json.loads(row["tags"]):
            if tag in tag_counts:
                tag_counts[tag] += 1
        if row["note"] and len(recent_notes) < 3:
            recent_notes.append(row["note"])

    return PlaceReviewsResponse(
        total=total,
        tag_counts=tag_counts,
        recent_notes=recent_notes,
    )
