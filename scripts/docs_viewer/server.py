#!/usr/bin/env python3
"""놀멍봅서 문서 뷰어 — 로컬 전용 마크다운 열람 서버.

왜 이렇게 만들었나
------------------
- **미리 만들어두지 않는다.** 요청이 올 때마다 디스크에서 md를 읽는다.
  HTML을 미리 생성해두면 문서를 고친 뒤 옛날 내용을 보게 되는데,
  그 실패는 조용해서 알아채기 어렵다(틀린 마감일을 보고 안심하는 식).
  서버가 꺼지면 화면이 아예 안 뜨므로 실패가 시끄럽다. 그쪽이 안전하다.
- **표준 라이브러리만 쓴다.** `.venv`를 다시 만들거나 백엔드 의존성이
  바뀌어도 문서 뷰어는 안 깨져야 한다.
- **127.0.0.1에만 묶는다.** docs/ 안에 미공개 기획·공모전 전략이 있다.
  같은 와이파이의 다른 기기에서도 접근할 수 없다.

실행: python3 scripts/docs_viewer/server.py   (기본 포트 4321)
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

# scripts/docs_viewer/server.py → parents[1]=scripts, parents[2]=프로젝트 루트
# 절대경로를 박지 않는다. 폴더명이 탐라담 → 놀멍봅서로 바뀌어도 그대로 동작한다.
HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parents[1]
STATIC_DIR = HERE / "static"

# 열람 대상. 여기 없는 경로는 서버가 아예 읽지 않는다.
DOC_DIRS = ["docs"]
ROOT_FILES = ["CLAUDE.md"]

DEFAULT_PORT = 4321
SEARCH_MAX_HITS = 60
SEARCH_SNIPPET_CHARS = 90


# ─── 문서 수집 ────────────────────────────────────────────────────────────


def _iter_doc_paths():
    """열람 대상 md 파일의 절대경로를 훑는다. 호출할 때마다 디스크를 다시 읽는다."""
    for name in ROOT_FILES:
        path = PROJECT_ROOT / name
        if path.is_file():
            yield path
    for dirname in DOC_DIRS:
        base = PROJECT_ROOT / dirname
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.md")):
            if path.is_file():
                yield path


def _rel(path: Path) -> str:
    return path.relative_to(PROJECT_ROOT).as_posix()


def resolve_doc(rel_path: str) -> Path | None:
    """요청받은 상대경로를 실제 파일로 바꾼다.

    경로 조작(`../../.env` 같은 요청)을 막기 위해, 실제로 수집된 문서 목록에
    있는 경로만 통과시킨다. 화이트리스트 대조라 문자열 검사보다 확실하다.
    """
    wanted = rel_path.strip().lstrip("/")
    for path in _iter_doc_paths():
        if _rel(path) == wanted:
            return path
    return None


def build_tree() -> dict:
    """사이드바용 문서 목록. 폴더별로 묶고, 최근 수정 순 목록도 같이 준다."""
    groups: dict[str, list[dict]] = {}
    flat: list[dict] = []

    for path in _iter_doc_paths():
        rel = _rel(path)
        parent = str(Path(rel).parent)
        group = "루트" if parent == "." else parent
        try:
            mtime = path.stat().st_mtime
        except OSError:
            mtime = 0.0
        item = {
            "path": rel,
            "title": path.stem,
            "group": group,
            "mtime": mtime,
            "mtimeText": datetime.fromtimestamp(mtime).strftime("%m/%d %H:%M") if mtime else "",
        }
        groups.setdefault(group, []).append(item)
        flat.append(item)

    ordered = []
    # 루트(CLAUDE.md)를 맨 위에 두고, 나머지 폴더는 이름순.
    for group in sorted(groups, key=lambda g: (g != "루트", g)):
        ordered.append({"group": group, "items": groups[group]})

    recent = sorted(flat, key=lambda i: i["mtime"], reverse=True)[:5]
    return {"groups": ordered, "recent": recent, "count": len(flat)}


def search(query: str) -> list[dict]:
    """모든 문서를 그 자리에서 훑어 일치하는 줄을 돌려준다.

    문서가 수십 개 규모라 색인을 만들 이유가 없다. 색인은 최신화 문제를
    다시 불러들이므로 오히려 손해다.
    """
    needle = query.strip().lower()
    if len(needle) < 2:
        return []

    results: list[dict] = []
    for path in _iter_doc_paths():
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        rel = _rel(path)
        title_hit = needle in path.stem.lower()
        line_hits = []
        for lineno, line in enumerate(text.splitlines(), start=1):
            low = line.lower()
            pos = low.find(needle)
            if pos == -1:
                continue
            start = max(0, pos - SEARCH_SNIPPET_CHARS // 2)
            snippet = line[start : start + SEARCH_SNIPPET_CHARS].strip()
            line_hits.append({"line": lineno, "snippet": snippet})
            if len(line_hits) >= 3:
                break

        if title_hit or line_hits:
            results.append(
                {
                    "path": rel,
                    "title": path.stem,
                    "group": "루트" if str(Path(rel).parent) == "." else str(Path(rel).parent),
                    "titleHit": title_hit,
                    "hits": line_hits,
                    "hitCount": len(line_hits),
                }
            )
        if len(results) >= SEARCH_MAX_HITS:
            break

    # 제목이 걸린 문서를 위로.
    results.sort(key=lambda r: (not r["titleHit"], -r["hitCount"]))
    return results


# ─── HTTP ────────────────────────────────────────────────────────────────


class Handler(BaseHTTPRequestHandler):
    server_version = "NolmeongDocs/1.0"

    def log_message(self, fmt, *args):  # 콘솔을 조용하게 둔다
        pass

    def do_GET(self):
        parsed = urlparse(self.path)
        route = unquote(parsed.path)
        params = parse_qs(parsed.query)

        try:
            if route == "/" or route == "/index.html":
                self._send_static(STATIC_DIR / "index.html")
            elif route == "/api/tree":
                self._send_json(build_tree())
            elif route == "/api/doc":
                self._serve_doc(params.get("path", [""])[0])
            elif route == "/api/search":
                self._send_json({"results": search(params.get("q", [""])[0])})
            elif route.startswith("/static/"):
                self._serve_static(route[len("/static/") :])
            elif route == "/favicon.ico":
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
            else:
                self._send_error(HTTPStatus.NOT_FOUND, "없는 주소예요")
        except BrokenPipeError:
            pass  # 브라우저가 먼저 끊은 경우. 정상.
        except Exception as exc:  # noqa: BLE001 — 뷰어가 통째로 죽는 것보다 낫다
            self._send_error(HTTPStatus.INTERNAL_SERVER_ERROR, f"서버 오류: {exc}")

    # ── 개별 라우트 ──

    def _serve_doc(self, rel_path: str):
        path = resolve_doc(rel_path)
        if path is None:
            self._send_error(HTTPStatus.NOT_FOUND, "그런 문서가 없어요")
            return
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            self._send_error(HTTPStatus.INTERNAL_SERVER_ERROR, f"문서를 읽지 못했어요: {exc}")
            return
        stat = path.stat()
        self._send_json(
            {
                "path": _rel(path),
                "title": path.stem,
                "group": "루트" if str(Path(_rel(path)).parent) == "." else str(Path(_rel(path)).parent),
                "markdown": text,
                "mtimeText": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M"),
                "bytes": stat.st_size,
            }
        )

    def _serve_static(self, rel: str):
        target = (STATIC_DIR / rel).resolve()
        # static 폴더 밖으로 절대 나가지 않는다.
        if not str(target).startswith(str(STATIC_DIR.resolve()) + os.sep) or not target.is_file():
            self._send_error(HTTPStatus.NOT_FOUND, "없는 파일이에요")
            return
        self._send_static(target)

    # ── 응답 헬퍼 ──

    def _send_static(self, path: Path):
        if not path.is_file():
            self._send_error(HTTPStatus.NOT_FOUND, "없는 파일이에요")
            return
        ctype, _ = mimetypes.guess_type(path.name)
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype or "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        # 문서는 절대 캐시하지 않는다(최신성이 이 도구의 존재 이유).
        # 폰트·스크립트는 안 바뀌므로 캐시해도 된다.
        if path.suffix in {".woff2", ".js", ".css"}:
            self.send_header("Cache-Control", "public, max-age=604800")
        else:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, status: HTTPStatus, message: str):
        body = json.dumps({"error": message}, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    parser = argparse.ArgumentParser(description="놀멍봅서 문서 뷰어")
    parser.add_argument("--port", type=int, default=int(os.environ.get("DOCS_VIEWER_PORT", DEFAULT_PORT)))
    args = parser.parse_args()

    try:
        httpd = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError as exc:
        print(f"❌ 포트 {args.port}을(를) 열 수 없어요: {exc}", file=sys.stderr)
        print("   이미 뷰어가 켜져 있거나, 다른 프로그램이 그 번호를 쓰고 있어요.", file=sys.stderr)
        return 1

    count = sum(1 for _ in _iter_doc_paths())
    print(f"📖 놀멍봅서 문서 뷰어 — 문서 {count}개")
    print(f"   http://localhost:{args.port}")
    print("   종료: Ctrl+C")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 종료")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
