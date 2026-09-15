"""PixelIcon.swift 의 Material Icons 글리프를 SVG path 로 뽑아 src/ui/iconPaths.ts 를 만든다.

왜 폰트가 아니라 SVG 인가
    iOS 는 `MaterialIcons-Regular.ttf` 를 글자로 찍는다. 웹에서 똑같이 하면
    ① 앱인토스 하드 규칙(꺾쇠·화살표는 텍스트 글리프 대신 SVG)에 걸리고
    ② 350KB 폰트가 오기 전까지 아이콘 자리가 비거나 네모로 보인다.
    같은 폰트에서 **같은 모양을 path 로** 꺼내 쓰면 둘 다 풀린다.

정본은 여전히 Swift 다 — 이름·코드포인트는 PixelIcon.swift 에서 읽는다.
아이콘을 추가하려면 Swift 에 case 를 넣고 이 스크립트를 다시 돌린다.

    python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools
    /tmp/ft/bin/python scripts/gen-icon-paths.py

Material Icons 는 Apache License 2.0 (Google).
"""
from __future__ import annotations

import pathlib
import re

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent  # nolmeongbopseo/
IOS = ROOT.parent / "ios" / "JejuFolklore"
SWIFT = IOS / "Sources" / "Views" / "DesignSystem" / "PixelIcon.swift"
TTF = IOS / "Resources" / "Fonts" / "MaterialIcons-Regular.ttf"
OUT = ROOT / "src" / "ui" / "iconPaths.ts"

CASE = re.compile(r'case \.([a-zA-Z]+):\s+return "\\u\{([0-9a-f]+)\}"\s+//\s*([a-z_]+)')


def main() -> None:
    glyphs = CASE.findall(SWIFT.read_text(encoding="utf-8"))
    font = TTFont(str(TTF))
    upm = font["head"].unitsPerEm
    ascent = font["hhea"].ascent
    cmap = font.getBestCmap()
    gs = font.getGlyphSet()

    lines = [
        "// ⚠️ 자동 생성 파일 — 직접 고치지 말 것. scripts/gen-icon-paths.py 로 다시 만든다.",
        "// 원본: ios/JejuFolklore/Sources/Views/DesignSystem/PixelIcon.swift 의 코드포인트,",
        "//       ios/JejuFolklore/Resources/Fonts/MaterialIcons-Regular.ttf 의 글리프 윤곽.",
        "// Material Icons © Google, Apache License 2.0.",
        "",
        f"/** 글리프 좌표계. Material Icons 는 em {upm} 이고 기준선 위로 {ascent} 까지 그린다. */",
        f"export const ICON_VIEWBOX = '0 0 {upm} {upm}';",
        "",
        "export const ICON_PATHS = {",
    ]
    for name, cp, material in glyphs:
        gname = cmap[int(cp, 16)]
        pen = SVGPathPen(gs)
        # 폰트는 y 가 위로 자란다. SVG 는 아래로 자란다 — 뒤집고 ascent 만큼 내린다.
        gs[gname].draw(TransformPen(pen, (1, 0, 0, -1, 0, ascent)))
        d = pen.getCommands()
        lines.append(f"  /** {material} (U+{cp.upper()}) */")
        lines.append(f"  {name}: '{d}',")
    lines.append("} as const;")
    lines.append("")
    lines.append("export type IconName = keyof typeof ICON_PATHS;")
    lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(glyphs)} glyphs → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
