"""시안과 구현을 같은 폭으로 맞춰 나란히 붙인다.

## 왜 있나

시안을 손으로 옮기면 매번 어긋난다. 그런데 "비슷하다 / 전혀 다르다"를 눈대중으로
다투면 결론이 안 난다 — 2026-09-02 에 홈 화면에서 세 번 왕복했다.

원인은 두 가지였고 둘 다 **보면 바로 알 수 있는 것**이었다.

1. 클래스 이름을 믿고 크기를 넘겨짚었다. `text-body-sm` 은 Tailwind config 에
   **정의되지 않은 클래스**라 무시되고 기본 16px 로 렌더된다. 나는 14로 읽었다.
2. 커버 이미지가 실사라 인상의 대부분이 달랐는데, 그것을 "나머지가 비슷하니 괜찮다"로
   덮어 두었다.

겹쳐 놓고 보면 둘 다 5초 만에 보인다.

## 쓰는 법

    # 1) 시뮬레이터에서 현재 화면을 찍는다
    xcrun simctl io <UDID> screenshot 구현.png

    # 2) 시안과 나란히 붙인다
    .venv/bin/python3 scripts/compare_design.py 시안.png 구현.png -o 비교.png

    # 3) 비교.png 를 열어 본다

`--crop-top` 은 아이폰 상태바처럼 시안에 없는 부분을 잘라낸다(기본 120px).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow 가 필요하다: .venv/bin/pip install pillow")

GAP = 30
BG = (255, 255, 255)


def to_width(img: Image.Image, width: int) -> Image.Image:
    h = round(img.size[1] * width / img.size[0])
    return img.resize((width, h), Image.LANCZOS)


def main() -> None:
    ap = argparse.ArgumentParser(description="시안과 구현을 나란히 붙인다")
    ap.add_argument("design", help="시안 스크린샷")
    ap.add_argument("build", help="구현 스크린샷 (시뮬레이터)")
    ap.add_argument("-o", "--out", default="비교.png")
    ap.add_argument("--width", type=int, default=780, help="맞출 폭 (기본 780)")
    ap.add_argument("--crop-top", type=int, default=120,
                    help="구현에서 위를 잘라낸다 — 아이폰 상태바 (기본 120px)")
    ap.add_argument("--crop-bottom", type=int, default=40,
                    help="구현에서 아래를 잘라낸다 — 홈 인디케이터 (기본 40px)")
    args = ap.parse_args()

    d = Image.open(args.design).convert("RGB")
    b = Image.open(args.build).convert("RGB")

    if args.crop_top or args.crop_bottom:
        b = b.crop((0, args.crop_top, b.size[0], b.size[1] - args.crop_bottom))

    d, b = to_width(d, args.width), to_width(b, args.width)
    height = max(d.size[1], b.size[1])

    canvas = Image.new("RGB", (args.width * 2 + GAP, height), BG)
    canvas.paste(d, (0, 0))
    canvas.paste(b, (args.width + GAP, 0))
    canvas.save(args.out)

    print(f"왼쪽 시안 {d.size}  ·  오른쪽 구현 {b.size}")
    print(f"→ {Path(args.out).resolve()}")
    if abs(d.size[1] - b.size[1]) > height * 0.2:
        print("⚠️ 두 이미지의 세로 길이가 많이 다르다 — 한쪽이 스크롤 전체 캡처일 수 있다.")


if __name__ == "__main__":
    main()
