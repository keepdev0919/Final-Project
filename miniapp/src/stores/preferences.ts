/**
 * 작은 설정값 — iOS 의 UserDefaults/AppStorage 자리.
 *
 *   play.voiceMuted  곱딱이 음성 끔 (StoryAudioPlayer.isMuted). 기기에 남아 다음 PLAY 에도 이어진다.
 *   selected_tab     마지막으로 본 탭 (ContentView @AppStorage). 앱을 다시 열면 그 탭에서 시작한다.
 */
import { createJsonStore } from './jsonStore';
import type { KeyValueBackend } from './kv';

export type AppTab = 'home' | 'course' | 'map' | 'profile';

const TABS: readonly AppTab[] = ['home', 'course', 'map', 'profile'];

export function createVoiceMutedStore(backend: KeyValueBackend) {
  return createJsonStore<boolean>({
    backend,
    key: 'play.voiceMuted',
    empty: () => false,
    parse: (v) => (typeof v === 'boolean' ? v : null),
  });
}

export function createSelectedTabStore(backend: KeyValueBackend) {
  // 예전 값·모르는 값이면 홈으로 떨어진다 — 앱이 깨지지는 않는다.
  return createJsonStore<AppTab>({
    backend,
    key: 'selected_tab',
    empty: () => 'home',
    parse: (v) => (typeof v === 'string' && (TABS as readonly string[]).includes(v) ? (v as AppTab) : null),
  });
}
