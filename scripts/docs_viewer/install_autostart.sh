#!/usr/bin/env bash
# 문서 뷰어를 맥 로그인 시 자동으로 켜지게 등록한다.
#
# 왜: 매번 터미널을 켜는 마찰을 없애려고. 뷰어는 "즐겨찾기 클릭 한 번"이어야
# 실제로 쓰이고, 그래야 오래된 문서를 보는 일이 사라진다.
#
# 실행: ./scripts/docs_viewer/install_autostart.sh
# 해제: ./scripts/docs_viewer/uninstall_autostart.sh
#
# ⚠️ 프로젝트 폴더를 옮기거나 이름을 바꾸면 이 스크립트를 다시 실행해야 한다.
#    (launchd 등록에는 절대경로가 들어가므로)
set -euo pipefail

LABEL="com.nolmeongbopseo.docsviewer"
PORT="${DOCS_VIEWER_PORT:-4321}"

HERE="$(cd "$(dirname "$0")" && pwd)"
SERVER="$HERE/server.py"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/nolmeong-docs-viewer.log"

# 시스템 파이썬을 쓴다. .venv를 다시 만들어도 뷰어가 안 깨지게.
PYTHON="/usr/bin/python3"

if [ ! -x "$PYTHON" ]; then
  echo "❌ $PYTHON 이 없습니다. Xcode 명령줄 도구를 설치하세요: xcode-select --install"
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# 이미 등록돼 있으면 먼저 내린다 (재설치를 안전하게).
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON</string>
    <string>$SERVER</string>
    <string>--port</string>
    <string>$PORT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <!-- 뻗으면 맥이 알아서 다시 띄운다. 30초 간격을 둬서 무한 재시작을 막는다. -->
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST_EOF

launchctl bootstrap "gui/$UID" "$PLIST"
sleep 1

if curl -sf -o /dev/null "http://localhost:$PORT/api/tree"; then
  COUNT=$(curl -s "http://localhost:$PORT/api/tree" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')
  echo "✅ 문서 뷰어가 켜졌습니다 (문서 $COUNT개)"
  echo ""
  echo "   👉 http://localhost:$PORT"
  echo ""
  echo "   이 주소를 브라우저 즐겨찾기에 넣어두세요."
  echo "   맥을 껐다 켜도 자동으로 켜집니다."
  echo "   기록: $LOG"
  exit 0
fi

# 여기부터는 실패 처리. 가장 흔한 원인이 macOS 파일 접근 권한이다.
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

if grep -q "Operation not permitted" "$LOG" 2>/dev/null; then
  cat <<'MSG'
⚠️  macOS가 막았습니다. 자동 시작은 등록하지 않았습니다.

   이유: 이 프로젝트가 "데스크탑" 폴더 안에 있습니다.
   macOS는 배경에서 도는 프로그램이 데스크탑·문서·다운로드 폴더를
   읽는 것을 기본으로 차단합니다. 터미널에서 직접 실행할 때는 되지만,
   로그인 시 자동 실행되는 프로그램은 안 됩니다.

   대신 이렇게 쓰세요 (권한 문제 없음):
     scripts/docs_viewer/문서보기.command 를 더블클릭

   굳이 자동 시작을 원한다면 방법은 둘입니다.

   ① 프로젝트를 데스크탑 밖으로 옮긴다  ← 권장
      예: ~/dev/놀멍봅서
      옮긴 뒤 이 스크립트를 다시 실행하면 그대로 됩니다.

   ② /usr/bin/python3 에 "전체 디스크 접근 권한"을 준다
      ⚠️ 이 맥에서 실행되는 모든 파이썬 스크립트가 전체 디스크를 읽게 됩니다.
         권한 범위가 넓으니 ①을 먼저 고려하세요.
MSG
  exit 1
fi

echo "⚠️  등록은 했는데 응답이 없습니다. 기록을 보세요: $LOG"
tail -5 "$LOG" 2>/dev/null
exit 1
