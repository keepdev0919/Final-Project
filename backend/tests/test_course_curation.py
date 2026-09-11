"""코스 큐레이션 — 설화 없는 품질 기준을 지키는 테스트.

`test_folklore_mapping.py`를 대체한다. 그 파일은 설화 취향 점수(`_scores_to_theme_text`)와
설화 매핑(`map_folklore_to_places`)을 테스트했는데, 2026-08-13에 코스 추천에서 설화를
분리하면서 두 함수가 사라졌다.

여기 테스트는 버그 잡기가 아니라 **결정을 코드에 박아두기 위한 것**이다.
"""
import math
import re

import pytest

from agents.course_list_agent import _haversine_m
from services.db import get_db_connection


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
                "docs/공고.md §3 P0-1의 근거를 먼저 뒤집을 것."
            )

    def test_detail_agent_has_no_folklore_mapping(self):
        """장소별 설화 매핑·내러티브 생성이 되살아나지 않아야 한다."""
        from agents import course_detail_agent

        for gone in ("map_folklore_to_places", "generate_narrative"):
            assert not hasattr(course_detail_agent, gone), f"{gone}가 되살아났다."

# ─── 코스 품질 점수 기준 ───────────────────────────────────────────────────────

class TestCurationCriteria:
    def test_no_quality_score_exists(self):
        """코스에 품질 점수를 다시 붙이지 않는다 (2026-09-10 결정).

        원본은 사람이 실제로 짠 여행 일정이다. 우리가 코스를 설계하는 게 아니라
        남이 짠 일정을 고르는 것이므로, 걸러야 할 것은 「우리 기준에 안 맞는
        코스」가 아니라 「일정이 아닌 데이터」다.

        실제로 점수제가 잘라내던 것을 열어보니 이런 것이었다:

            day1: 공항 → 관음사 → 사려니숲길 → 쌍둥이횟집 → 휴애리 → 호텔

        멀쩡한 제주 3박4일인데, 숙소·식당이 껴서 이동이 길고 관광지 비율이
        낮다는 이유로 감점됐다. 이런 일정 1,793개가 버려지고 있었다.

        점수 컬럼이 되살아나면 같은 일이 조용히 반복된다.
        """
        import importlib.util
        from pathlib import Path

        script = Path(__file__).parent.parent / "scripts" / "build_curated_courses.py"
        spec = importlib.util.spec_from_file_location("bcc", script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        weights = [n for n in dir(mod) if n.startswith("W_")]
        assert not weights, f"점수 가중치가 다시 생겼다: {weights}"

    def test_wishlist_is_rejected_by_distance_not_by_place_count(self):
        """찜 목록은 「장소가 많아서」가 아니라 「이동이 불가능해서」 걸러져야 한다.

        2026-09-10에 하루 장소 수 채점(35%)을 없앴다. 우리가 코스를 설계하는 게
        아니라 남이 짠 일정을 고르는 것이라, 하루 몇 곳이 적당한지는 우리가 정할
        일이 아니기 때문이다. 실제로 하루 5~8곳은 식당·숙소가 섞인 멀쩡한 일정이었다.

        그 결정이 성립하려면 **이동거리 상한이 찜 목록을 혼자서 걸러낼 수 있어야 한다.**
        원본에는 `한라산 → 우도 → 4.3평화공원`을 하루에 넣은 위시리스트가 있는데,
        이런 건 이동 거리가 저절로 터진다 (하루 14곳 이상은 100%가 90km 초과).

        이 테스트가 깨진다면 밀도 기준을 다시 넣을지 판단해야 한다.
        (`MAX_KM_PER_DAY` 150km — 제주 일주도로가 약 200km다)
        """
        import importlib.util
        from pathlib import Path

        script = Path(__file__).parent.parent / "scripts" / "build_curated_courses.py"
        spec = importlib.util.spec_from_file_location("bcc", script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        # 찜 목록: 하루에 제주 전역을 왕복한다. 실제 원본에 612km/일짜리가 있다
        wishlist = [
            {"day": 1, "seq_no": 1, "place_name": "성산일출봉", "lat": 33.458, "lng": 126.942},
            {"day": 1, "seq_no": 2, "place_name": "협재해수욕장", "lat": 33.394, "lng": 126.240},
            {"day": 1, "seq_no": 3, "place_name": "섭지코지", "lat": 33.424, "lng": 126.930},
            {"day": 1, "seq_no": 4, "place_name": "카멜리아힐", "lat": 33.290, "lng": 126.368},
            {"day": 1, "seq_no": 5, "place_name": "월정리해수욕장", "lat": 33.556, "lng": 126.795},
        ]
        wl_km = mod._km_per_day(wishlist, 1)
        assert wl_km > mod.MAX_KM_PER_DAY, (
            f"찜 목록이 이동거리 상한을 통과했다 — {wl_km:.0f}km/일"
        )

        # 빡빡하지만 실제 일정: 중문 일대 하루 7곳. 장소가 많다고 걸리면 안 된다
        tight = [
            {"day": 1, "seq_no": 1, "place_name": "주상절리대", "lat": 33.238, "lng": 126.427},
            {"day": 1, "seq_no": 2, "place_name": "중문색달해수욕장", "lat": 33.244, "lng": 126.412},
            {"day": 1, "seq_no": 3, "place_name": "천제연폭포", "lat": 33.252, "lng": 126.417},
            {"day": 1, "seq_no": 4, "place_name": "여미지식물원", "lat": 33.252, "lng": 126.412},
            {"day": 1, "seq_no": 5, "place_name": "테디베어뮤지엄제주", "lat": 33.249, "lng": 126.410},
            {"day": 1, "seq_no": 6, "place_name": "박물관은 살아있다", "lat": 33.247, "lng": 126.415},
            {"day": 1, "seq_no": 7, "place_name": "천지연폭포", "lat": 33.247, "lng": 126.554},
        ]
        tight_km = mod._km_per_day(tight, 1)
        assert tight_km <= mod.MAX_KM_PER_DAY, (
            f"하루 7곳이어도 이동이 짧으면 살아남아야 한다 — {tight_km:.0f}km/일"
        )

        # 하루 60km짜리 평범한 일정도 당연히 살아남아야 한다.
        # 예전 점수제는 이런 코스를 감점했다
        normal = [
            {"day": 1, "seq_no": 1, "place_name": "관음사", "lat": 33.427, "lng": 126.562},
            {"day": 1, "seq_no": 2, "place_name": "사려니숲길", "lat": 33.435, "lng": 126.641},
            {"day": 1, "seq_no": 3, "place_name": "휴애리", "lat": 33.311, "lng": 126.652},
            {"day": 1, "seq_no": 4, "place_name": "카멜리아힐", "lat": 33.290, "lng": 126.368},
        ]
        assert mod._km_per_day(normal, 1) <= mod.MAX_KM_PER_DAY

    def test_duplicate_places_are_deduped(self):
        """같은 장소 중복 방문이 제거되어야 한다.

        비짓제주 코스 1,556개에 중복 장소가 있다. 중복을 두면 이동 거리가 0에
        가까워져 **경로 점수를 속인다.**
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


# ─── 「이런 코스는 어때요?」 첫 화면 목록 ──────────────────────────────────────
#
# 이 목록은 코스 탭을 열자마자 아무 조건 없이 보이는 자리다. 여기가 조용히 망가지면
# 사용자가 앱에서 처음 보는 코스가 깨진 제목이거나 품질 미달 코스가 된다 —
# 화면은 멀쩡하고 내용만 나빠지므로 눈으로 잡기 어렵다.

class TestFeaturedCourses:
    """실제 DB(`storage/metadata.db`)를 읽는다. DB가 없으면 건너뛴다."""

    @pytest.fixture(scope="class")
    def featured(self):
        from agents.course_list_agent import run_featured_courses
        try:
            result = run_featured_courses(limit=5)
        except Exception as exc:                      # DB 미비 환경
            pytest.skip(f"코스 DB를 읽을 수 없음: {exc}")
        if result.get("error"):
            pytest.skip(f"코스 DB가 비어 있음: {result['error']}")
        return result["result_courses"]

    def test_returns_requested_count(self, featured):
        assert len(featured) == 5

    def test_titles_are_presentable(self):
        """원본 여행 일정의 장소 이름이 그대로 새어 나오면 안 된다.

        비짓제주 원본에는 관리용 메모가 붙은 이름이 있다:

            수목원테마파크_2025.11.11 영업종료(리모델링공사) / 2026.03.01 재오픈 예정
            이호테우해수욕장_old · 제주공룡랜드[휴장중] · 소노벨제주(미공개)

        코스 제목은 대표 장소 이름으로 자동 생성되므로 그대로 카드에 실린다.
        예전에는 이런 제목을 조회 단계에서 걸러냈는데, **제목만 깨진 것이지 코스는
        멀쩡해서** 1,200개가 같이 빠졌다. 지금은 장소 이름 자체를 정리한다
        (`backend/scripts/build_place_display_names.py`).

        괄호와 슬래시 자체는 막지 않는다 — 「용담/용두암 해안도로」,
        「알오름(성산읍)」처럼 원래 그런 이름이 있고, 특히 괄호가 같은 이름의
        다른 장소를 구별하는 경우에는 **떼면 안 된다.**

        무작위 다섯 장이 아니라 목록 전체를 본다. 표본만 보면 실패가 운에 달린다.
        """
        conn = get_db_connection()
        bad = re.compile(r"_|20\d\d|[\[\]]|미공개|중복\s*콘텐츠|영업\s*종료|폐업|휴장|철거|운영\s*중단")

        offenders = []
        for (title,) in conn.execute("SELECT title FROM curated_courses"):
            if bad.search(title) or len(title) > 40:
                offenders.append(title)
        assert not offenders, f"관리용 메모가 새어 나온 제목 {len(offenders)}개: {offenders[:3]}"

    def test_no_course_sends_travelers_to_a_closed_place(self):
        """폐업한 곳이 낀 코스는 추천 대상에 없어야 한다 (2026-09-11 조익준님 결정).

        화면에 보여줄 때 표시 이름이 「(폐업)」 표기를 떼어낸다 — 괄호를 정리하는
        규칙이 폐업 표기까지 같이 지운다(`build_place_display_names.py`). 그래서
        「북촌에가면(폐업)」이 앱에서는 「북촌에가면」으로 멀쩡하게 보이고, 코스를
        믿고 간 여행자가 문 닫은 가게 앞에서 헛걸음한다.

        원본은 2018년부터 쌓인 일정이라 그 뒤 문 닫은 곳이 섞여 있다. 비짓제주가
        폐업 표기를 단 곳만이라도 확실히 걸러낸다. 표시 이름으로 비교하므로 폐업
        표기가 붙기 전에 등록된 같은 가게도 함께 걸린다.
        """
        import json
        from services.place_display_names import JSON_PATH, shown

        closed = set(json.loads(JSON_PATH.read_text(encoding="utf-8"))["closed"])
        if not closed:
            pytest.skip("폐업 목록이 비어 있음")

        conn = get_db_connection()
        offenders = conn.execute(
            "SELECT DISTINCT cc.title, cp.place_name FROM curated_courses cc "
            "JOIN course_places cp ON cp.course_id = cc.id"
        ).fetchall()
        hits = [(t, n) for t, n in offenders if shown(n) in closed]
        assert not hits, f"폐업 장소를 품은 추천 코스 {len(hits)}건: {hits[:3]}"

    def test_every_course_has_places_to_show(self, featured):
        """카드에 대표 장소를 3개까지 보여준다. 장소가 없으면 빈 카드가 된다."""
        for course in featured:
            assert len(course["places"]) >= 3, f"장소가 모자란 코스: {course['title']}"

    def test_refresh_shows_different_courses(self):
        """새로고침이 갱신 수단이다. 매번 같은 다섯 장이면 새로고침이 무의미해진다."""
        from agents.course_list_agent import run_featured_courses
        try:
            first = {c["id"] for c in run_featured_courses(limit=5)["result_courses"]}
            second = {c["id"] for c in run_featured_courses(limit=5)["result_courses"]}
        except Exception as exc:
            pytest.skip(f"코스 DB를 읽을 수 없음: {exc}")
        if not first:
            pytest.skip("코스 DB가 비어 있음")
        assert first != second, "두 번 불렀는데 같은 코스만 나온다"


# ─── 고른 일수와 코스 일수의 관계 ──────────────────────────────────────────────

class TestDurationMatching:
    """고른 일수보다 **짧은** 코스를 주지 않는다 (2026-09-10).

    예전에는 ±1일이었다. 그러면 「2박3일」을 고른 사람에게 1박2일 코스가 떠서
    하루가 통째로 빈다. 반대 방향은 덜 나쁘다 — 4일 코스의 day4는 평균 3.2곳이고
    59%가 공항을 포함해, 「오전에 두세 곳 돌고 공항」이라 덜어내기 쉽다.

    당일치기만 예외로 +1도 주지 않는다. 1박2일에서 day2(평균 4.4곳)를 빼면 절반이
    날아가고, 애초에 숙박을 전제로 짠 동선이라 하루로 쪼개지지 않는다.

    이 테스트는 실제 DB를 읽는다. 데이터가 바뀌어도 규칙은 지켜져야 한다.
    """

    @pytest.mark.parametrize("duration_days", [1, 2, 3, 4])
    @pytest.mark.parametrize("region", ["동부", "서부", "남부", "북부"])
    def test_never_returns_a_shorter_course(self, region, duration_days):
        from agents.course_list_agent import run_course_list

        result = run_course_list(region=region, duration_days=duration_days)
        assert not result["error"], result["error"]
        assert result["result_courses"], f"{region} {duration_days}일에 후보가 없다"

        for course in result["result_courses"]:
            last_day = max(p["day"] for p in course["places"])
            assert last_day >= duration_days, (
                f"{duration_days}일을 골랐는데 {last_day}일짜리가 왔다: {course['title']}"
            )
            # 마지막 선택지(「3박4일 이상」)만 위로 열려 있고, 그것도 일주일까지다.
            # 원본에 있는 28일짜리 한 달 살기 일정을 4일 여행자에게 주면 안 된다.
            limit = 7 if duration_days >= 4 else duration_days
            assert last_day <= limit, (
                f"{duration_days}일을 골랐는데 {last_day}일짜리가 왔다: {course['title']}"
            )

    def test_day_trip_gets_only_single_day_courses(self):
        """당일치기는 1박2일 코스를 받으면 안 된다."""
        from agents.course_list_agent import run_course_list

        for region in ("동부", "서부", "남부", "북부"):
            for course in run_course_list(region=region, duration_days=1)["result_courses"]:
                last_day = max(p["day"] for p in course["places"])
                assert last_day == 1, f"당일치기에 {last_day}일 코스가 왔다: {course['title']}"

    def test_titles_are_unique_within_one_result(self):
        """같은 제목의 카드가 한 화면에 두 번 뜨면 안 된다.

        제목이 `대표장소 + 개수`뿐이라 6,339개 중 47%가 다른 코스와 겹친다
        (「북부 4일 · 산굼부리 외 10곳」이 70개). 내용은 서로 다르지만 사용자
        눈에는 같은 카드다.
        """
        from agents.course_list_agent import run_course_list, run_featured_courses

        for _ in range(20):
            for region in ("동부", "북부"):
                titles = [c["title"] for c in run_course_list(region=region, duration_days=3)["result_courses"]]
                assert len(titles) == len(set(titles)), f"제목 중복: {titles}"

            featured = [c["title"] for c in run_featured_courses(limit=5)["result_courses"]]
            assert len(featured) == len(set(featured)), f"제목 중복: {featured}"
