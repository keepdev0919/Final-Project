/**
 * 서버 주소 — App/Config.swift 이식.
 *
 * 앱인토스 전용 서버(Railway 환경 `apps-in-toss`)를 부른다. 같은 backend/ 코드를 따로 띄운 것이다.
 * `production` 환경(…-production.up.railway.app)은 앱스토어 iOS 1.0 (2)가 부르는 서버라
 * 공모전 심사(2026-10 말)까지 그대로 둔다 — 이 앱에서 부르지 않는다. (2026-09-15 조익준님 결정)
 *
 * `VITE_API_BASE` 로 바꿀 수 있다 (예: `.env.local` 에 `VITE_API_BASE=https://…`).
 * 앱인토스는 HTTPS 만 허용하므로 http 주소를 주면 기본값으로 되돌린다.
 */
const DEFAULT_API_BASE = 'https://nolmeongbopseo-apps-in-toss.up.railway.app';

function resolveBase(): string {
  const raw = (import.meta.env.VITE_API_BASE ?? '').trim();
  if (!raw) return DEFAULT_API_BASE;
  if (!raw.startsWith('https://')) {
    console.warn(`[config] VITE_API_BASE 는 https 여야 해요 (${raw}). 기본 서버를 씁니다.`);
    return DEFAULT_API_BASE;
  }
  return raw.replace(/\/+$/, '');
}

export const API_BASE = resolveBase();

/** 개인정보 처리방침 (서버가 함께 서빙: backend/routers/legal.py). 프로필 탭 하단 링크. */
export const PRIVACY_POLICY_URL = `${API_BASE}/privacy`;
