"""
설화 매핑 핵심 함수 테스트

커버:
- _haversine_m: 알려진 두 지점 거리 검증
- _scores_to_theme_text: 카테고리 점수 → 주제 텍스트 변환
- map_folklore_to_places: DB 기반 설화 매핑
"""
from unittest.mock import MagicMock, patch

import pytest

from agents.course_list_agent import _haversine_m, _scores_to_theme_text


# ─── _haversine_m ─────────────────────────────────────────────────────────────

class TestHaversine:
    def test_same_point_is_zero(self):
        """같은 좌표의 거리는 0."""
        dist = _haversine_m(33.4584, 126.9426, 33.4584, 126.9426)
        assert dist == 0.0

    def test_jeju_airport_to_seongsan(self):
        """제주공항(33.5113, 126.4930) → 성산일출봉(33.4584, 126.9426) 직선거리 약 42km."""
        dist = _haversine_m(33.5113, 126.4930, 33.4584, 126.9426)
        assert 40_000 < dist < 45_000, f"예상 ~42km, 실제 {dist:.0f}m"

    def test_short_distance_hyupjae_to_hallim(self):
        """협재해수욕장(33.3941, 126.2393) → 한림공원(33.4069, 126.2448) 직선거리 약 1.5km."""
        dist = _haversine_m(33.3941, 126.2393, 33.4069, 126.2448)
        assert 1_000 < dist < 2_500, f"예상 ~1.5km, 실제 {dist:.0f}m"

    def test_symmetry(self):
        """거리 계산은 방향에 무관해야 한다."""
        d1 = _haversine_m(33.4584, 126.9426, 33.3941, 126.2393)
        d2 = _haversine_m(33.3941, 126.2393, 33.4584, 126.9426)
        assert abs(d1 - d2) < 1, "대칭성 위반"


# ─── _scores_to_theme_text ────────────────────────────────────────────────────

class TestScoresToThemeText:
    def test_empty_scores_returns_default(self):
        """점수 없으면 기본 문구 반환."""
        result = _scores_to_theme_text({})
        assert result == "특별한 취향 없음 (다양한 설화 포함)"

    def test_all_zero_returns_default(self):
        """모두 0점이면 기본 문구 반환."""
        result = _scores_to_theme_text({"무속신화·신격 전승": 0, "생활민담·교훈담": 0})
        assert result == "특별한 취향 없음 (다양한 설화 포함)"

    def test_positive_scores_include_category(self):
        """양수 점수 카테고리는 결과에 포함된다."""
        result = _scores_to_theme_text({"해양·어촌 전승": 3})
        assert "해양·어촌 전승" in result
        assert "3점" in result

    def test_higher_score_appears_first(self):
        """점수 높은 카테고리가 먼저 나온다."""
        result = _scores_to_theme_text({"생활민담·교훈담": 1, "무속신화·신격 전승": 5})
        lines = result.splitlines()
        assert "무속신화·신격 전승" in lines[0]

    def test_zero_score_category_excluded(self):
        """0점 카테고리는 결과에서 제외된다."""
        result = _scores_to_theme_text({"해양·어촌 전승": 2, "초자연 존재담": 0})
        assert "초자연 존재담" not in result


# ─── map_folklore_to_places ───────────────────────────────────────────────────

def _make_db_row(code_no: str, title: str, category: str = "생활민담·교훈담",
                 matched_place: str = "성산읍", specificity: int = 5) -> MagicMock:
    """sqlite3.Row 대신 MagicMock으로 DB 행 흉내."""
    row = MagicMock()
    row.__getitem__ = lambda self, key: {
        "folklore_code_no": code_no,
        "folklore_title": title,
        "folklore_summary": "테스트 요약",
        "final_category": category,
        "matched_place": matched_place,
        "specificity": specificity,
        "place_lat": 33.4584,
        "place_lng": 126.9426,
    }[key]
    return row


class TestMapFolkloreToPlaces:
    def test_db_results_attached_as_pins(self):
        """DB 조회 결과가 folklore_pins에 포함된다."""
        from agents.course_detail_agent import map_folklore_to_places

        mock_conn = MagicMock()
        mock_conn.execute.return_value.fetchall.return_value = [
            _make_db_row("F001", "설문대할망")
        ]

        with patch("agents.course_detail_agent.get_db_connection", return_value=mock_conn):
            places = [{"place_name": "성산일출봉", "lat": 33.4584, "lng": 126.9426, "day": 1}]
            result = map_folklore_to_places(places)

        assert len(result[0]["folklore_pins"]) == 1
        assert result[0]["folklore_pins"][0]["code_no"] == "F001"

    def test_no_db_results_gives_empty_pins(self):
        """DB에 결과 없으면 folklore_pins는 빈 리스트."""
        from agents.course_detail_agent import map_folklore_to_places

        mock_conn = MagicMock()
        mock_conn.execute.return_value.fetchall.return_value = []

        with patch("agents.course_detail_agent.get_db_connection", return_value=mock_conn):
            places = [{"place_name": "없는장소", "lat": 33.40, "lng": 126.53, "day": 1}]
            result = map_folklore_to_places(places)

        assert result[0]["folklore_pins"] == []

    def test_max_3_pins_per_place(self):
        """장소당 최대 3개 설화만 포함된다 (DB LIMIT 20 → 상위 3개 선택)."""
        from agents.course_detail_agent import map_folklore_to_places

        mock_conn = MagicMock()
        mock_conn.execute.return_value.fetchall.return_value = [
            _make_db_row(f"F{i:03d}", f"설화{i}") for i in range(5)
        ]

        with patch("agents.course_detail_agent.get_db_connection", return_value=mock_conn):
            places = [{"place_name": "성산일출봉", "lat": 33.4584, "lng": 126.9426, "day": 1}]
            result = map_folklore_to_places(places)

        assert len(result[0]["folklore_pins"]) == 3

    def test_category_scores_reorder_pins(self):
        """category_scores가 높은 카테고리의 설화가 앞에 온다."""
        from agents.course_detail_agent import map_folklore_to_places

        mock_conn = MagicMock()
        mock_conn.execute.return_value.fetchall.return_value = [
            _make_db_row("F001", "낮은카테고리", category="생활민담·교훈담", specificity=5),
            _make_db_row("F002", "높은카테고리", category="해양·어촌 전승", specificity=5),
        ]

        with patch("agents.course_detail_agent.get_db_connection", return_value=mock_conn):
            places = [{"place_name": "성산일출봉", "lat": 33.4584, "lng": 126.9426, "day": 1}]
            category_scores = {"해양·어촌 전승": 10, "생활민담·교훈담": 2}
            result = map_folklore_to_places(places, category_scores=category_scores)

        pins = result[0]["folklore_pins"]
        assert pins[0]["code_no"] == "F002", "취향 점수 높은 설화가 첫 번째여야 함"

    def test_place_fields_preserved(self):
        """원본 place 필드(place_name, lat, lng, day)가 결과에 보존된다."""
        from agents.course_detail_agent import map_folklore_to_places

        mock_conn = MagicMock()
        mock_conn.execute.return_value.fetchall.return_value = []

        with patch("agents.course_detail_agent.get_db_connection", return_value=mock_conn):
            places = [{"place_name": "협재해수욕장", "lat": 33.3941, "lng": 126.2393, "day": 2}]
            result = map_folklore_to_places(places)

        assert result[0]["place_name"] == "협재해수욕장"
        assert result[0]["day"] == 2
        assert result[0]["lat"] == 33.3941
