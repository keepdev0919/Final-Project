/**
 * 거리 계산 — **단말 안에서만** 한다. 사용자 좌표를 서버로 보내지 않는다 (데이터.md §6).
 * iOS `CLLocation.distance(from:)` 자리.
 */
import type { LatLng } from './region';

const EARTH_RADIUS_M = 6_371_008.8;
const rad = (d: number) => (d * Math.PI) / 180;

/** 두 좌표 사이 직선 거리(m) — haversine. */
export function distanceMeters(a: LatLng, b: LatLng): number {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** 「약 350m」 / 「약 1.2km」 — PLAY 러너의 「다음 지점까지」 표기 (Swift `"약 %.0fm"` / `"약 %.1fkm"`). */
export function approxDistanceText(meters: number): string {
  return meters < 1000 ? `약 ${Math.round(meters)}m` : `약 ${(meters / 1000).toFixed(1)}km`;
}
