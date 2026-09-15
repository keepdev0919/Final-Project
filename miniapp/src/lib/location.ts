/**
 * 현재 위치 — Services/LocationService.swift 이식 (앱인토스 위치 SDK).
 *
 * GPS 는 PLAY 의 **보조 기능**이다. 쓰는 곳: START·다음 Point 까지 거리, 지도의 내 위치.
 * ⚠️ 받은 좌표는 **단말 안에서만** 쓴다. 서버로 보내지 않는다 (위치기반서비스사업자 신고 대상이 된다).
 * ⚠️ 권한을 거부했거나 SDK 가 없으면 **조용히 null** 이다. 거리가 안 보일 뿐 PLAY 는 끝까지 된다.
 *
 * SDK: `Device.getLocation`(= getCurrentLocation) · `Device.subscribeLocation`(= startUpdateLocation),
 *      각각 `.getPermission()` · `.openPermissionDialog()` 를 갖는다.
 *      apps-in-toss.config.ts 의 permissions 에 `{ name: 'geolocation', access: 'access' }` 가 있어야 한다.
 *
 * 여러 화면이 같은 값을 본다 (Swift `LocationService.shared` 처럼 모듈 하나가 들고 있다).
 */
import { Accuracy, Device } from '@apps-in-toss/web-framework';
import { useEffect, useSyncExternalStore } from 'react';

export interface UserLocation {
  lat: number;
  lng: number;
  /** 오차 반경 (m) */
  accuracy: number;
  /** epoch ms */
  timestamp: number;
}

/**
 *   idle         아직 묻지 않음
 *   requesting   권한 대화상자 또는 위치를 기다리는 중
 *   granted      위치를 받았다 (location 이 채워짐)
 *   denied       사용자가 거부했다
 *   unavailable  SDK 없음·오류·시간 초과
 */
export type LocationStatus = 'idle' | 'requesting' | 'granted' | 'denied' | 'unavailable';

interface State {
  location: UserLocation | null;
  status: LocationStatus;
}

let state: State = { location: null, status: 'idle' };
const listeners = new Set<() => void>();
const setState = (patch: Partial<State>) => {
  state = { ...state, ...patch };
  listeners.forEach((l) => l());
};

const SDK_TIMEOUT_MS = 15_000;

function withTimeout<T>(p: Promise<T>, ms = SDK_TIMEOUT_MS): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('location timeout')), ms);
    p.then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      },
    );
  });
}

type SdkLocation = { coords: { latitude: number; longitude: number; accuracy: number }; timestamp: number };

function toUserLocation(l: SdkLocation): UserLocation {
  return { lat: l.coords.latitude, lng: l.coords.longitude, accuracy: l.coords.accuracy, timestamp: l.timestamp };
}

/** 권한 확인 → 필요하면 대화상자. 허용이면 true. */
async function ensurePermission(): Promise<boolean> {
  try {
    const status = await withTimeout(Device.getLocation.getPermission());
    if (status === 'allowed') return true;
    if (status === 'denied') {
      setState({ status: 'denied' });
      return false;
    }
    setState({ status: 'requesting' });
    const answer = await withTimeout(Device.getLocation.openPermissionDialog(), 60_000);
    if (answer === 'allowed') return true;
    setState({ status: 'denied' });
    return false;
  } catch {
    setState({ status: 'unavailable' });
    return false;
  }
}

let inflight: Promise<UserLocation | null> | null = null;

/**
 * **1회성** 위치 요청 (Swift `requestCurrentLocationOnce`).
 * 권한이 아직 없으면 대화상자를 띄운다. 거부·오류면 null — 예외를 던지지 않는다.
 * 동시에 여러 번 불러도 요청은 하나만 나간다.
 */
export function requestLocationOnce(): Promise<UserLocation | null> {
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      if (!(await ensurePermission())) return null;
      setState({ status: 'requesting' });
      const loc = toUserLocation(await withTimeout(Device.getLocation({ accuracy: Accuracy.High })));
      setState({ location: loc, status: 'granted' });
      return loc;
    } catch {
      // 위치를 못 받으면 거리 표시가 비는 것뿐이다.
      setState({ status: state.location ? 'granted' : 'unavailable' });
      return null;
    } finally {
      inflight = null;
    }
  })();
  return inflight;
}

let watchers = 0;
let stopWatch: (() => void) | null = null;
const stillWanted = () => watchers > 0;

/** 계속 추적 시작. 반환 함수로 멈춘다. 여러 곳이 불러도 구독은 하나만 연다. */
export function startWatchingLocation(): () => void {
  watchers += 1;
  if (watchers === 1) {
    void (async () => {
      if (!(await ensurePermission()) || !stillWanted() || stopWatch) return;
      try {
        stopWatch = Device.subscribeLocation({
          options: { accuracy: Accuracy.High, timeInterval: 3000, distanceInterval: 10 },
          onEvent: (l) => setState({ location: toUserLocation(l), status: 'granted' }),
          onError: () => setState({ status: state.location ? 'granted' : 'unavailable' }),
        });
      } catch {
        setState({ status: 'unavailable' });
      }
    })();
  }
  let stopped = false;
  return () => {
    if (stopped) return;
    stopped = true;
    watchers = Math.max(0, watchers - 1);
    if (watchers === 0 && stopWatch) {
      stopWatch();
      stopWatch = null;
    }
  };
}

function subscribe(l: () => void) {
  listeners.add(l);
  return () => {
    listeners.delete(l);
  };
}
const snapshot = () => state;

/**
 * 현재 위치 훅.
 *
 *   const { location, status } = useUserLocation({ mode: 'once' });   // 화면이 열릴 때 한 번
 *   const { location } = useUserLocation({ mode: 'watch' });          // 화면이 떠 있는 동안 계속
 *   const { location } = useUserLocation();                            // 요청 없이 마지막 값만 본다
 *
 * `enabled: false` 면 요청하지 않는다(권한 대화상자를 띄울 때를 늦추고 싶을 때).
 */
export function useUserLocation(opts: { mode?: 'none' | 'once' | 'watch'; enabled?: boolean } = {}): {
  location: UserLocation | null;
  status: LocationStatus;
  /** 다시 1회 요청 */
  refresh: () => Promise<UserLocation | null>;
} {
  const { mode = 'none', enabled = true } = opts;
  const s = useSyncExternalStore(subscribe, snapshot);

  useEffect(() => {
    if (!enabled) return;
    if (mode === 'once') {
      void requestLocationOnce();
      return;
    }
    if (mode === 'watch') return startWatchingLocation();
    return;
  }, [mode, enabled]);

  return { location: s.location, status: s.status, refresh: requestLocationOnce };
}

/** 지금 들고 있는 마지막 위치 (없으면 null). */
export function lastKnownLocation(): UserLocation | null {
  return state.location;
}
