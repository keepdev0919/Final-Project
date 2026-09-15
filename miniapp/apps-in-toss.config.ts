import { defineConfig } from '@apps-in-toss/web-framework/config';

export default defineConfig({
  appName: 'nolmeongbopseo',
  brand: {
    // PixelColor.primary (놀멍봅서 초록). ios/…/DesignSystem/PixelColor.swift
    primaryColor: '#006D39',
  },
  // 현재 위치 — PLAY 에서 START·다음 지점까지 거리, 지도의 내 위치.
  // 거부해도 나머지 기능은 그대로 된다 (src/lib/location.ts).
  permissions: [{ name: 'geolocation', access: 'access' }],
  // WebView 속성 (docs: /documentation/integration/props). 설정 단계에서 적용된다.
  webView: {
    // 곱딱이 대사는 단계가 바뀌면 탭 없이 읽는다 (Swift StoryAudioPlayer 와 같다). 기본값 true 면
    // PLAY 첫 줄(첫 지점 가는 길 안내)이 자동재생 제한에 걸려 자막만 나온다.
    mediaPlaybackRequiresUserAction: false,
    // iOS 기본값은 당겨서 새로고침 켜짐(bounces 도 함께 켜짐). 러너에서 실수로 당기면 웹뷰가 통째로
    // 다시 떠서 풀던 미션의 Step·힌트·보던 발견/이야기가 사라진다(저장은 미션 단위).
    // 홈·코스 탭의 당겨서 새로고침은 화면 안에서 직접 받는다(src/ui/usePullToRefresh.ts).
    pullToRefreshEnabled: false,
    bounces: false,
    // Android 오버스크롤 효과도 끈다 — 화면 안 당겨서 새로고침과 겹치지 않게.
    overScrollMode: 'never',
  },
  webBundleDir: 'dist',
});
