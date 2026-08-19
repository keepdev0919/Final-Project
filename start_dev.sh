#!/usr/bin/env bash
# 새 장소에서 개발 시작할 때 실행: ./start_dev.sh
set -e

CONFIG="ios/JejuFolklore/Sources/App/Config.swift"

# ── 1. 현재 IP 감지 ──────────────────────────────────────────
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")

if [ -z "$IP" ]; then
  echo "❌ WiFi IP를 찾을 수 없습니다. WiFi에 연결되어 있는지 확인하세요."
  exit 1
fi

echo "📡 감지된 IP: $IP"

# ── 2. Config.swift URL 교체 ────────────────────────────────
# http://로 시작하고 :8000으로 끝나는 패턴을 교체
sed -i '' "s|http://[0-9.]*:8000|http://$IP:8000|g" "$CONFIG"

echo "✅ Config.swift 업데이트 완료 → http://$IP:8000"

# ── 3. 백엔드 서버 실행 ─────────────────────────────────────
echo ""
echo "🚀 FastAPI 서버 시작 중..."
echo "   Xcode에서 빌드 후 앱 실행하세요"
echo "   종료: Ctrl+C"
echo "──────────────────────────────────────────"

cd "$(dirname "$0")"

# ⚠️ `source .venv/bin/activate` 를 쓰지 않는다.
# 이 가상환경은 만들 당시 경로(keepdev/overedge/탐라담)가 안에 박혀 있어
# 폴더명이 바뀐 뒤로 activate가 깨졌다. 실행파일 셔뱅도 48개 중 44개가 깨져
# `uvicorn` 을 직접 부를 수도 없다(bad interpreter).
#
# `python3 -m` 으로 부르면 셔뱅을 타지 않으므로 지금도 되고, 나중에
# 가상환경을 다시 만든 뒤에도 그대로 된다. → CLAUDE.md "남은 뒷정리" 참조
PY="$(pwd)/.venv/bin/python3"
if [ ! -x "$PY" ]; then
  echo "❌ 가상환경을 찾을 수 없습니다: $PY"
  echo "   만들기: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

cd backend
exec "$PY" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
