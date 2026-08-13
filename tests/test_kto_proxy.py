"""KTO 프록시 상수 — 공모전 자격 요건 관련.

이 테스트들은 버그를 잡기 위한 것이 아니다. **결정을 코드에 박아두기 위한 것**이다.
값을 바꾸려는 사람에게 "왜 이 값인지"를 보여주는 것이 목적이므로, 각 docstring에
근거를 남긴다.
"""
from routers import tourist, place


def test_cache_ttl_is_one_hour():
    """캐시 TTL이 1시간이어야 한다.

    7일 캐시는 성산 1개 장소 기준 개발 기간 전체에 호출 20여 건만 남긴다.
    공지 FAQ: "로컬 DB 저장 방식을 사용하여 개발 기간 내 API 호출 이력이
    확인되지 않을 경우 심사에서 불이익을 받을 수 있다."

    완전히 제거하지도 않는다 — 개발계정 한도가 오퍼레이션당 일 1,000건이라
    코스를 훑는 사용자 50명 수준에서 차단되고, 차단되면 place.py가 빈 필드로
    200을 반환해 에러 없이 정보가 사라진다.
    """
    assert tourist.CACHE_TTL == 3600
    assert place.CACHE_TTL == 3600


def test_mobile_app_uses_service_name():
    """KTO에 보내는 MobileApp 값이 현재 서비스명이어야 한다.

    심사 제출 서비스명과 일치해야 한다. 구명 JejuFolklore는 설화 데이터
    중심 시절의 이름이다.
    """
    assert tourist.MOBILE_APP == "Nolmeongbopseo"


def test_attribution_string_is_exact():
    """출처 표기는 공지가 지정한 문구만 허용된다.

    [O] 출처: ⓒ한국관광공사 · 출처: ⓒ한국관광콘텐츠랩
    [X] TourAPI 단독 표기, 공사 CI/BI 로고 이미지 (텍스트 표기만 허용)
    """
    assert tourist.KTO_ATTRIBUTION == "출처: ⓒ한국관광공사"
    assert "TourAPI" not in tourist.KTO_ATTRIBUTION


def test_kto_request_sends_service_name(monkeypatch):
    """_kto_get이 실제 요청에 MOBILE_APP 값을 넣어야 한다.

    상수만 바꾸고 사용처를 놓치는 실수를 막는다.
    """
    captured = {}

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def read(self):
            return b'{"response": {}}'

    def fake_urlopen(url, timeout=None):
        captured["url"] = url
        return FakeResponse()

    monkeypatch.setattr(tourist.urllib.request, "urlopen", fake_urlopen)
    tourist._kto_get("KorService2", "detailCommon2", {"contentId": "126435"})

    assert "MobileApp=Nolmeongbopseo" in captured["url"]
    assert "JejuFolklore" not in captured["url"]
