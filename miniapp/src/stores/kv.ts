/**
 * 문자열 키-값 저장소 추상화.
 *
 * 앱에서는 `kvToss.ts` 의 `appStorage`(앱인토스 Storage SDK → 실패하면 localStorage)를 쓰고,
 * 테스트에서는 `createMemoryBackend()` 를 쓴다. 저장소 로직(playProgress·savedCourses…)은
 * 이 인터페이스만 알아서 SDK 없이 테스트된다.
 */
export interface KeyValueBackend {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

/** 메모리 저장소 (테스트용). `dump()` 로 지금 담긴 값을 본다. */
export function createMemoryBackend(initial: Record<string, string> = {}): KeyValueBackend & {
  dump(): Record<string, string>;
  /** 다음 setItem 을 실패시킨다 (쓰기 실패 경로 테스트용). */
  failNextWrite(): void;
} {
  const data = new Map(Object.entries(initial));
  let failNext = false;
  return {
    async getItem(key) {
      return data.has(key) ? (data.get(key) as string) : null;
    },
    async setItem(key, value) {
      if (failNext) {
        failNext = false;
        throw new Error('write failed (test)');
      }
      data.set(key, value);
    },
    async removeItem(key) {
      data.delete(key);
    },
    dump() {
      return Object.fromEntries(data);
    },
    failNextWrite() {
      failNext = true;
    },
  };
}
