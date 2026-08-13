"""여정(장소 1개 = 유료 상품) 요약 엔드포인트.

성산 여정의 값들은 설계 SSoT(docs/기획/설계_현장경험_엔진_v1.md §2)에서 왔다.
아래 세 개는 바꾸면 조용히 망가지므로 못 박는다.

- kto_content_id 126435: 성산일출봉의 한국관광공사 contentid.
  틀리면 장소 정보가 엉뚱한 곳을 가리키는데 화면은 멀쩡히 뜬다.
- price_krw ≤ 5000, valid_days == 90: 설계 §4에서 확정한 상품 조건이다.
  결제(묶음 C)의 90일 만료 계산이 이 값을 전제한다.
- free_story_count: 전체의 30~40%. 무료 구간이 없으면 사용자가 결제 화면을
  만나기 전에 아무것도 경험하지 못한다.
"""


def test_journeys_list_contains_seongsan(client):
    res = client.get("/journeys")
    assert res.status_code == 200
    ids = [j["journey_id"] for j in res.json()["journeys"]]
    assert "seongsan" in ids


def test_seongsan_kto_content_id_is_pinned(client):
    """성산일출봉 contentid는 126435 (contenttypeid 12)."""
    body = client.get("/journeys/seongsan").json()
    assert body["kto_content_id"] == "126435"


def test_seongsan_product_terms(client):
    """5,000원 이하 · 90일 이용. 설계 §4에서 확정한 조건이다."""
    body = client.get("/journeys/seongsan").json()
    assert 0 < body["price_krw"] <= 5000
    assert body["valid_days"] == 90


def test_free_portion_is_between_30_and_40_percent(client):
    """무료 구간은 전체의 30~40%.

    0이면 결제 전에 아무것도 못 듣고, 너무 크면 낼 이유가 없어진다.
    """
    body = client.get("/journeys/seongsan").json()
    ratio = body["free_story_count"] / body["story_count"]
    assert 0.3 <= ratio <= 0.4, f"무료 비율 {ratio:.0%}"


def test_journey_endpoint_takes_no_coordinates(client):
    """여정 조회가 사용자 좌표를 받지 않아야 한다.

    위치 판정은 단말에서만 한다(설계 §6). '지금 여기예요' 배지도 앱이
    자기 위치와 여정 좌표를 비교해 스스로 판단한다.
    """
    from main import app

    journey_routes = [r for r in app.routes if getattr(r, "path", "").startswith("/journeys")]
    assert journey_routes, "여정 라우트가 없다"
    for route in journey_routes:
        names = {p.name for p in route.dependant.query_params}
        assert not ({"lat", "lng"} & names), f"{route.path}가 좌표를 받는다"


def test_unknown_journey_returns_404(client):
    assert client.get("/journeys/nope").status_code == 404
