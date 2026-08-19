"""KTO OpenAPI를 부르는 방식이 조용히 망가지지 않게 고정한다.

2026-08-19에 두 개의 고장을 발견했다. 둘 다 **에러가 안 뜨는 종류**였다.

1. `detailCommon2`에 KorService1 파라미터(`defaultYN`·`overviewYN`)를 보내
   호출이 통째로 실패하고 있었다. 그런데 실패해도 빈 값으로 200을 반환해서
   화면에는 "설명이 원래 없는 장소"처럼 보였다.
2. `detailIntro2`에서 운영시간을 `opentime`으로 찾는데, 관광지(12)의 실제 칸은
   `usetime`이다. 그래서 관광지 운영시간이 항상 비어 있었다.

두 고장 모두 화면만 봐서는 못 잡는다. 그래서 테스트로 잡는다.
"""

import io
import json
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "backend"))

from routers import place, tourist  # noqa: E402

PLACE_SRC = (PROJECT_ROOT / "backend" / "routers" / "place.py").read_text(encoding="utf-8")
TOURIST_SRC = (PROJECT_ROOT / "backend" / "routers" / "tourist.py").read_text(encoding="utf-8")


# ── ① KorService1 파라미터를 섞어 보내지 않는다 ──────────────────────────

@pytest.mark.parametrize("param", ["defaultYN", "overviewYN", "addrinfoYN"])
def test_korservice1_params_are_never_sent(param):
    """KorService2는 이 파라미터들을 거부한다 — 하나라도 있으면 호출 전체가 실패한다.

    `INVALID_REQUEST_PARAMETER_ERROR(defaultYN)`이 뜨고 응답에 body가 없다.
    KorService1에서 쓰던 것이라 참고 자료·예전 코드에서 다시 딸려 들어오기 쉽다.
    """
    assert f'"{param}"' not in PLACE_SRC, f"place.py가 {param}을 보낸다"
    assert f'"{param}"' not in TOURIST_SRC, f"tourist.py가 {param}을 보낸다"


# ── ② 장소 종류별 칸 이름을 실제 응답 기준으로 고정 ──────────────────────

# 2026-08-19 실호출로 확인한 칸 이름. 종류마다 다르다.
INTRO_SAMPLES = {
    "12 관광지":  {"usetime": "06:00~18:00", "restdate": "첫째 주 월요일",
                  "parking": "가능", "infocenter": "064-783-0959"},
    "14 문화시설": {"usetimeculture": "09:00~18:00", "restdateculture": "월요일",
                  "parkingculture": "가능", "infocenterculture": "064-1234",
                  "usefee": "무료", "parkingfee": "2000원"},
    "15 축제행사": {"usetimefestival": "10:00~17:00", "sponsor1tel": "064-2222"},
    "32 숙박":    {"checkintime": "15:00", "parkinglodging": "가능",
                  "infocenterlodging": "064-3333"},
    "38 쇼핑":    {"opentime": "08:00~20:00", "restdateshopping": "연중무휴",
                  "parkingshopping": "가능", "infocentershopping": "064-4444"},
    "39 음식점":  {"opentimefood": "11:00~22:30", "restdatefood": "연중무휴",
                  "parkingfood": "가능", "infocenterfood": "064-757-8182"},
}


@pytest.mark.parametrize("label,item", INTRO_SAMPLES.items())
def test_intro_fields_are_found_for_every_place_type(label, item):
    """어떤 종류든 운영시간·전화는 뽑아낼 수 있어야 한다.

    종류별로 칸 이름을 하나하나 적는 방식이었을 때, 새 종류가 등장하면
    아무도 모르게 빈 값이 됐다. 지금은 앞부분이 같은 칸을 찾는 방식이다.
    이 테스트는 그 방식이 실제 칸 이름들을 전부 덮는지 확인한다.
    """
    assert place._pick(item, place._INTRO_FIELDS["open_time"]), f"{label}: 운영시간을 못 찾음"
    assert place._pick(item, place._INTRO_FIELDS["tel"]), f"{label}: 전화번호를 못 찾음"


def test_parking_fee_is_not_mistaken_for_parking_availability():
    """`parkingfee`(주차 요금)를 `parking`(주차 가능 여부)으로 읽지 않는다.

    앞부분 일치 방식의 유일한 함정이다. "2000원"이 주차 가능 여부 자리에 뜨면
    화면에 "주차: 2000원"이라고 나온다.
    """
    assert place._pick({"parkingfee": "2000원"}, place._INTRO_FIELDS["parking"]) == ""
    assert place._pick({"parkingfee": "2000원", "parkingculture": "가능"},
                       place._INTRO_FIELDS["parking"]) == "가능"


# ── ③ KTO의 실패를 조용히 넘기지 않는다 ─────────────────────────────────

class _FakeResponse(io.BytesIO):
    """urlopen이 돌려주는 것처럼 with 문에 쓸 수 있는 가짜 응답."""

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def _stub_kto(monkeypatch, payload: dict) -> None:
    body = json.dumps(payload).encode()
    monkeypatch.setattr(tourist.urllib.request, "urlopen",
                        lambda url, timeout=None: _FakeResponse(body))


def test_kto_error_response_raises(monkeypatch):
    """KTO는 실패도 HTTP 200으로 돌려준다. 본문 resultCode를 봐야 안다.

    이걸 검사하지 않으면 파라미터 오류·한도 초과·키 만료가 전부
    "정보가 없는 장소"로 보인다. 심사 기간에 한도를 넘기면 심사위원은
    고장이 아니라 원래 그런 앱을 보게 된다.
    """
    _stub_kto(monkeypatch, {"resultCode": "10",
                            "resultMsg": "INVALID_REQUEST_PARAMETER_ERROR(defaultYN)"})
    with pytest.raises(tourist.KtoApiError):
        tourist._kto_get("KorService2", "detailCommon2", {"contentId": "126435"})


def test_successful_response_passes_through(monkeypatch):
    """정상 응답(resultCode 0000)은 그대로 통과해야 한다."""
    _stub_kto(monkeypatch, {"response": {
        "header": {"resultCode": "0000", "resultMsg": "OK"},
        "body": {"items": {"item": [{"contentid": "126435"}]}}}})
    out = tourist._kto_get("KorService2", "detailCommon2", {"contentId": "126435"})
    assert out["response"]["body"]["items"]["item"][0]["contentid"] == "126435"


# ── ④ 호출 이력을 센다 ──────────────────────────────────────────────────

def test_every_call_is_logged():
    """호출 한 건마다 기록을 남긴다.

    공지: "개발 기간 내 API 호출 이력이 확인되지 않을 경우 심사에서 불이익."
    캐시 TTL을 얼마로 둘지는 추측이 아니라 이 기록과 공공데이터포털 수치를
    대조해서 정한다. 계측이 없으면 조정도 없다.
    """
    assert "_log_call" in TOURIST_SRC
    assert "kto_call_log" in (PROJECT_ROOT / "backend" / "services" / "db.py").read_text(encoding="utf-8")
    # 성공·실패 양쪽 경로에서 모두 기록해야 한다
    assert TOURIST_SRC.count("_log_call(service, operation") >= 3
