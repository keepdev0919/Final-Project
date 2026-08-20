"""팔레트의 명도 대비를 못 박는다.

색은 틀려도 앱이 죽지 않는다. 조용히 안 읽히게만 된다. 그래서 테스트로 잡는다.

## 겪은 사고 두 건

1. **2026-08-14** — 다크 모드에서 강조색 위에 잉크를 올려 **1.26:1**. 글자가 사라졌다.
   "밝은 배경 위 글자는 어두운색으로 고정"으로 해결했다.
2. **2026-08-20** — 시안 색으로 갈아타면서 그 해법이 깨졌다. 새 팔레트는
   라이트 `primary`(#006D39)가 **어두운** 초록, 다크 `primary`(#38CC77)가 **밝은** 초록이라
   글자색이 모드마다 반대여야 한다. 고정색 하나로는 한쪽이 반드시 깨진다.

그래서 지금은 **채움색마다 짝이 되는 글자색**(`onPrimary` 등)을 두고,
**두 모드 모두** 검사한다.

## 기준

- 본문·보조 텍스트: WCAG AA **4.5:1**
- 배지·버튼 글자: 14pt 굵은 글자이므로 large text 기준 **3:1**
"""
import re
from pathlib import Path

import pytest

PALETTE = (Path(__file__).parent.parent
           / "ios/JejuFolklore/Sources/Views/DesignSystem/PixelColor.swift")

BODY_MIN = 4.5
LABEL_MIN = 3.0

# 채움색 ↔ 그 위에 올리는 글자색 짝. 이 짝이 깨지면 글자가 사라진다.
PAIRS = [("primary", "onPrimary"), ("accent", "onAccent"),
         ("done", "onDone"), ("locked", "onLocked")]


def _lum(v: int) -> float:
    def ch(c: int) -> float:
        s = c / 255
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a: int, b: int) -> float:
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _parse() -> tuple[dict[str, int], dict[str, int]]:
    """`adaptive(light: 0xRRGGBB, dark: 0xRRGGBB)` 를 코드에서 읽는다.

    문서가 아니라 코드를 읽는다. 실제로 화면에 나가는 값이 코드이기 때문이다.
    """
    src = PALETTE.read_text(encoding="utf-8")
    pat = re.compile(r"static let (\w+)\s*=\s*adaptive\(light:\s*0x([0-9A-Fa-f]{6}),"
                     r"\s*dark:\s*0x([0-9A-Fa-f]{6})\)")
    light: dict[str, int] = {}
    dark: dict[str, int] = {}
    for name, l, d in pat.findall(src):
        light[name] = int(l, 16)
        dark[name] = int(d, 16)
    assert light, f"{PALETTE} 에서 팔레트를 찾지 못했다"
    return light, dark


def test_palette_matches_design_doc():
    """코드의 팔레트가 DESIGN.md §2에 적힌 값과 같아야 한다.

    라이트 값은 Stitch 시안 CSS에서 그대로 가져온 것이다. 시안이 라이트 전용이라
    다크는 같은 색조로 파생시켰다.
    """
    light, dark = _parse()
    assert light == {
        "background": 0xFBF8FF, "surface": 0xFFFFFF, "sunk": 0xEDECFF,
        "ink": 0x181A2A, "inkWeak": 0x3D4A3F,
        "primary": 0x006D39, "accent": 0xD9AF00, "done": 0x38CC77, "locked": 0xBA1A1A,
        "onPrimary": 0xFFFFFF, "onAccent": 0x181A2A,
        "onDone": 0x181A2A, "onLocked": 0xFFFFFF,
    }
    assert dark == {
        "background": 0x12141F, "surface": 0x22243A, "sunk": 0x1B1D2E,
        "ink": 0xF0EFFF, "inkWeak": 0x9EA8A0,
        "primary": 0x38CC77, "accent": 0xEEC215, "done": 0x70FDA2, "locked": 0xFFB4AB,
        "onPrimary": 0x181A2A, "onAccent": 0x181A2A,
        "onDone": 0x181A2A, "onLocked": 0x181A2A,
    }


@pytest.mark.parametrize("mode", [0, 1], ids=["light", "dark"])
@pytest.mark.parametrize("fg,bg", [("ink", "background"), ("ink", "surface"),
                                   ("inkWeak", "background"), ("inkWeak", "surface"),
                                   ("inkWeak", "sunk")])
def test_text_meets_aa(mode, fg, bg):
    """본문·보조 텍스트는 배경 대비 4.5:1 이상이어야 한다."""
    p = _parse()[mode]
    r = contrast(p[fg], p[bg])
    assert r >= BODY_MIN, f"{fg} on {bg} = {r:.2f}:1 (기준 {BODY_MIN})"


@pytest.mark.parametrize("mode", [0, 1], ids=["light", "dark"])
@pytest.mark.parametrize("fill,on", PAIRS)
def test_fill_and_its_text_are_legible(mode, fill, on):
    """채움색과 그 짝 글자색이 두 모드 모두에서 읽혀야 한다.

    여기가 2026-08-14(1.26:1)와 2026-08-20(모드별 반전) 사고를 함께 막는 자리다.
    """
    p = _parse()[mode]
    r = contrast(p[fill], p[on])
    assert r >= LABEL_MIN, f"{on} on {fill} = {r:.2f}:1 (기준 {LABEL_MIN})"


@pytest.mark.parametrize("fill,on", PAIRS)
def test_paired_text_is_the_better_of_black_or_white(fill, on):
    """짝 글자색이 흰색·검정 중 대비가 높은 쪽이어야 한다.

    반대를 골라도 3:1은 넘길 수 있다. 그러면 '읽히긴 하는데 눈이 아픈' 상태로
    굳는다. 더 나은 쪽을 고르게 강제한다.
    """
    for mode, name in ((0, "라이트"), (1, "다크")):
        p = _parse()[mode]
        chosen = contrast(p[fill], p[on])
        best = max(contrast(p[fill], 0xFFFFFF), contrast(p[fill], 0x181A2A))
        assert chosen >= best - 0.01, (
            f"{name}: {on} on {fill} = {chosen:.2f}:1 이지만 "
            f"반대 색이면 {best:.2f}:1 이다"
        )
