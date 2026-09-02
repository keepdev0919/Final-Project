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
# 테두리·아이콘 같은 비텍스트 요소는 WCAG 1.4.11에 따라 3:1이다.
NONTEXT_MIN = 3.0
LABEL_MIN = 3.0

# 채움색 ↔ 그 위에 올리는 글자색 짝. 이 짝이 깨지면 글자가 사라진다.
PAIRS = [
    ("primary", "onPrimary"),
    ("primaryContainer", "onPrimaryContainer"),
    ("secondary", "onSecondary"),
    ("secondaryContainer", "onSecondaryContainer"),
    ("tertiary", "onTertiary"),
    ("tertiaryContainer", "onTertiaryContainer"),
    ("tertiaryFixed", "onTertiaryFixed"),
    ("error", "onError"),
]


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
    """코드의 팔레트가 정해진 팔레트와 같아야 한다.

    라이트 값은 Stitch 시안 CSS에서 그대로 가져온 것이다. 시안이 라이트 전용이라
    다크는 같은 색조로 파생시켰다.
    """
    light, dark = _parse()
    assert light == {
        "background": 0xFBF8FF, "surface": 0xFFFFFF, "surfaceLow": 0xF4F2FF,
        "surfaceMid": 0xEDECFF, "surfaceHigh": 0xE6E6FD, "surfaceVariant": 0xE1E1F7,
        "surfaceDim": 0xD8D8EF,
        "ink": 0x181A2A, "inkWeak": 0x3D4A3F,
        "outline": 0x6D7B6E, "outlineVariant": 0xBCCABC,
        "primary": 0x006D39, "onPrimary": 0xFFFFFF,
        "primaryContainer": 0x38CC77, "onPrimaryContainer": 0x005129,
        "secondary": 0x0062A2, "onSecondary": 0xFFFFFF,
        "secondaryContainer": 0x54ABFD, "onSecondaryContainer": 0x003E69,
        "tertiary": 0x735C00, "onTertiary": 0xFFFFFF,
        "tertiaryContainer": 0xD9AF00, "onTertiaryContainer": 0x554400,
        "tertiaryFixed": 0xFFE085, "onTertiaryFixed": 0x231B00,
        "error": 0xBA1A1A, "onError": 0xFFFFFF,
    }
    assert dark == {
        "background": 0x12141F, "surface": 0x22243A, "surfaceLow": 0x1B1D2E,
        "surfaceMid": 0x282B44, "surfaceHigh": 0x30334E, "surfaceVariant": 0x3A3D58,
        "surfaceDim": 0x0D0F18,
        "ink": 0xF0EFFF, "inkWeak": 0x9EA8A0,
        "outline": 0x8A9A8B, "outlineVariant": 0x4A5A4B,
        "primary": 0x51E088, "onPrimary": 0x00210D,
        "primaryContainer": 0x005229, "onPrimaryContainer": 0x70FDA2,
        "secondary": 0x9DCAFF, "onSecondary": 0x001D35,
        "secondaryContainer": 0x00497C, "onSecondaryContainer": 0xD1E4FF,
        "tertiary": 0xEEC215, "onTertiary": 0x231B00,
        "tertiaryContainer": 0x574500, "onTertiaryContainer": 0xFFE085,
        "tertiaryFixed": 0xFFE085, "onTertiaryFixed": 0x231B00,
        "error": 0xFFB4AB, "onError": 0x93000A,
    }


@pytest.mark.parametrize("mode", [0, 1], ids=["light", "dark"])
@pytest.mark.parametrize("fg,bg", [("ink", "background"), ("ink", "surface"),
                                   ("ink", "surfaceMid"), ("ink", "surfaceVariant"),
                                   ("inkWeak", "background"), ("inkWeak", "surface"),
                                   ("inkWeak", "surfaceMid")])
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

    ⚠️ 한때 "짝 색은 흰색·검정 중 대비가 높은 쪽이어야 한다"는 검사를 뒀다가 지웠다.
    그 규칙은 역할마다 색이 두 개뿐이던 시절엔 맞았지만, 시안의 Material 팔레트는
    `on*` 색을 **일부러 색조에 맞춰** 둔다(`onPrimaryContainer`는 순수 검정이 아니라
    진한 초록 #005129). 그 규칙을 강제하면 시안 색을 바꿔야 하므로, "시안과 똑같이"
    라는 목적과 정면으로 어긋난다. 대비 하한(3:1)만 지킨다.
    """
    p = _parse()[mode]
    r = contrast(p[fill], p[on])
    assert r >= LABEL_MIN, f"{on} on {fill} = {r:.2f}:1 (기준 {LABEL_MIN})"


@pytest.mark.parametrize("mode", [0, 1], ids=["light", "dark"])
@pytest.mark.parametrize("line,bg", [("outline", "surface"), ("outline", "background")])
def test_lines_meet_nontext_contrast(line, bg, mode):
    """테두리·구분선은 3:1이면 된다 (WCAG 1.4.11 비텍스트 대비).

    본문 기준 4.5:1을 적용하면 라이트 `outline`(#6D7B6E)이 4.46으로 걸린다.
    그런데 이건 글자가 아니라 선이다. 기준을 잘못 적용해서 시안 색을 억지로
    바꾸면, 맞추려던 것에서 오히려 멀어진다.
    """
    p = _parse()[mode]
    r = contrast(p[line], p[bg])
    assert r >= NONTEXT_MIN, f"{line} on {bg} = {r:.2f}:1 (기준 {NONTEXT_MIN})"


def test_semantic_aliases_point_at_real_roles():
    """의미 별칭(accent·done·locked 등)은 Material 역할을 가리키는 것이어야 한다.

    별칭이 직접 색을 들고 있으면 팔레트가 두 곳에 생기고, 한쪽만 바뀐다.
    """
    src = PALETTE.read_text(encoding="utf-8")
    for alias in ("sunk", "accent", "onAccent", "done", "onDone", "locked", "onLocked"):
        m = re.search(rf"static let {alias}\s*=\s*(\w+)", src)
        assert m, f"{alias} 별칭을 찾지 못했다"
        assert not m.group(1).startswith("adaptive"), (
            f"{alias}가 색을 직접 들고 있다 — Material 역할을 가리켜야 한다"
        )
