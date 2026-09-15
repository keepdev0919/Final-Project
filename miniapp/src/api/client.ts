/**
 * fetch 기반 API 클라이언트 — Services/APIClient.swift 이식.
 *
 * - 응답 JSON 의 키를 전부 camelCase 로 바꾼다 (Swift `convertFromSnakeCase` 와 같다).
 * - 요청 본문의 키는 snake_case 로 바꿔 보낸다 (Swift `convertToSnakeCase`).
 * - 요청 제한 120초 (Swift `timeoutIntervalForRequest`).
 *
 * ⚠️ 사용자 위치를 서버로 보내지 않는다. 쿼리에 들어가는 좌표는 **관광지 좌표**뿐이다
 *    (위치기반서비스사업자 신고 회피 — 데이터.md §6).
 */
import { API_BASE } from './config';

export type ApiErrorKind = 'invalidURL' | 'invalidResponse' | 'decodingFailed' | 'networkError' | 'aborted';

/** Swift `APIError`. `message` 는 Swift `errorDescription` 과 같은 한국어다. */
export class ApiError extends Error {
  readonly kind: ApiErrorKind;
  /** invalidResponse 일 때 HTTP 상태 코드 (응답이 없으면 0). */
  readonly status: number;

  constructor(kind: ApiErrorKind, status = 0, cause?: unknown) {
    super(ApiError.describe(kind, status, cause));
    this.name = 'ApiError';
    this.kind = kind;
    this.status = status;
  }

  private static describe(kind: ApiErrorKind, status: number, cause: unknown): string {
    switch (kind) {
      case 'invalidURL':
        return '잘못된 URL입니다.';
      case 'invalidResponse':
        return `서버 오류 (${status})`;
      case 'decodingFailed':
        return '데이터 파싱에 실패했습니다.';
      case 'aborted':
        return '요청이 취소됐어요.';
      case 'networkError':
        return cause instanceof Error && cause.message ? cause.message : '네트워크에 연결할 수 없어요.';
    }
  }
}

/** 호출이 취소(화면 이탈 등)된 것인지. 취소는 오류 화면을 띄울 일이 아니다. */
export function isAbortError(e: unknown): boolean {
  return e instanceof ApiError && e.kind === 'aborted';
}

const REQUEST_TIMEOUT_MS = 120_000;

// ── 키 변환 ─────────────────────────────────────────────────────────────

/** "bus_stops" → "busStops", "distance_m" → "distanceM" */
export function snakeToCamel(key: string): string {
  return key.replace(/_+([a-zA-Z0-9])/g, (_, c: string) => c.toUpperCase());
}

/** "durationDays" → "duration_days" */
export function camelToSnake(key: string): string {
  return key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** 객체·배열을 깊게 돌며 **키만** 바꾼다. 값(문자열)은 건드리지 않는다. */
export function convertKeys(value: unknown, convert: (k: string) => string): unknown {
  if (Array.isArray(value)) return value.map((v) => convertKeys(v, convert));
  if (isPlainObject(value)) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) out[convert(k)] = convertKeys(v, convert);
    return out;
  }
  return value;
}

// ── 요청 ────────────────────────────────────────────────────────────────

export interface RequestOptions {
  /** 화면을 떠날 때 요청을 끊으려면 AbortController.signal 을 넘긴다. */
  signal?: AbortSignal;
}

function buildURL(path: string, query?: Record<string, string | number>): URL {
  try {
    const url = new URL(API_BASE + path);
    if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, String(v));
    return url;
  } catch {
    throw new ApiError('invalidURL');
  }
}

/** 바깥 signal + 120초 제한을 하나로 묶는다 (AbortSignal.any 는 구형 WebView 에 없다). */
function withTimeout(outer?: AbortSignal): { signal: AbortSignal; done: () => void; timedOut: () => boolean } {
  const ctrl = new AbortController();
  let expired = false;
  const timer = setTimeout(() => {
    expired = true;
    ctrl.abort();
  }, REQUEST_TIMEOUT_MS);
  const onAbort = () => ctrl.abort();
  if (outer) {
    if (outer.aborted) ctrl.abort();
    else outer.addEventListener('abort', onAbort, { once: true });
  }
  return {
    signal: ctrl.signal,
    done: () => {
      clearTimeout(timer);
      outer?.removeEventListener('abort', onAbort);
    },
    timedOut: () => expired,
  };
}

async function perform(url: URL, init: RequestInit, opts?: RequestOptions): Promise<Response> {
  const t = withTimeout(opts?.signal);
  let res: Response;
  try {
    res = await fetch(url, { ...init, signal: t.signal });
  } catch (e) {
    if (t.signal.aborted && !t.timedOut()) throw new ApiError('aborted', 0, e);
    throw new ApiError('networkError', 0, t.timedOut() ? new Error('요청 시간이 초과됐어요.') : e);
  } finally {
    t.done();
  }
  if (!res.ok) throw new ApiError('invalidResponse', res.status);
  return res;
}

async function decode<T>(res: Response): Promise<T> {
  try {
    const json: unknown = await res.json();
    return convertKeys(json, snakeToCamel) as T;
  } catch (e) {
    throw new ApiError('decodingFailed', res.status, e);
  }
}

/** GET. `query` 값은 문자열로 바꿔 붙인다. */
export async function apiGet<T>(path: string, query?: Record<string, string | number>, opts?: RequestOptions): Promise<T> {
  const res = await perform(buildURL(path, query), { method: 'GET' }, opts);
  return decode<T>(res);
}

/** POST JSON. 본문 키는 snake_case 로 바뀌어 나간다. */
export async function apiPost<T>(path: string, body: unknown, opts?: RequestOptions): Promise<T> {
  const res = await perform(
    buildURL(path),
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(convertKeys(body, camelToSnake)),
    },
    opts,
  );
  return decode<T>(res);
}
