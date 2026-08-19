#!/usr/bin/env bash
# 문서 뷰어 자동 시작을 해제하고 지금 켜져 있는 것도 끈다.
set -euo pipefail

LABEL="com.nolmeongbopseo.docsviewer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

echo "✅ 문서 뷰어를 껐고, 자동 시작도 해제했습니다."
echo "   다시 켜려면: ./scripts/docs_viewer/install_autostart.sh"
