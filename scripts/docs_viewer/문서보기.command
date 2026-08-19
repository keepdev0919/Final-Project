#!/usr/bin/env bash
# 더블클릭하면 문서 뷰어가 열린다.
#
# - 뷰어가 꺼져 있으면 켜고, 이미 켜져 있으면 그냥 브라우저만 연다.
# - 그래서 몇 번을 눌러도 안전하다.
# - 문서는 열 때마다 디스크에서 새로 읽으므로 항상 최신이다.
set -uo pipefail

PORT="${DOCS_VIEWER_PORT:-4321}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SERVER="$HERE/server.py"
LOG="$HOME/Library/Logs/nolmeong-docs-viewer.log"
URL="http://localhost:$PORT"

mkdir -p "$HOME/Library/Logs"

if curl -sf -o /dev/null "$URL/api/tree"; then
  echo "📖 문서 뷰어가 이미 켜져 있습니다."
else
  echo "📖 문서 뷰어를 켭니다…"
  nohup /usr/bin/python3 "$SERVER" --port "$PORT" >> "$LOG" 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.3
    curl -sf -o /dev/null "$URL/api/tree" && break
  done
fi

if curl -sf -o /dev/null "$URL/api/tree"; then
  open "$URL"
  echo "✅ $URL"
  echo "   이 창은 닫아도 됩니다."
else
  echo "❌ 켜지 못했습니다. 기록을 보세요: $LOG"
  echo ""
  tail -5 "$LOG"
  echo ""
  read -r -p "엔터를 누르면 닫힙니다 "
fi
