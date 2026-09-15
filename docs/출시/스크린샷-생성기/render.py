"""index.html 의 8장을 앱스토어 규격 PNG 로 찍는다.

    .venv/bin/python3 docs/출시/스크린샷-생성기/render.py

결과는 docs/출시/앱스토어_스크린샷/<규격>/ 에 쌓인다.
App Store Connect 는 투명도가 있는 PNG 를 거절하므로 마지막에 RGB 로 눌러 저장한다.
"""

import functools
import http.server
import io
import threading
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "앱스토어_스크린샷"

# 보여주신 App Store Connect 칸은 6.5인치(1284×2778). 6.9인치 칸이 따로 뜨면 그쪽을 쓴다.
SIZES = [
    ("6.5인치_1284x2778", 1284, 2778),
    ("6.9인치_1320x2868", 1320, 2868),
]


def serve() -> int:
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(HERE))
    handler.log_message = lambda *a, **k: None
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd.server_address[1]


def main() -> None:
    port = serve()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        for folder, w, h in SIZES:
            out = OUT / folder
            out.mkdir(parents=True, exist_ok=True)
            page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
            page.goto(f"http://127.0.0.1:{port}/index.html?export&w={w}&h={h}")
            page.evaluate("document.fonts.ready")
            page.wait_for_function(
                "[...document.images].every(i => i.complete && i.naturalWidth > 0)"
            )
            for el in page.query_selector_all(".slide"):
                slide_id = el.get_attribute("data-id")
                png = el.screenshot(type="png")
                im = Image.open(io.BytesIO(png)).convert("RGB")
                assert im.size == (w, h), (slide_id, im.size)
                im.save(out / f"{slide_id}.png")
                print(folder, slide_id, im.size)
            page.close()
        browser.close()


if __name__ == "__main__":
    main()
