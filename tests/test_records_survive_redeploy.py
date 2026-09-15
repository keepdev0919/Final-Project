"""미션 신고 · KTO 호출 기록은 재배포에서 살아남아야 한다 (2026-09-15).

metadata.db 는 배포 이미지에 실려 가서 재배포하면 맥에 있던 사본으로 되돌아간다.
서버가 운영 중에 적은 신고와 호출 기록이 거기 있으면 배포할 때마다 조용히 사라진다 —
화면은 멀쩡하니 아무도 모른다. 그래서 둘은 Railway 볼륨의 records.db 에 적는다.
"""
import sqlite3

import pytest

from services import db, typecast


def test_records_live_in_the_volume_folder():
    """Railway 볼륨이 붙은 폴더는 음성 캐시 폴더 하나뿐이다(/app/storage/tts_cache).

    records.db 가 그 밖으로 나가면 다시 배포 때마다 지워진다.
    """
    assert db.RECORDS_PATH.parent == typecast.CACHE_DIR
    assert db.RECORDS_PATH != db.DB_PATH


@pytest.fixture
def fresh_conn(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "DB_PATH", tmp_path / "metadata.db")
    monkeypatch.setattr(db, "RECORDS_PATH", tmp_path / "volume" / "records.db")
    conn = db._connect()
    yield conn
    conn.close()


def _tables(path) -> set[str]:
    with sqlite3.connect(path) as c:
        return {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}


def test_reports_and_kto_log_are_created_in_records_not_metadata(fresh_conn, tmp_path):
    for t in ("kto_call_log", "mission_reports"):
        assert t in _tables(tmp_path / "volume" / "records.db")
        assert t not in _tables(tmp_path / "metadata.db")


def test_report_sent_from_app_lands_in_records(client, tmp_path, monkeypatch):
    """옛 metadata.db 에는 이름이 같은 mission_reports 표가 남아 있다. 쿼리에 `records.`
    를 빠뜨리면 SQLite 가 그 옛 표에 적는다 — 그 상태를 만들어 두고 앱처럼 신고를 보낸다."""
    main_db = tmp_path / "metadata.db"
    with sqlite3.connect(main_db) as c:
        c.execute("CREATE TABLE mission_reports (id TEXT PRIMARY KEY, play_id TEXT, "
                  "mission_id TEXT, reason TEXT, note TEXT, reported_at REAL)")
    monkeypatch.setattr(db, "DB_PATH", main_db)
    monkeypatch.setattr(db, "RECORDS_PATH", tmp_path / "volume" / "records.db")
    # 스레드마다 캐시된 연결을 비워 새 경로로 다시 열게 한다
    import threading
    monkeypatch.setattr(db, "_thread_local", threading.local())

    res = client.post("/report/mission", json={
        "play_id": "seongeup-restore", "mission_id": "m07", "reason": "notVisible"})
    assert res.status_code == 201

    with sqlite3.connect(tmp_path / "volume" / "records.db") as c:
        assert c.execute("SELECT count(*) FROM mission_reports").fetchone()[0] == 1
    with sqlite3.connect(main_db) as c:
        assert c.execute("SELECT count(*) FROM mission_reports").fetchone()[0] == 0

    listed = client.get("/report/mission").json()
    assert [r["id"] for r in listed["reports"]] == [res.json()["id"]]
