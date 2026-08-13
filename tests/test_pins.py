"""설화 핀 엔드포인트 + 위치 전송 불변식.

`GET /pins?lat=&lng=` (좌표 조회)는 2026-08-13에 제거했다. 호출부가 없는 죽은
코드였고, 남겨두면 나중에 사용자 위치를 서버로 보내는 경로가 생긴다.
"""


def test_no_coordinate_query_endpoint(client):
    """제거한 `/pins?lat&lng` 경로가 되살아나지 않아야 한다."""
    res = client.get("/pins", params={"lat": 33.4581, "lng": 126.9415, "radius_m": 500})
    assert res.status_code == 404, "좌표를 받는 /pins 엔드포인트가 남아 있다"


def test_no_route_takes_user_coordinates():
    """좌표를 쿼리로 받는 라우트가 허용 목록 밖에 생기면 실패한다.

    위치정보법: 개인위치정보를 사업자 서버로 전송하면 DB 저장 여부와 무관하게
    위치기반서비스사업자 신고 대상이 된다(공지 FAQ). 현재 앱은 위치 판정을
    단말에서만 하므로 대상이 아니며, 이 상태를 유지해야 한다.

    경로 문자열 하나만 막으면 `/pins/search?lat=&lng=` 같은 다른 경로로
    부활할 수 있다. 라우트 테이블 전체를 훑어야 의도가 지켜진다.

    `/place/detail`은 예외다 — 받는 lat/lng가 사용자 위치가 아니라 **관광지
    자체의 좌표**다(PlaceDetailView가 place.lat/place.lng를 넘긴다).
    """
    from main import app

    ALLOWED = {"/place/detail"}  # 관광지 좌표만 받는 경로
    offenders = []
    for route in app.routes:
        dependant = getattr(route, "dependant", None)
        if dependant is None:
            continue
        names = {p.name for p in dependant.query_params}
        if {"lat", "lng"} & names and route.path not in ALLOWED:
            offenders.append(route.path)

    assert not offenders, (
        f"사용자 좌표를 받을 수 있는 경로가 추가됐다: {offenders}. "
        "관광지 좌표만 받는 경로라면 ALLOWED에 추가하고 근거를 남길 것."
    )


def test_pins_all_returns_list(client):
    """좌표 없이 전체 조회는 계속 동작해야 한다."""
    res = client.get("/pins/all")
    assert res.status_code == 200
    assert isinstance(res.json(), list)


def test_pins_all_result_structure(client):
    """반환된 핀에 필수 필드가 있어야 한다."""
    res = client.get("/pins/all")
    pins = res.json()
    if pins:
        pin = pins[0]
        for field in ("code_no", "title", "lat", "lng", "source_type"):
            assert field in pin, f"필드 누락: {field}"
