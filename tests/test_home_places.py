"""홈 장소 카드의 결정을 지킨다.

홈은 사용자와 심사위원이 **가장 먼저 보는 화면**이다. 여기 뜨는 10개가 틀리면
화면은 멀쩡한데 앱의 첫인상이 망가진다. 눌러보는 검증으로는 "카드가 나온다"까지만
확인되고 "맞는 카드가 나오는가"는 확인되지 않는다.
"""

import pytest

from services import home_places


def test_airport_and_terminals_are_excluded():
    """공항·터미널·면세점을 관광지로 보지 않는다.

    이름을 오디에서 뽑게 된 뒤로 이 규칙이 목록을 거르는 일은 없어졌다(오디에 공항
    해설이 없다). 그래도 규칙은 남긴다 — 사진을 찾을 때 KTO 후보를 고르는 데 쓰이고,
    오디에 교통시설 해설이 생기면 다시 필요해진다.
    """
    assert home_places.is_excluded("제주국제공항")
    assert home_places.is_excluded("제주국제공항 버스터미널")
    assert home_places.is_excluded("제주관광공사 중문면세점 (내국인)")
    assert not home_places.is_excluded("성산일출봉")
    assert not home_places.is_excluded("천지연폭포")


def test_place_names_drop_trailing_parentheses():
    """괄호 부가설명을 뗀다.

    비짓제주 이름이 `성산일출봉(UNESCO 세계자연유산)`,
    `만장굴(안전점검 및 내부공사로 운영중단)`처럼 온다. 그대로 쓰면
    ① 카드 제목이 두 줄이 되고 ② 운영 상태 같은 건 시간이 지나면 거짓이 된다.

    `_old` 접미도 뗀다 — 비짓제주에 남은 옛 항목이라 같은 장소가 두 번 보인다.
    """
    assert home_places.clean_name("성산일출봉(UNESCO 세계자연유산)") == "성산일출봉"
    assert home_places.clean_name("우도(해양도립공원)") == "우도"
    assert home_places.clean_name("이호테우해수욕장_old") == "이호테우해수욕장"
    # 괄호가 이름의 일부일 때는 남긴다 — 앞에 다른 글자가 없으면 이름이 사라진다.
    assert home_places.clean_name("(사)제주해녀협회") == "(사)제주해녀협회"


def test_story_radius_is_700m_so_seongsan_survives():
    """해설 매칭 반경이 700m 이상이어야 한다.

    성산일출봉은 오디 좌표(정상 부근)와 비짓제주 좌표(주차장 쪽)가 **551m** 떨어져 있다.
    500m로 줄이면 **1위 장소가 홈에서 사라진다**(2026-08-22 실측).
    반경을 줄일 일이 생기면 유명한 곳이 빠지는지 먼저 확인할 것.
    """
    assert home_places.STORY_RADIUS_M >= 600.0


def test_distance_matches_known_pair():
    """거리 계산이 맞아야 한다. 이게 틀리면 매칭 전체가 조용히 어긋난다.

    성산일출봉 실측 좌표 한 쌍을 박아둔다 —
    비짓제주 평균 `(33.458057, 126.942498)` ↔ 오디 stid 969 `(33.461861, 126.938694)`.
    **551m**. 이 숫자가 `STORY_RADIUS_M`을 700으로 잡은 이유다.
    """
    got = home_places._distance_m(33.458057, 126.942498, 33.461861, 126.938694)
    assert 540 < got < 560, got
    # 같은 점은 0
    assert home_places._distance_m(33.0, 126.0, 33.0, 126.0) == pytest.approx(0)


def test_one_card_per_place(db_conn):
    """같은 장소가 카드 두 개로 나오면 안 된다.

    비짓제주에는 한 곳을 여러 이름으로 적어둔 경우가 많다 —
    이호테우말등대 · 이호테우해수욕장 · 이호테우해수욕장_old가 전부 같은 해설을 가리킨다.
    묶지 않으면 홈 10칸 중 3칸이 같은 해변이 된다.
    """
    places = home_places.compute(db_conn)
    assert places, "장소 목록이 비었다"
    stids = [p["stid"] for p in places]
    assert len(stids) == len(set(stids)), "같은 해설이 두 장소의 대표가 됐다"

    # 해설도 두 장소에 겹쳐 들어가면 안 된다 — 한 해설은 한 장소의 것이다
    seen: set[str] = set()
    for place in places:
        for story in place["stories"]:
            assert story["stid"] not in seen, f"해설 {story['stid']}가 두 장소에 있다"
            seen.add(story["stid"])


def test_place_names_come_from_odii_titles():
    """장소 이름을 오디 해설 제목에서 뽑아야 한다.

    오디 제목은 장소 이름이 아니라 **해설 제목**이라 손질이 필요하다. 세 규칙을 박아둔다.

    한때 이름을 비짓제주에서 가져왔다. 그러면 두 가지가 동시에 망가진다 —
    비짓제주에 없는 곳 18곳(사려니숲길·가파도…)이 **목록에서 통째로 사라지고**,
    아무도 안 가져간 묶음을 근처 **식당이 가져간다**(자리돔횟집이 456m 떨어진
    「서귀포 기적의 도서관」 해설을 선점했다). 둘 다 화면은 멀쩡해서 안 보인다.
    """
    from services.home_places import place_name_from_stories as name

    # ① 여러 해설의 공통 접두어가 곧 장소 이름이다
    assert name(["관음사 일주문", "관음사 대웅전", "관음사 해월굴"]) == "관음사"
    assert name(["약천사 법고", "약천사 종각"]) == "약천사"
    # 접두어가 너무 짧으면 장소 이름이 아니다 — 「산방산」과 「산방연대」의 「산방」
    assert name(["산방산과 용머리해안", "산방연대"]) != "산방"

    # ② 「수식어, 실제이름」은 쉼표 뒤가 장소다
    assert name(["낭만적인 힐링의 섬, 가파도"]) == "가파도"
    assert name(["하늘을 품은 바다, 평대 해변"]) == "평대 해변"

    # ③ 분류 딱지는 뗀다
    assert name(["열린관광지 - 제주도 서귀포 치유의 숲"]) == "서귀포 치유의 숲"

    # 손댈 필요 없는 것은 그대로
    assert name(["성산일출봉"]) == "성산일출봉"


def test_place_names_are_unique(db_conn):
    """장소 이름이 겹치면 안 된다.

    홈 스테이지가 **이름으로** 장소를 찾는다. 겹치면 어느 쪽이 연결될지 알 수 없고,
    엉뚱한 장소가 홈에 뜬 채로 출시된다.

    실제로 겹친 적이 있다 — 오디에 감성 제목 시리즈가 12건 따로 있어서
    「가파도」와 「낭만적인 힐링의 섬, 가파도」가 둘 다 「가파도」로 뽑혔다.
    그런 것은 `data/place_names.json`에서 **stid로 짚어** 고친다.
    """
    names = [p["name"] for p in home_places.compute(db_conn)]
    dupes = {n for n in names if names.count(n) > 1}
    assert not dupes, f"이름이 겹친다: {dupes}. place_names.json에서 stid로 짚어 고칠 것"


def test_every_place_has_a_playable_story(db_conn):
    """카드가 있으면 들을 것도 있어야 한다.

    홈 카드를 누르는 이유가 해설이다. 대본 없는 항목이 섞이면 눌러도 아무 일이 없고,
    사용자는 앱이 고장난 줄 안다. 오디 226건 중 대본 없는 것이 실제로 35건 있다.
    """
    for place in home_places.compute(db_conn)[:20]:
        assert place["stid"], place
        assert place["story_seconds"] > 0, place


def test_nearby_search_never_substitutes_the_closest_place(monkeypatch):
    """이름이 안 맞으면 **어느 반경에서도** 아무것도 주지 않는다.

    전에는 반경 500m 에서 이름이 하나도 안 맞으면 가장 가까운 것을 대신 썼다.
    그래서 코스에서 `해녀의부엌 종달점`을 누르면 KTO 에 없으니 바로 옆
    `종달리해변`의 사진과 설명이 붙었다 (2026-09-10 실측). 화면은 멀쩡해 보여서
    눌러봐도 절대 안 잡힌다.

    사진이 없는 것보다 틀린 사진이 붙는 게 나쁘다.
    """
    from routers import place

    calls = []

    def fake_kto_get(service, operation, params):
        calls.append(params["radius"])
        return {"response": {"body": {"items": {"item": [
            {"title": "종달리해변", "contentid": "99999", "contenttypeid": "12"},
        ]}}}}

    monkeypatch.setattr(place, "_kto_get", fake_kto_get)
    monkeypatch.setattr(place, "_search_by_keyword", lambda name: [])

    assert place.find_content_id("해녀의부엌 종달점", 33.49, 126.91) is None
    assert calls == [500, 2000]


def test_course_place_detail_accepts_restaurants_when_name_matches(monkeypatch):
    """코스 장소 상세는 식당·카페도 찾아야 한다.

    홈·PLAY 는 관광지 계열만 받지만(`find_sight_content_id`), 코스에는 빵집·식당이
    들어 있다. 종류를 좁히지 않은 `find_content_id` 는 이름이 맞는 음식점(39)을
    그대로 준다 — 이걸 막으면 코스 장소 상세가 텅 빈다.
    """
    from routers import place

    monkeypatch.setattr(place, "_search_by_keyword", lambda name: [{
        "title": "해녀의부엌 종달점", "contentid": "4242", "contenttypeid": "39",
        "mapy": "33.49", "mapx": "126.91",
    }])

    assert place.find_content_id("해녀의부엌 종달점", 33.49, 126.91) == ("4242", "39")
    # 같은 후보라도 관광지만 받는 자리에서는 버린다.
    monkeypatch.setattr(place, "_kto_get",
                        lambda *a, **k: {"response": {"body": {"items": ""}}})
    assert place.find_sight_content_id("해녀의부엌 종달점", 33.49, 126.91) is None


def test_thumbnail_warming_targets_the_top_ranks(db_conn):
    """사진 채우기는 **상위 N곳**을 대상으로 해야 한다.

    `LIMIT ?`만 쓰면 "사진 없는 행 N개"가 되어, 30위권 사진을 받는 동안 홈에 실제로
    뜨는 상위 10곳이 비어 있는 일이 생긴다(2026-08-22에 실제로 그렇게 동작했다).
    홈은 상위 10곳만 보여주므로 그 10곳이 우선이다.
    """
    import inspect
    src = inspect.getsource(home_places.warm_thumbnails)
    assert "rank < ?" in src, "상위 순위로 한정하지 않고 있다"


def test_restaurants_and_lodging_are_not_sights():
    """음식점·숙박은 관광지 후보가 아니다.

    성산일출봉 좌표에서 반경 2km를 부르면 후보 10개 중 9개가 식당·펜션이다.
    타입을 안 거르면 `성산흑돼지두루치기 성산일출봉점`(39 음식점)이 뽑혀서
    **성산일출봉 카드에 식당 사진이 붙는다.** 2026-08-22에 실제로 그렇게 나왔다.

    38(쇼핑)은 넣는다 — 동문재래시장·서귀포매일올레시장이 쇼핑으로 분류돼 있고
    제주 관광의 축이며 오디 해설도 있다.
    """
    from routers.place import SIGHT_CONTENT_TYPES

    assert "39" not in SIGHT_CONTENT_TYPES, "음식점이 관광지 후보에 들어 있다"
    assert "32" not in SIGHT_CONTENT_TYPES, "숙박이 관광지 후보에 들어 있다"
    assert "12" in SIGHT_CONTENT_TYPES
    assert "38" in SIGHT_CONTENT_TYPES, "시장(쇼핑)이 빠졌다"


def test_name_containment_beats_similarity():
    """이름을 품고 있는 후보가 유사도보다 먼저다.

    `성산일출봉`을 찾을 때 후보가 둘이다 —
    `성산일출봉 [유네스코 세계자연유산]`(정답)과 `성산흑돼지두루치기 성산일출봉점`(식당).
    difflib 유사도만 쓰면 **식당이 이긴다.** 정답 뒤에 붙은 `[유네스코 세계자연유산]`이
    길어서 유사도가 떨어지기 때문이다(2026-08-22 실측).

    그래서 완전일치 → 접두 → 포함 → 유사도 순으로 본다.
    """
    from routers.place import _pick_by_name

    candidates = [
        {"title": "성산흑돼지두루치기 성산일출봉점", "contentid": "1", "contenttypeid": "39"},
        {"title": "성산일출봉 [유네스코 세계자연유산]", "contentid": "2", "contenttypeid": "12"},
    ]
    assert _pick_by_name("성산일출봉", candidates)["contentid"] == "2"

    # 아무것도 안 맞으면 None을 준다 (호출부가 "없음"으로 처리할 수 있게)
    assert _pick_by_name("한라산", [{"title": "카페 봄", "contentid": "3"}]) is None


def test_keyword_search_must_not_send_areacode(monkeypatch):
    """이름 검색에 `areaCode`를 붙이면 안 된다.

    `areaCode=39`(제주)를 붙이면 천지연폭포·카멜리아힐·오설록 티뮤지엄이
    **빈 결과로 돌아온다**(2026-08-22 실측). 붙이지 않으면 정상이다.
    지역이 맞는지는 거리 검증(`NAME_SEARCH_MAX_DISTANCE_M`)이 판단한다.

    붙여도 예외가 안 나고 그냥 "그 장소는 사진이 없다"로 보이므로 조용히 망한다.
    """
    from routers import place

    seen = {}

    def fake_kto_get(service, operation, params):
        seen.update(params)
        return {"response": {"body": {"items": ""}}}

    monkeypatch.setattr(place, "_kto_get", fake_kto_get)
    place._search_by_keyword("천지연폭포")
    assert "areaCode" not in seen, f"areaCode를 보내고 있다: {seen}"
    assert seen.get("keyword") == "천지연폭포"


def test_name_search_result_must_be_nearby(monkeypatch):
    """이름으로 찾은 결과가 멀면 버린다.

    `우도`로 검색하면 전남 강진의 `가우도`가, `주상절리대`로 검색하면 광주
    `무등산 주상절리대`가 온다(실측). 둘 다 타입 12(관광지)라 타입 검사로는 걸러지지 않는다.

    거리로 걸러내지 않으면 제주 앱의 우도 카드에 **전라남도 사진**이 붙는다.
    """
    from routers import place

    def fake_search(name):
        return [{
            "title": "가우도", "contentid": "77", "contenttypeid": "12",
            "mapy": "34.6", "mapx": "126.7",  # 전남 강진
        }]

    monkeypatch.setattr(place, "_search_by_keyword", fake_search)
    monkeypatch.setattr(place, "_nearby_content_id", lambda *a, **k: None)

    # 제주 우도 좌표로 물어보면 전남 결과는 버려진다
    assert place.find_sight_content_id("가우도", 33.50, 126.95) is None


def test_screens_never_claim_a_number_of_people():
    """화면에 「N명」으로 사람 수를 적지 않는다.

    우리가 가진 값은 `COUNT(DISTINCT course_id)` — **그 장소가 담긴 여행 일정의 수**다.
    한 사람이 일정을 여러 개 만들 수 있으므로 **사람 수는 데이터에 없다.**

    2026-08-22에 홈 카드가 「여행자 2,668명」, 안내문이 「실제 여행자 9,134명의 일정」으로
    나갔다가 조익준님이 잡았다. 숫자는 진짜인데 단위가 거짓이다 — 화면은 완벽히 정상이고
    테스트도 통과하므로 **사람이 읽어야만 잡힌다.** 그래서 문구를 코드로 묶어둔다.

    공모전 제출물에도 같은 문구가 들어가고, 「거짓이 없는지」는 위임하지 않는 항목이다.
    """
    from pathlib import Path

    sources = Path(__file__).resolve().parents[1] / "ios" / "JejuFolklore" / "Sources"
    offenders = []
    for path in sources.rglob("*.swift"):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "//" in line and line.strip().startswith("//"):
                continue  # 주석은 설명이라 봐준다
            if "여행자" in line and "명" in line:
                offenders.append(f"{path.name}:{lineno} {line.strip()}")
    assert not offenders, "사람 수를 주장하는 문구가 있다:\n" + "\n".join(offenders)


def test_accessibility_rows_drop_kto_suffix_and_empty_fields(monkeypatch):
    """무장애 정보는 **있는 항목만, 꼬리표 없이** 준다.

    KTO 는 `장애인 전용 주차구역 있음(3대)_무장애 편의시설` 처럼 값 뒤에 분류
    꼬리표를 붙여 보낸다 (2026-09-10 협재 실측). 그대로 보여주면 화면에
    `_무장애 편의시설` 이 글자로 찍힌다. 빈 칸은 목록에서 빠져야 한다 —
    스무 칸을 다 늘어놓으면 「없음」이 「있음」을 묻는다.
    """
    from routers import place

    monkeypatch.setattr(place, "_kto_get", lambda *a, **k: {"response": {"body": {"items": {"item": [{
        "contentid": "127490",
        "parking": "장애인 전용 주차구역 있음(3대,공영주차장)_무장애 편의시설",
        "restroom": "장애인 전용화장실 있음",
        "wheelchair": "",
        "elevator": None,
    }]}}}})

    rows = place._fetch_accessibility("127490")
    assert rows == [
        {"label": "장애인 주차", "value": "장애인 전용 주차구역 있음(3대,공영주차장)"},
        {"label": "장애인 화장실", "value": "장애인 전용화장실 있음"},
    ]


def test_info_rows_tidy_kto_labels(monkeypatch):
    """반복정보의 이름표는 KTO 가 `입 장 료` 처럼 띄어 보낸다. 붙여서 준다."""
    from routers import place

    monkeypatch.setattr(place, "_kto_get", lambda *a, **k: {"response": {"body": {"items": {"item": [
        {"infoname": "입 장 료", "infotext": "무료"},
        {"infoname": "화장실", "infotext": "있음<br>주차장 옆"},
        {"infoname": "비어있음", "infotext": ""},
    ]}}}})

    assert place._fetch_info("1", "12") == [
        {"label": "입장료", "value": "무료"},
        {"label": "화장실", "value": "있음\n주차장 옆"},
    ]


def test_nearby_facilities_skip_broken_coords_and_collapse_duplicates(monkeypatch):
    """주변 시설은 **깨진 좌표는 건너뛰고, 같은 이름은 하나만, 가까운 순**이다.

    제주시 화장실 데이터에는 `126..42388329` 같은 좌표가 6건 섞여 있고
    (2026-09-10 실측), 해수욕장 관리센터 화장실은 같은 이름으로 세 개가 등록돼
    있다. 정류장은 길 양쪽이 같은 이름이다. 그대로 두면 다섯 줄이 두 이름으로 찬다.
    """
    from routers import place

    place._toilet_cache.update(items=[
        {"toiletNm": "관리센터", "laCrdnt": "33.5435", "loCrdnt": "126.6696", "opnTimeInfo": "연중무휴",
         "maleDspsnClosetCnt": "1", "femaleDspsnClosetCnt": "0"},
        {"toiletNm": "관리센터", "laCrdnt": "33.5440", "loCrdnt": "126.6700", "opnTimeInfo": "연중무휴"},
        {"toiletNm": "깨진좌표", "laCrdnt": "126..4238", "loCrdnt": "33.5"},
        {"toiletNm": "먼곳", "laCrdnt": "33.60", "loCrdnt": "126.70", "opnTimeInfo": ""},
    ], at=9e12)

    toilets = place._toilets_near(33.5434, 126.6695)
    assert [t["name"] for t in toilets] == ["관리센터"]
    assert toilets[0]["accessible"] is True
    assert toilets[0]["distance_m"] < 100

    monkeypatch.setattr(place, "_public_get", lambda url, params: {"response": {"body": {"items": {"item": [
        {"nodenm": "용마로", "gpslati": "33.5152", "gpslong": "126.5062"},
        {"nodenm": "용마로", "gpslati": "33.5148", "gpslong": "126.5059"},
        {"nodenm": "용마마을", "gpslati": "33.5168", "gpslong": "126.5037"},
    ]}}}})
    stops = place._bus_stops_near(33.5160, 126.5059)
    assert [s["name"] for s in stops] == ["용마로", "용마마을"]
    assert stops[0]["distance_m"] <= stops[1]["distance_m"]


def test_intro_fields_get_the_same_cleanup_as_info_rows(monkeypatch):
    """운영시간·휴무·입장료·주차도 `<br>` 을 줄바꿈으로 바꿔 준다.

    반복정보와 무장애는 정리를 거치는데 이 네 칸만 빠져 있어서, 성산일출봉
    운영시간에 `<br>` 이 **글자로 찍혔다** (2026-09-10 발견, 캐시 204곳 중 10곳).
    """
    from routers import place

    monkeypatch.setattr(place, "_kto_get", lambda *a, **k: {"response": {"body": {"items": {"item": [{
        "usetime": "- 1~2월 06:00~18:00 (매표마감 17:00)<br>\n- 3~4월 05:00~19:00",
        "restdate": "연중무휴",
        "parking": "가능",
    }]}}}})

    intro = place._fetch_intro("126486", "12")
    assert intro["open_time"] == "- 1~2월 06:00~18:00 (매표마감 17:00)\n- 3~4월 05:00~19:00"
    assert intro["rest_date"] == "연중무휴"


def test_clean_text_restores_lines_kto_squashed_together():
    """줄바꿈 없이 붙어서 온 운영시간을 원래 줄로 되돌린다.

    카멜리아힐은 KTO 원문 자체가 `[하절기]- 08:30~18:30- 입장 마감 17:30[동절기]…`
    처럼 한 줄이다 (2026-09-10 실측). 이대로 보여주면 「…17:30[동절기…」로 읽힌다.
    범위 표시 `10:00 - 18:00` 의 `-` 는 항목 표시가 아니므로 끊지 않는다.
    """
    from routers.place import _clean_text

    squashed = "[하절기/간절기(3월~11월)]- 08:30~18:30- 입장 마감 17:30[동절기(11월~2월)]- 08:30~18:00- 입장 마감 17:00"
    assert _clean_text(squashed).split("\n") == [
        "[하절기/간절기(3월~11월)]",
        "- 08:30~18:30",
        "- 입장 마감 17:30",
        "[동절기(11월~2월)]",
        "- 08:30~18:00",
        "- 입장 마감 17:00",
    ]
    assert _clean_text("10:00 - 18:00") == "10:00 - 18:00"
    assert _clean_text("[개인]\n- 성인 12,000원\n[단체]\n- 성인 10,000원").split("\n") == [
        "[개인]", "- 성인 12,000원", "[단체]", "- 성인 10,000원",
    ]


def test_clean_text_leaves_real_sentences_and_ranges_alone():
    """줄을 되살리는 규칙이 **다른 장소의 진짜 문장을 망가뜨리지 않는다.**

    성산일출봉 실측값(2026-09-10)으로 잡는다:
    - `성산일출봉입구[서] 정류장` 의 `[서]` 는 정류장 방향이지 머리가 아니다.
    - `안내 가능- 시간 : 09:00~17:00- 대기장소 : …` 는 세 군데 **모두** 끊어야 한다.
      숫자 앞에서만 끊으면 한 문장이 반만 갈라져 전보다 더 이상하다.
    - `[11월~2월] - 06:00~18:00 - 매표 마감 17:00 [3월/…]` 처럼 양쪽 공백이 있어도 끊는다.
    - `<br>` 로 이미 줄이 나뉜 값은 손대지 않는다.
    """
    from routers.place import _clean_text

    assert _clean_text("대중교통 이용가능 : 성산일출봉입구[서] 정류장저상버스 없음.") == \
        "대중교통 이용가능 : 성산일출봉입구[서] 정류장저상버스 없음."

    guide = "자연유산해설사 안내 가능- 시간 : 09:00~17:00- 대기장소 : 탐방안내소- 문의처 : 064-710-7923"
    assert _clean_text(guide).split("\n") == [
        "자연유산해설사 안내 가능",
        "- 시간 : 09:00~17:00",
        "- 대기장소 : 탐방안내소",
        "- 문의처 : 064-710-7923",
    ]

    spaced = "[11월~2월] - 06:00~18:00 - 매표 마감 17:00 [3월/4월] - 05:00~19:00"
    assert _clean_text(spaced).split("\n") == [
        "[11월~2월]", "- 06:00~18:00", "- 매표 마감 17:00", "[3월/4월]", "- 05:00~19:00",
    ]

    assert _clean_text("09:00- 18:00") == "09:00- 18:00"
    assert _clean_text("2024-12-01 ~ 2025-02-28") == "2024-12-01 ~ 2025-02-28"
    already = "- 안내 가능- 시간 : 09:00<br>- 문의 064-1"
    assert _clean_text(already) == "- 안내 가능- 시간 : 09:00\n- 문의 064-1"
