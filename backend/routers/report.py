"""미션 신고 — 「현장에서 찾을 수 없어요」.

## 왜 있나

제주 5곳을 직접 답사하지 않기로 했다(2026-09-02). 웹 자료로 검증했지만
**일반 관람객 시야에서 실제로 보이는지까지는 확정하지 못한 미션이 있다**
(성읍 M04 마당 배치 · M07 물팡).

그래서 "출시 후 사용자 리뷰로 잡는다"고 정했는데, **이 경로가 없으면 그건
리뷰 보정이 아니라 그냥 「검증 안 함」이다.** 이 엔드포인트가 그 전략을 성립시킨다.

## ⚠️ 사용자를 식별하는 값을 받지 않는다

기기 ID·위치·사진 없음. 신고 화면이 사용자에게
*"위치나 사진은 함께 보내지 않습니다"* 라고 약속하고 있다.
여기에 무엇을 더하려면 **그 문구부터 고쳐야 한다.**

식별자가 없으니 중복 신고를 못 거른다. 지금 규모에서는 문제가 아니고,
연타는 rate limit 이 막는다.
"""
from __future__ import annotations

import logging
import time
import uuid

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from slowapi import Limiter
from slowapi.util import get_remote_address

from services.db import get_db_connection

router = APIRouter(prefix="/report", tags=["report"])
limiter = Limiter(key_func=get_remote_address)
logger = logging.getLogger(__name__)

# 신고 사유. 화면의 보기와 같아야 한다
# (`ios/…/MissionReportSheet.swift` 의 `MissionReport.Reason`).
ALLOWED_REASONS = frozenset({
    "notVisible",   # 대상이 보이지 않아요
    "blocked",      # 공사·통제 중이에요
    "mismatch",     # 설명과 실제 장소가 달라요
    "other",        # 기타
})

# 자유 입력 길이. 넘치면 자르지 않고 막는다 — 반쪽만 저장하면 무슨 말인지 모른다.
MAX_NOTE = 500


class MissionReportRequest(BaseModel):
    play_id: str
    mission_id: str = ""
    reason: str
    note: str = Field(default="", max_length=MAX_NOTE)


@router.post("/mission", status_code=201)
@limiter.limit("20/minute")
def report_mission(request: Request, body: MissionReportRequest) -> dict:
    if body.reason not in ALLOWED_REASONS:
        raise HTTPException(status_code=400, detail=f"모르는 사유: {body.reason}")

    report_id = str(uuid.uuid7())
    conn = get_db_connection()
    conn.execute(
        "INSERT INTO mission_reports "
        "(id, play_id, mission_id, reason, note, reported_at) VALUES (?,?,?,?,?,?)",
        (report_id, body.play_id, body.mission_id or None,
         body.reason, body.note or None, time.time()),
    )
    conn.commit()

    # 콘텐츠를 고칠 때 보려고 로그에도 남긴다. 신고가 쌓이는 미션이
    # 곧 다시 조사해야 할 미션이다.
    logger.info("[REPORT] %s / %s — %s | %s",
                body.play_id, body.mission_id or "-", body.reason, body.note or "")
    return {"id": report_id}


@router.get("/mission")
@limiter.limit("30/minute")
def list_reports(request: Request, play_id: str = "", limit: int = 100) -> dict:
    """쌓인 신고를 본다. **콘텐츠 QA 용이다** — 어느 미션이 현장에서 안 되는지 읽는다.

    운영 화면이 따로 없으니 당분간 이걸로 확인한다.
    """
    conn = get_db_connection()
    if play_id:
        rows = conn.execute(
            "SELECT * FROM mission_reports WHERE play_id = ? "
            "ORDER BY reported_at DESC LIMIT ?", (play_id, min(limit, 500)),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM mission_reports ORDER BY reported_at DESC LIMIT ?",
            (min(limit, 500),),
        ).fetchall()
    return {"reports": [dict(r) for r in rows], "total": len(rows)}
