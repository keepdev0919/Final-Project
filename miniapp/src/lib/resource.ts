/**
 * 서버 응답 캐시 + 훅.
 *
 * ## 왜 필요한가
 * iOS 는 탭 네 개의 화면을 **전부 살려 둔 채** 보이는 것만 바꾼다 — 탭을 오가도 다시 부르지 않는다.
 * 웹은 탭을 오가거나 뒤로 돌아오면 화면이 다시 마운트된다. 매번 부르면 느리고, 코스 목록
 * (`POST /course/list`, 분당 10회 제한)은 제한에 걸린다. 그래서 응답을 **모듈 수준**에 둔다.
 *
 * ## 요청은 화면이 사라져도 끝까지 간다
 * Swift HomeView 주석: `.task` 로 부르면 화면이 잠깐 다시 만들어지기만 해도 취소돼 퀘스트 탭이
 * 빈 채로 남았다. 여기서도 화면 언마운트로 요청을 끊지 않는다 — 결과는 캐시에 남는다.
 *
 *   const { data, error, loading, reload } = useResource('plays', () => PlayAPI.list());
 *   const { data } = useResource(`play:${playId}`, () => PlayAPI.detail(playId));
 *   const { data } = useResource(id ? `x:${id}` : null, …)   // key 가 null 이면 부르지 않는다
 *
 * 키 규칙(겹치지 않게): 'plays' · `play:<id>` · 'mapPins' · 'featured' · `courseList:<region>:<days>` ·
 *   `course:<courseId>` · `place:<name>:<lat>:<lng>` · `nearby:<lat>:<lng>` · `placePlays:<placeId>`
 */
import { useCallback, useEffect, useSyncExternalStore } from 'react';

interface Entry {
  data?: unknown;
  error?: unknown;
  promise?: Promise<unknown>;
  /** 마지막으로 성공한 시각 (epoch ms) */
  at?: number;
}

const cache = new Map<string, Entry>();
const listeners = new Map<string, Set<() => void>>();
const EMPTY: Entry = {};

function emit(key: string) {
  listeners.get(key)?.forEach((l) => l());
}

function put(key: string, e: Entry) {
  cache.set(key, e);
  emit(key);
}

/**
 * 불러오기. 이미 있으면 그대로 돌려주고(force 면 다시 부른다), 부르는 중이면 그 요청을 같이 기다린다.
 * 실패하면 reject — 이전에 성공한 data 는 지우지 않는다.
 */
export function fetchResource<T>(key: string, fetcher: () => Promise<T>, opts: { force?: boolean } = {}): Promise<T> {
  const cur = cache.get(key) ?? EMPTY;
  if (cur.promise) return cur.promise as Promise<T>;
  if (!opts.force && cur.at !== undefined) return Promise.resolve(cur.data as T);
  const promise = fetcher().then(
    (data) => {
      put(key, { data, at: Date.now() });
      return data;
    },
    (error: unknown) => {
      put(key, { data: cur.data, at: cur.at, error });
      throw error;
    },
  );
  put(key, { ...cur, error: undefined, promise });
  return promise;
}

/** 캐시에 있는 값 (없으면 undefined). */
export function peekResource<T>(key: string): T | undefined {
  return cache.get(key)?.data as T | undefined;
}

/** 캐시 값을 직접 넣는다 (예: 목록에서 이미 받은 것을 상세 캐시에 미리 채우기). */
export function setResource<T>(key: string, data: T): void {
  put(key, { data, at: Date.now() });
}

/** 지운다. prefix 로 끝나는 '*' 를 주면 그 접두어 전부 (`'courseList:*'`). */
export function invalidateResource(keyOrPrefix: string): void {
  const keys = keyOrPrefix.endsWith('*')
    ? [...cache.keys()].filter((k) => k.startsWith(keyOrPrefix.slice(0, -1)))
    : [keyOrPrefix];
  for (const k of keys) {
    cache.delete(k);
    emit(k);
  }
}

export interface ResourceState<T> {
  data: T | undefined;
  error: unknown;
  /** 부르는 중 (이미 data 가 있어도 새로고침 중이면 true) */
  loading: boolean;
  /** 다시 부른다 (당겨서 새로고침·다시 시도 버튼). 실패해도 reject 하지 않는다. */
  reload: () => Promise<void>;
}

/**
 * 캐시를 거치는 불러오기 훅. 처음 쓰일 때 한 번 부르고, 이후엔 캐시를 쓴다.
 * `fetcher` 는 key 가 같으면 바뀌어도 다시 부르지 않는다 (key 에 입력값을 다 넣을 것).
 */
export function useResource<T>(key: string | null, fetcher: () => Promise<T>): ResourceState<T> {
  const subscribe = useCallback(
    (l: () => void) => {
      if (!key) return () => undefined;
      let set = listeners.get(key);
      if (!set) {
        set = new Set();
        listeners.set(key, set);
      }
      set.add(l);
      return () => {
        set.delete(l);
      };
    },
    [key],
  );
  const entry = useSyncExternalStore(subscribe, () => (key ? (cache.get(key) ?? EMPTY) : EMPTY));

  useEffect(() => {
    if (!key) return;
    const cur = cache.get(key);
    if (cur?.at !== undefined || cur?.promise) return;
    fetchResource(key, fetcher).catch(() => undefined);
    // fetcher 는 일부러 뺀다 — 매 렌더 새 함수라도 key 가 같으면 같은 자원이다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const reload = useCallback(async () => {
    if (!key) return;
    await fetchResource(key, fetcher, { force: true }).catch(() => undefined);
  }, [key, fetcher]);

  return {
    data: entry.data as T | undefined,
    error: entry.error,
    loading: !!entry.promise,
    reload,
  };
}
