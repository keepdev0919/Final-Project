"""인기 상위 장소의 TTS 캐시를 미리 채운다.

    .venv/bin/python backend/scripts/warm_tts_cache.py           # 목록대로
    .venv/bin/python backend/scripts/warm_tts_cache.py --dry-run # 비용만 계산
    .venv/bin/python backend/scripts/warm_tts_cache.py --force   # 캐시 있어도 다시

## 왜 미리 채우나

첫 생성이 **20초** 걸린다(1,039자 실측). 캐시 히트는 0.0초다. 사용자가 20초를
기다리는 경로를 남길 수 없다. 그래서 데모·심사 전에 미리 만들어 둔다.

## 왜 몇 곳만인가 (2026-08-20 조익준님 결정)

189곳을 다 만들 필요가 없다. 데모와 심사에서 보여줄 것만 있으면 된다.
**기본 상위 3곳**이고 `--limit`으로 늘린다.

대상은 `data/tts_warm_targets.json`이고 **비짓제주 코스 9,134개의 등장 빈도**로
순위를 매겼다(공항·카페 등 제외). stid를 손으로 바꾸면 그대로 따라간다.

## 주의

- 무료 플랜은 월 15,000 크레딧이다. 10곳 전체가 약 9,800이라 목소리를 바꿔
  다시 만들면 한 달 안에 두 번은 안 된다. **그래서 기본을 3곳으로 뒀다.**
- 무료 플랜 동시 호출 2. 순차로 돌린다.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

BASE = Path(__file__).parent.parent.parent
sys.path.insert(0, str(BASE / "backend"))

TARGETS = BASE / "data" / "tts_warm_targets.json"
CHARS_PER_SEC = 6.4  # 실측 (성산 1,039자 / 187초 등 5건 평균)


def _load_env() -> None:
    env = BASE / ".env"
    if not env.exists():
        return
    for line in env.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="비용만 계산하고 만들지 않는다")
    ap.add_argument("--force", action="store_true", help="캐시가 있어도 다시 만든다")
    ap.add_argument("--limit", type=int, default=3,
                    help="상위 몇 곳만 만들 것인가 (기본 3 — 2026-08-20 결정)")
    ap.add_argument("--emotion", default="normal")
    ap.add_argument("--lang", default="ko", choices=["ko", "en"])
    args = ap.parse_args()

    _load_env()
    from routers.odii import fetch_story
    from services import typecast
    from services.db import get_db_connection

    places = json.loads(TARGETS.read_text(encoding="utf-8"))[: args.limit]
    est_chars = sum(p["play_time"] for p in places) * CHARS_PER_SEC
    print(f"대상 {len(places)}곳 · 예상 {est_chars:,.0f} 크레딧 "
          f"(무료 플랜 월 15,000 / 라이트 월 200,000)\n")
    if args.dry_run:
        for p in places:
            print(f"  {p['rank']:2}. {p['odii_title'][:28]:30} {p['play_time']:>4}초 "
                  f"≈ {p['play_time']*CHARS_PER_SEC:>6,.0f} 크레딧")
        return 0

    tc_lang = {"ko": "kor", "en": "eng"}[args.lang]
    conn = get_db_connection()
    made = hit = fail = 0
    used = 0

    for p in places:
        label = f"{p['rank']:2}. {p['odii_title'][:26]:28}"
        try:
            # 대본은 오디에서 실시간으로 받는다 — 저장하지 않는다(설계 v2 §2).
            story = fetch_story(str(p["stid"]), args.lang)
            script = (story.get("script") or "").strip()
            if not script:
                print(f"{label} ⚠️  대본 없음 — 건너뜀")
                fail += 1
                continue

            if args.force:
                key = typecast.cache_key(script, emotion=args.emotion, lang=tc_lang)
                typecast._path_for(key).unlink(missing_ok=True)

            t0 = time.time()
            audio, from_cache = typecast.synth(
                script, emotion=args.emotion, lang=tc_lang, conn=conn
            )
            dt = time.time() - t0
            if from_cache:
                hit += 1
                print(f"{label} ✓ 캐시 ({len(audio)/1024:,.0f}KB)")
            else:
                made += 1
                used += len(script)
                print(f"{label} ✅ 생성 {dt:4.1f}초 · {len(script):,}자 ({len(audio)/1024:,.0f}KB)")
        except Exception as e:  # noqa: BLE001
            fail += 1
            print(f"{label} ❌ {type(e).__name__}: {str(e)[:90]}")
        time.sleep(0.5)  # 무료 플랜 동시 호출 2 — 순차로 돈다

    print(f"\n생성 {made} · 캐시 {hit} · 실패 {fail}")
    print(f"쓴 크레딧 약 {used:,}자")
    return 1 if fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
