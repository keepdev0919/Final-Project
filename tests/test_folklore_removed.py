"""설화 기능 제거 + 위치 전송 불변식.

설화는 2026-08-13에 코스 추천 기준에서 분리했고, 2026-08-14에 조회·LLM
엔드포인트까지 걷어냈다. 근거(설계 문서 §5): ① 장소에 강하게 얽힌 설화가
실제로 거의 없고 ② 파일 데이터라 공모전 데이터 활용 점수에 기여하지 않으며
(공지 FAQ: "OpenAPI 형태만 인정") ③ 무료 기능이 설화 취향을 묻는데 유료
콘텐츠는 설화가 아니라 앞뒤가 안 맞았다.

되살릴 일이 있으면 이 파일을 먼저 지우면서 "왜 되살리는지"를 남길 것.
데이터 파일(data/extracted, storage/vector_db)은 지우지 않았으므로 복구는 가능하다.
"""


def test_pins_router_gone(client):
    """설화 핀 조회가 없어야 한다."""
    assert client.get("/pins/all").status_code == 404


def test_no_pins_prefixed_route(client):
    """경로 하나만 막으면 /pins/search 같은 다른 이름으로 부활한다. 접두사 전체를 막는다."""
    from main import app

    offenders = [r.path for r in app.routes if getattr(r, "path", "").startswith("/pins")]
    assert not offenders, f"/pins 라우트가 남아 있다: {offenders}"


def test_today_folklore_endpoint_gone(client):
    """'오늘의 설화'는 홈에서 성산 카드에 자리를 내줬다."""
    assert client.get("/home/today").status_code == 404


def test_course_response_has_no_folklore_fields():
    """코스 응답에 설화 잔재 필드가 없어야 한다.

    folklore_pins·narrative는 2026-08-13에 '스키마 호환용'으로 남겨뒀던 것이다.
    호환 대상이던 구 클라이언트가 없어졌으므로 제거한다.
    """
    from models.schemas import Course, CoursePlace

    assert "folklore_pins" not in CoursePlace.model_fields
    assert "narrative" not in Course.model_fields


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

    # ⚠️ 이 검사는 app.routes를 훑는다. FastAPI 0.141부터 include_router가
    # 라우트를 펼치지 않고 감싸므로, 그 버전에서는 훑어도 **아무것도 안 나온다.**
    # 그러면 위반이 있어도 "통과"가 되어 감시가 조용히 꺼진다.
    # 그래서 먼저 "볼 수 있는 상태인가"를 확인한다.
    inspectable = [r for r in app.routes if getattr(r, "dependant", None) is not None]
    assert len(inspectable) >= 10, (
        f"라우트를 {len(inspectable)}개밖에 못 봤다. FastAPI 구조가 바뀌어 "
        "이 검사가 무력화됐을 가능성이 크다. 통과로 넘기면 안 된다."
    )

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
        "위치 판정은 단말에서만 한다."
    )


def test_home_recommendations_carry_full_course_fields(client):
    """홈 추천 코스가 iOS `Course` 모델이 요구하는 필드를 모두 담아야 한다.

    iOS `Course`는 `estimatedMinutes`·`sourceCourseId`를 비옵셔널로 선언한다.
    Swift의 합성 Codable은 이 키가 없으면 **디코딩 전체를 실패**시키는데,
    호출부가 `try?`로 감싸고 있어 예외가 삼켜지고 목록이 조용히 빈다.
    실제로 홈의 "추천 코스" 섹션이 계속 비어 있었다(2026-08-14 발견).

    화면이 멀쩡히 뜨면서 내용만 사라지는 종류의 고장이라 테스트로 잡는다.
    """
    from unittest.mock import patch
    from models.schemas import CourseListItem, CoursePlace

    with patch("routers.home.list_courses") as mock_list:
        mock_list.return_value = [
            CourseListItem(
                id="c1", title="테스트 코스", duration_days=2,
                places=[CoursePlace(name="성산일출봉", lat=33.4, lng=126.9, day=1)],
            )
        ]
        body = client.get("/home/recommendations").json()

    assert body["courses"], "추천 코스가 비었다"
    for course in body["courses"]:
        for required in ("id", "title", "duration_days", "places",
                         "estimated_minutes", "source_course_id"):
            assert required in course, f"'{required}' 누락 — iOS 디코딩이 통째로 실패한다"
