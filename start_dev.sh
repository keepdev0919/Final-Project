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
source .venv/bin/activate
cd backend
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
