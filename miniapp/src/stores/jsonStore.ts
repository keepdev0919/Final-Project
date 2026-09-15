/**
 * JSON 한 덩어리를 키 하나에 담는 저장소의 공통 뼈대.
 *
 * - 앱 시작 때 `hydrate()` 로 한 번 읽어 메모리에 둔다 → 이후 읽기는 **동기**다.
 * - 쓰기는 메모리를 먼저 바꾸고(화면이 바로 반영), 저장소 쓰기는 **순서대로 줄 세운다**.
 *   (빠르게 두 번 저장해도 늦게 끝난 옛 값이 새 값을 덮지 않는다.)
 * - `subscribe` 는 React `useSyncExternalStore` 와 맞물린다.
 */
import type { KeyValueBackend } from './kv';

export interface JsonStore<T> {
  readonly key: string;
  hydrate(): Promise<void>;
  isHydrated(): boolean;
  get(): T;
  /** 메모리를 바꾸고 저장을 줄 세운다. 반환 Promise 는 **이번 쓰기**가 끝나면 풀린다(실패하면 reject). */
  set(next: T): Promise<void>;
  subscribe(listener: () => void): () => void;
  /** 줄 서 있는 쓰기가 다 끝날 때까지 기다린다 (테스트·앱 종료 직전). */
  whenIdle(): Promise<void>;
}

export function createJsonStore<T>(opts: {
  backend: KeyValueBackend;
  key: string;
  empty: () => T;
  /** 저장된 JSON 을 검사해 T 로. 못 읽는 모양이면 null → 저장값을 버린다. */
  parse: (raw: unknown) => T | null;
}): JsonStore<T> {
  const { backend, key, empty, parse } = opts;
  let state: T = empty();
  let hydrated = false;
  let queue: Promise<void> = Promise.resolve();
  const listeners = new Set<() => void>();

  const notify = () => listeners.forEach((l) => l());

  return {
    key,
    async hydrate() {
      let raw: string | null = null;
      try {
        raw = await backend.getItem(key);
      } catch (e) {
        console.warn(`[store:${key}] 읽기 실패`, e);
      }
      if (raw != null) {
        let value: T | null = null;
        try {
          value = parse(JSON.parse(raw));
        } catch {
          value = null;
        }
        if (value == null) {
          // 저장 형식이 바뀌어 못 읽는 데이터는 버린다. 남겨두면 매번 실패를 반복한다.
          console.warn(`[store:${key}] 못 읽는 저장값을 버립니다.`);
          state = empty();
          await backend.removeItem(key).catch(() => undefined);
        } else {
          state = value;
        }
      }
      hydrated = true;
      notify();
    },
    isHydrated: () => hydrated,
    get: () => state,
    set(next: T) {
      state = next;
      notify();
      const json = JSON.stringify(next);
      const write = queue.then(() => backend.setItem(key, json));
      // 줄은 실패해도 끊기지 않는다 — 다음 쓰기는 계속 간다.
      queue = write.catch((e) => {
        console.warn(`[store:${key}] 쓰기 실패`, e);
      });
      return write;
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    whenIdle: () => queue,
  };
}
