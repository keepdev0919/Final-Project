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


def test_wide_radius_requires_a_name_match(monkeypatch):
    """넓은 반경에서는 이름이 맞아야만 받아들인다.

    카드 사진을 찾을 때 반경 500m로는 섭지코지·우도·카멜리아힐이 안 잡힌다 —
    비짓제주 평균 좌표가 실제 관광지에서 그만큼 벗어나 있다. 그래서 2km로 다시 부른다.

    그런데 `_find_content_id`에는 **이름이 하나도 안 맞으면 가장 가까운 것을 쓰는**
    폴백이 있다. 2km에서 그 폴백이 살아 있으면 섭지코지 카드에 근처 카페 사진이 붙는다.
    화면은 멀쩡하고 사진도 예쁘게 나오므로 **눌러봐도 절대 안 잡힌다.**

    사진이 없는 것보다 틀린 사진이 붙는 게 나쁘다.
    """
    from routers import place

    calls = []

    def fake_kto_get(service, operation, params):
        calls.append(params["radius"])
        return {"response": {"body": {"items": {"item": [
            {"title": "전혀 다른 카페", "contentid": "99999", "contenttypeid": "39"},
        ]}}}}

    monkeypatch.setattr(place, "_kto_get", fake_kto_get)

    # 좁은 반경: 이름이 안 맞아도 가장 가까운 것을 쓴다 (기존 동작 유지)
    assert place._find_content_id("섭지코지", 33.42, 126.93) == ("99999", "39")
    # 넓은 반경: 이름이 안 맞으면 아무것도 안 준다
    assert place._find_content_id(
        "섭지코지", 33.42, 126.93, radius=2000, require_name_match=True
    ) is None
    assert calls == [500, 2000]


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
    monkeypatch.setattr(place, "_find_content_id", lambda *a, **k: None)

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


def test_every_stage_card_resolves_to_a_real_place(db_conn):
    """`home_stage.json`의 이름이 전부 `home_places`에 있어야 한다.

    이름이 하나 안 맞으면 **홈에서 카드가 조용히 사라진다.** 에러도 안 나고
    나머지 5장이 정상으로 보이므로, 눌러보는 검증으로는 "6장이어야 하는데 5장"임을
    알 방법이 없다. 이름은 `home_places`가 다듬은 값(괄호 뗀 뒤)과 정확히 같아야 한다.
    """
    from services import home_places

    data = home_places._load_stage_file()
    entries = data.get("stages", [])
    assert entries, "스테이지가 비었다"

    got = home_places.stages()
    missing = {e["name"] for e in entries} - {s["name"] for s in got}
    assert not missing, f"home_places에 없는 이름: {missing}"
    assert len(got) == len(entries)


def test_every_stage_has_a_label_and_a_mission():
    """라벨과 미션이 비어 있으면 안 된다.

    미션은 카드의 **유일한 문장**이라 비면 카드가 이름만 남은 목록이 된다.
    라벨이 비면 사진 위 칩이 빈 노란 사각형으로 뜬다 — 둘 다 화면이 깨지지는 않아서
    눈으로 훑을 때 놓치기 쉽다.
    """
    from services import home_places

    data = home_places._load_stage_file()
    labels = data.get("labels", {})
    for entry in data["stages"]:
        assert entry.get("mission", "").strip(), f"{entry['name']}: 미션이 없다"
        assert entry.get("label") in labels, f"{entry['name']}: 라벨 '{entry.get('label')}'이 없다"


def test_label_icons_exist_in_the_app():
    """`home_stage.json`의 아이콘 이름이 앱에 실제로 있어야 한다.

    서버가 모르는 이름을 보내면 `HomeStage.labelGlyph`가 nil이 되고 칩에 글자만 남는다.
    앱은 안 깨지지만 아이콘이 조용히 사라진다. 라벨을 추가할 때 도트 모양 그리는 것을
    잊는 일이 실제로 일어난다.
    """
    from pathlib import Path

    from services import home_places

    icons = {v["icon"] for v in home_places._load_stage_file()["labels"].values()}
    swift = (Path(__file__).resolve().parents[1] / "ios" / "JejuFolklore" / "Sources"
             / "Models" / "HomeStage.swift").read_text(encoding="utf-8")
    missing = [i for i in icons if f'case "{i}"' not in swift]
    assert not missing, f"HomeStage.labelGlyph가 모르는 아이콘: {missing}"
