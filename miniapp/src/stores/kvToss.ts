/**
 * 앱 저장소 — 앱인토스 **Storage SDK** 를 쓴다.
 *
 * 왜 localStorage 가 아니라 SDK 인가 (docs: /documentation/common/file-storage/storage)
 *   Storage 는 토스 앱의 네이티브 저장소라 WebView 캐시 정리와 무관하게 남는다
 *   (토스 앱을 지우면 함께 지워진다). 60~75분짜리 PLAY 진행이 조용히 사라지면 안 된다.
 *
 * 브라우저 개발(devtools mock)에서는 mock 이 `__ait_storage:` 접두어로 localStorage 에 담는다.
 * SDK 가 없는 환경(토스 밖에서 연 운영 번들 등 — SDK 가 곧바로 예외를 던진다)에서는 **localStorage 로
 * 떨어진다** — 저장이 안 되는 것보다 낫다. 판정은 첫 호출에서 한 번만 한다.
 *
 * ## 토스 앱 안에서는 느리다고 localStorage 로 떨어뜨리지 않는다
 * 한 번 느렸다고 그 세션을 localStorage 에 쓰면, 다음 실행 때 SDK 가 제때 답하는 순간 앱은 SDK 만
 * 읽는다 — 지난번 진행이 사라진 것처럼 보인다(출시 가이드: 「종료했다 다시 들어와도 데이터 유지」).
 * 그래서 토스 앱 안(`window.ReactNativeWebView`)에서는 넉넉히 기다리며 다시 묻고, 그래도 끝내
 * 답이 없을 때만 localStorage 에 쓴다. 그렇게 쓴 값은 **다음에 SDK 가 살아나면 SDK 로 옮긴다**
 * (`mergeFallbackValue`). 첫 화면은 main.tsx 가 3초까지만 기다리고 그린다 — 늦게 도착한 값은
 * 저장소 훅이 다시 그린다.
 */
import { Storage } from '@apps-in-toss/web-framework';
import type { KeyValueBackend } from './kv';

/** 토스 앱 밖(SDK 가 예외를 안 던지는데 답도 없는 이상한 환경)에서 기다리는 시간. */
const PROBE_TIMEOUT_MS = 1500;
/** 토스 앱 안에서 한 번 묻고 기다리는 시간과 횟수 — 합쳐 최대 12초. */
const IN_TOSS_PROBE_TIMEOUT_MS = 4000;
const IN_TOSS_PROBE_ATTEMPTS = 3;
const LOCAL_PREFIX = 'nmbs:';

type Mode = 'sdk' | 'local';
let mode: Promise<Mode> | null = null;

function timeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('storage timeout')), ms);
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

function inTossApp(): boolean {
  return typeof window !== 'undefined' && (window as { ReactNativeWebView?: unknown }).ReactNativeWebView != null;
}

async function probe(): Promise<void> {
  if (!inTossApp()) {
    await timeout(Storage.getItem('__nmbs_probe'), PROBE_TIMEOUT_MS);
    return;
  }
  let last: unknown = null;
  for (let i = 0; i < IN_TOSS_PROBE_ATTEMPTS; i++) {
    try {
      await timeout(Storage.getItem('__nmbs_probe'), IN_TOSS_PROBE_TIMEOUT_MS);
      return;
    } catch (e) {
      last = e;
    }
  }
  throw last;
}

function detect(): Promise<Mode> {
  if (!mode) {
    mode = (async () => {
      try {
        await probe();
      } catch (e) {
        console.warn('[storage] 앱인토스 Storage 를 쓸 수 없어 localStorage 로 대신합니다.', e);
        return 'local' as const;
      }
      // 지난번에 SDK 가 답하지 않아 localStorage 에 쓴 값이 있으면 SDK 로 옮긴다 (저장소를 읽기 전에).
      await migrateLocalToSdk().catch((e) => console.warn('[storage] 옮기기 실패', e));
      return 'sdk' as const;
    })();
  }
  return mode;
}

function local(): globalThis.Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function localKeys(ls: globalThis.Storage): string[] {
  const keys: string[] = [];
  for (let i = 0; i < ls.length; i++) {
    const k = ls.key(i);
    if (k && k.startsWith(LOCAL_PREFIX)) keys.push(k.slice(LOCAL_PREFIX.length));
  }
  return keys;
}

/** localStorage 에 대신 써 둔 값을 SDK 로 옮기고, 옮긴 것은 localStorage 에서 지운다. */
async function migrateLocalToSdk(): Promise<void> {
  const ls = local();
  if (!ls) return;
  for (const key of localKeys(ls)) {
    const localRaw = ls.getItem(LOCAL_PREFIX + key);
    if (localRaw == null) continue;
    const sdkRaw = await Storage.getItem(key);
    const merged = mergeFallbackValue(sdkRaw, localRaw);
    if (merged !== sdkRaw) await Storage.setItem(key, merged);
    ls.removeItem(LOCAL_PREFIX + key); // 옮기기에 실패하면 위에서 던져 localStorage 에 남는다
  }
}

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

/** 목록 항목의 신원 — 담은 코스는 sourceCourseId(없으면 id), 신고는 id. 모르면 내용 전체. */
function identityOf(item: unknown): string {
  if (isPlainObject(item)) {
    if (typeof item.sourceCourseId === 'string' && item.sourceCourseId) return `src:${item.sourceCourseId}`;
    if (typeof item.id === 'string') return `id:${item.id}`;
  }
  return `json:${JSON.stringify(item)}`;
}

/**
 * SDK 값(`sdkRaw`)과 SDK 가 답하지 않던 세션에 localStorage 에 쓴 값(`localRaw`)을 합친다.
 * localStorage 값은 **그 뒤 세션**에 쓴 것이라 더 새롭다고 본다.
 *
 * - SDK 에 값이 없으면 → localStorage 값.
 * - 둘 다 객체(PLAY 진행 `{ [playId]: 진행 }`)면 → 키별로 합친다. 두 쪽 모두 `updatedAt` 이 있으면
 *   더 늦게 저장한 쪽, 아니면 localStorage 쪽.
 * - 둘 다 목록(담은 코스·신고 대기열)이면 → 합치고 같은 신원은 localStorage 쪽 하나만.
 * - 그 밖(음성 끔·마지막 탭 같은 값 하나)은 → localStorage 값.
 * - JSON 이 아니면 → 손대지 않는다(SDK 값 그대로).
 */
export function mergeFallbackValue(sdkRaw: string | null, localRaw: string): string {
  if (sdkRaw == null) return localRaw;
  let sdk: unknown;
  let loc: unknown;
  try {
    sdk = JSON.parse(sdkRaw);
    loc = JSON.parse(localRaw);
  } catch {
    return sdkRaw;
  }
  if (isPlainObject(sdk) && isPlainObject(loc)) {
    const out: Record<string, unknown> = { ...sdk };
    for (const [k, lv] of Object.entries(loc)) {
      const sv = sdk[k];
      if (isPlainObject(sv) && isPlainObject(lv) && typeof sv.updatedAt === 'number' && typeof lv.updatedAt === 'number') {
        out[k] = lv.updatedAt >= sv.updatedAt ? lv : sv;
      } else {
        out[k] = lv;
      }
    }
    return JSON.stringify(out);
  }
  if (Array.isArray(sdk) && Array.isArray(loc)) {
    const localIds = new Set(loc.map(identityOf));
    return JSON.stringify([...sdk.filter((x) => !localIds.has(identityOf(x))), ...loc]);
  }
  return localRaw;
}

export const appStorage: KeyValueBackend = {
  async getItem(key) {
    if ((await detect()) === 'sdk') return Storage.getItem(key);
    return local()?.getItem(LOCAL_PREFIX + key) ?? null;
  },
  async setItem(key, value) {
    if ((await detect()) === 'sdk') return Storage.setItem(key, value);
    local()?.setItem(LOCAL_PREFIX + key, value);
  },
  async removeItem(key) {
    if ((await detect()) === 'sdk') return Storage.removeItem(key);
    local()?.removeItem(LOCAL_PREFIX + key);
  },
};
