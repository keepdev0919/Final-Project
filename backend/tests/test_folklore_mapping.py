"""
설화 매핑 핵심 함수 테스트

커버:
- _haversine_m: 알려진 두 지점 거리 검증
- _filter_places_by_region: GPS 경계값 로직
- map_folklore_to_places: 반경 내/외 설화 매핑
"""
import pytest
from agents.course_detail_agent import _haversine_m, map_folklore_to_places
from agents.course_list_agent import _filter_places_by_region


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


# ─── _filter_places_by_region ─────────────────────────────────────────────────

def _make_place(lat: float, lng: float) -> dict:
    return {"place_name": "테스트장소", "lat": lat, "lng": lng, "day": 1}


class TestRegionFilter:
    def test_north_all_in_region(self):
        """북부(lat >= 33.45): 장소 모두 통과 → 코스 포함."""
        places = [_make_place(33.50, 126.52), _make_place(33.48, 126.51)]
        result = _filter_places_by_region(places, "북부")
        assert len(result) == 2

    def test_north_none_in_region(self):
        """북부: 장소 모두 남쪽(lat < 33.45) → 코스 제외."""
        places = [_make_place(33.30, 126.52), _make_place(33.28, 126.51)]
        result = _filter_places_by_region(places, "북부")
        assert result == []

    def test_north_half_passes_50_percent_threshold(self):
        """북부: 장소 2/4 (정확히 50%) 충족 → 코스 포함 (>= 50% 기준)."""
        places = [
            _make_place(33.50, 126.52),  # in 북부
            _make_place(33.50, 126.52),  # in 북부
            _make_place(33.30, 126.52),  # out
            _make_place(33.28, 126.51),  # out
        ]
        result = _filter_places_by_region(places, "북부")
        assert len(result) == 2  # 50% → 통과, in-region 장소만 반환

    def test_north_below_50_percent_excluded(self):
        """북부: 장소 1/4 (25%) → 코스 제외."""
        places = [
            _make_place(33.50, 126.52),  # in 북부
            _make_place(33.30, 126.52),  # out
            _make_place(33.28, 126.51),  # out
            _make_place(33.29, 126.53),  # out
        ]
        result = _filter_places_by_region(places, "북부")
        assert result == []

    def test_south_filter(self):
        """남부(lat < 33.30): 경계값 아래만 통과."""
        places = [_make_place(33.25, 126.55), _make_place(33.30, 126.55)]
        # 33.30은 경계값 — 남부 조건 lat < 33.30 이므로 통과 안 됨
        result = _filter_places_by_region(places, "남부")
        # 1개만 in(33.25), 1개는 out(33.30) → 1/2 = 50% → 통과
        assert len(result) == 1

    def test_east_filter(self):
        """동부(lng >= 126.70): 경계값 이상만 통과."""
        places = [_make_place(33.40, 126.80), _make_place(33.40, 126.60)]
        result = _filter_places_by_region(places, "동부")
        assert len(result) == 1  # 126.80만 통과

    def test_west_filter(self):
        """서부(lng < 126.40): 경계값 미만만 통과."""
        places = [_make_place(33.40, 126.30), _make_place(33.40, 126.40)]
        result = _filter_places_by_region(places, "서부")
        assert len(result) == 1  # 126.30만 통과

    def test_all_region_no_filter(self):
        """전체: 필터 없음 → 빈 리스트 반환 (호출하지 않아야 하지만 방어)."""
        places = [_make_place(33.40, 126.52)]
        # 전체는 REGION_HAS_FILTER에 포함 안 되어 호출 자체가 안 됨
        # 함수가 호출된 경우에도 True를 반환하는지 확인
        result = _filter_places_by_region(places, "전체")
        # 전체는 in_region이 True → 100% 통과
        assert len(result) == 1


# ─── map_folklore_to_places ───────────────────────────────────────────────────

class TestMapFolkloreToPlaces:
    def test_nearby_folklore_attached(self, monkeypatch):
        """반경 3km 이내 설화는 folklore_pins에 포함된다."""
        fake_folklore = [
            {
                "code_no": "F001",
                "title": "설문대할망",
                "source_type": "legend",
                "summary": "제주 창조 신화",
                "lat": 33.4590,  # 성산일출봉 기준 ~60m
                "lng": 126.9430,
            }
        ]
        monkeypatch.setattr(
            "agents.course_detail_agent._folklore_gps_cache", fake_folklore
        )
        places = [{"place_name": "성산일출봉", "lat": 33.4584, "lng": 126.9426, "day": 1}]
        result = map_folklore_to_places(places, radius_m=3000)
        assert len(result[0]["folklore_pins"]) == 1
        assert result[0]["folklore_pins"][0]["code_no"] == "F001"

    def test_far_folklore_not_attached(self, monkeypatch):
        """반경 3km 밖 설화는 folklore_pins에 포함되지 않는다."""
        fake_folklore = [
            {
                "code_no": "F002",
                "title": "멀리 있는 설화",
                "source_type": "folktale",
                "summary": "",
                "lat": 33.5113,  # 제주공항 인근 (~48km 거리)
                "lng": 126.4930,
            }
        ]
        monkeypatch.setattr(
            "agents.course_detail_agent._folklore_gps_cache", fake_folklore
        )
        places = [{"place_name": "성산일출봉", "lat": 33.4584, "lng": 126.9426, "day": 1}]
        result = map_folklore_to_places(places, radius_m=3000)
        assert result[0]["folklore_pins"] == []

    def test_null_gps_folklore_skipped(self, monkeypatch):
        """GPS 없는 설화(lat/lng = None)는 건너뛴다."""
        fake_folklore = [
            {"code_no": "F003", "title": "GPS없는설화", "source_type": "legend",
             "summary": "", "lat": None, "lng": None}
        ]
        monkeypatch.setattr(
            "agents.course_detail_agent._folklore_gps_cache", fake_folklore
        )
        places = [{"place_name": "어딘가", "lat": 33.40, "lng": 126.53, "day": 1}]
        result = map_folklore_to_places(places, radius_m=3000)
        assert result[0]["folklore_pins"] == []

    def test_max_3_pins_per_place(self, monkeypatch):
        """장소당 최대 3개 설화만 포함된다."""
        base_lat, base_lng = 33.4584, 126.9426
        fake_folklore = [
            {"code_no": f"F{i:03d}", "title": f"설화{i}", "source_type": "legend",
             "summary": "", "lat": base_lat + i * 0.001, "lng": base_lng}
            for i in range(5)
        ]
        monkeypatch.setattr(
            "agents.course_detail_agent._folklore_gps_cache", fake_folklore
        )
        places = [{"place_name": "성산일출봉", "lat": base_lat, "lng": base_lng, "day": 1}]
        result = map_folklore_to_places(places, radius_m=5000)
        assert len(result[0]["folklore_pins"]) == 3  # 최대 3개 제한
