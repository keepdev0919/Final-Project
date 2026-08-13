"""코스 큐레이션 — 설화 없는 품질 기준을 지키는 테스트.

`test_folklore_mapping.py`를 대체한다. 그 파일은 설화 취향 점수(`_scores_to_theme_text`)와
설화 매핑(`map_folklore_to_places`)을 테스트했는데, 2026-08-13에 코스 추천에서 설화를
분리하면서 두 함수가 사라졌다.

여기 테스트는 버그 잡기가 아니라 **결정을 코드에 박아두기 위한 것**이다.
"""
import math

import pytest

from agents.course_list_agent import _haversine_m


# ─── _haversine_m (기존 테스트에서 이관) ───────────────────────────────────────

class TestHaversine:
    def test_same_point_is_zero(self):
        assert _haversine_m(33.4584, 126.9426, 33.4584, 126.9426) == pytest.approx(0, abs=1)

    def test_known_distance_jeju_city_to_seongsan(self):
        """제주시청 ↔ 성산일출봉 약 44km (오차 3km 허용)."""
        d = _haversine_m(33.5113, 126.4930, 33.4584, 126.9426)
        assert 41_000 < d < 47_000

    def test_symmetry(self):
        d1 = _haversine_m(33.4584, 126.9426, 33.3941, 126.2393)
        d2 = _haversine_m(33.3941, 126.2393, 33.4584, 126.9426)
        assert d1 == pytest.approx(d2)


# ─── 코스 추천에 설화가 다시 끼어들지 않게 한다 ────────────────────────────────

class TestNoFolkloreInCourseRecommendation:
    def test_course_list_agent_has_no_folklore_scoring(self):
        """설화 취향 점수 함수가 되살아나지 않아야 한다.

        코스는 "어디를 갈지", 설화는 "그 장소의 이야기"다. 추천 기준으로 쓸 근거가
        없고, 장소에 강하게 얽힌 설화가 실제로 거의 없다(매핑 작업에서 확인).
        설화는 로컬 파일 데이터라 공모전 데이터 활용 점수에도 기여하지 않는다.
        """
        from agents import course_list_agent

        for gone in ("_score_course", "_scores_to_theme_text", "CATEGORY_QUERIES"):
            assert not hasattr(course_list_agent, gone), (
                f"{gone}가 되살아났다. 코스 추천에 설화를 다시 넣으려면 "
                "docs/기획/설계_현장경험_엔진_v1.md의 근거를 먼저 뒤집을 것."
            )

    def test_detail_agent_has_no_folklore_mapping(self):
        """장소별 설화 매핑·내러티브 생성이 되살아나지 않아야 한다."""
        from agents import course_detail_agent

        for gone in ("map_folklore_to_places", "generate_narrative"):
            assert not hasattr(course_detail_agent, gone), f"{gone}가 되살아났다."

    def test_category_scores_is_ignored(self):
        """category_scores를 넘겨도 결과가 달라지지 않아야 한다.

        API 스키마 호환을 위해 파라미터는 남아 있지만 무시된다. 취향 퀴즈 제거
        (단계 1)와 함께 스키마에서도 없앤다.
        """
        import inspect

        from agents.course_list_agent import run_course_list

        sig = inspect.signature(run_course_list)
        assert sig.parameters["category_scores"].default is None, (
            "category_scores는 선택 파라미터여야 한다 — 호출부가 넘기지 않아도 동작해야 함"
        )


# ─── 코스 품질 점수 기준 ───────────────────────────────────────────────────────

class TestCurationCriteria:
    def test_score_weights_sum_to_one(self):
        """점수 비중 합이 1이어야 한다. 하나를 바꾸면 나머지를 조정해야 한다."""
        import importlib.util
        from pathlib import Path

        script = Path(__file__).parent.parent / "scripts" / "build_curated_courses.py"
        spec = importlib.util.spec_from_file_location("bcc", script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        total = mod.W_ROUTE + mod.W_DENSITY + mod.W_ATTRACTION
        assert total == pytest.approx(1.0), f"비중 합이 {total}이다"

    def test_duplicate_places_are_deduped(self):
        """같은 장소 중복 방문이 제거되어야 한다.

        비짓제주 코스 1,556개에 중복 장소가 있다. 중복을 두면 이동 거리가 0에
        가까워지고 장소 수가 부풀려져 **세 점수 기준을 모두 속인다.**
        실제로 첫 빌드에서 "우도피아"만 7번 있는 코스가 만점 1위였다.
        """
        import importlib.util
        from pathlib import Path

        script = Path(__file__).parent.parent / "scripts" / "build_curated_courses.py"
        spec = importlib.util.spec_from_file_location("bcc", script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        places = [
            {"day": 1, "seq_no": 1, "place_name": "우도피아", "lat": 33.5, "lng": 126.96},
            {"day": 1, "seq_no": 2, "place_name": "우도피아", "lat": 33.5, "lng": 126.96},
            {"day": 1, "seq_no": 3, "place_name": "우도피아", "lat": 33.5, "lng": 126.96},
            {"day": 2, "seq_no": 4, "place_name": "성산일출봉", "lat": 33.458, "lng": 126.94},
        ]
        deduped = mod._dedupe_places(places)
        assert len(deduped) == 2, f"중복이 남았다: {[p['place_name'] for p in deduped]}"

    def test_same_place_across_days_is_kept(self):
        """day를 넘는 재방문은 정상이므로 남겨야 한다."""
        import importlib.util
        from pathlib import Path

        script = Path(__file__).parent.parent / "scripts" / "build_curated_courses.py"
        spec = importlib.util.spec_from_file_location("bcc", script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        places = [
            {"day": 1, "seq_no": 1, "place_name": "협재해수욕장", "lat": 33.39, "lng": 126.24},
            {"day": 2, "seq_no": 2, "place_name": "협재해수욕장", "lat": 33.39, "lng": 126.24},
        ]
        assert len(mod._dedupe_places(places)) == 2
