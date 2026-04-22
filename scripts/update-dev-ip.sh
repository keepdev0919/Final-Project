#!/bin/bash
# 실기기 테스트용 Mac IP 자동 갱신
# 사용법: ./scripts/update-dev-ip.sh

CONFIG="ios/JejuFolklore/Sources/App/Config.swift"

# Mac의 현재 로컬 IP 감지 (Wi-Fi 우선, 유선 fallback)
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)

if [ -z "$IP" ]; then
    echo "❌ 네트워크 인터페이스를 찾지 못했습니다. Wi-Fi 연결 상태를 확인하세요."
    exit 1
fi

# Config.swift 안의 IP 패턴 교체
sed -i '' "s|http://[0-9.]*:8000|http://${IP}:8000|g" "$CONFIG"

echo "✅ $CONFIG 업데이트 완료"
echo "   Mac IP: $IP"
echo "   → 이제 실기기를 Mac과 같은 Wi-Fi에 연결하고 앱을 빌드하세요."
