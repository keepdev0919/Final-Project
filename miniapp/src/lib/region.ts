/**
 * 제주 4개 권역 — Models/JejuRegion.swift + MapTabView.swift 의 JejuMapFocus 이식.
 *
 * **백엔드와 같은 기준**이다 (backend/scripts/build_curated_courses.py::_classify_place_region).
 * 코스 탭의 권역 선택과 지도 탭의 권역 칩이 이걸 같이 쓴다.
 * ⚠️ 경계값을 바꾸면 백엔드도 같이 바꿔야 한다.
 *
 * 권역색은 **앱 전체에서 같은 색**이다 (코스 카드 배지 · 코스 탭 지도 버튼 · 지도 탭 칩).
 *   동부 주황 · 서부 보라 · 북부 파랑 · 남부 청록 · 전체 잉크
 */
import { PixelColor } from '../ui/tokens';

export interface LatLng {
  lat: number;
  lng: number;
}

export interface LatLngBounds {
  south: number;
  west: number;
  north: number;
  east: number;
}

export type JejuRegionId = '서부' | '북부' | '동부' | '남부';

export interface JejuRegionDef {
  id: JejuRegionId;
  label: string;
  sublabel: string;
  /** 권역색 (CSS 변수 문자열) */
  color: string;
  /** 권역색 위 글자색 */
  onColor: string;
  /** 권역 사각형 (지도 강조·카메라 맞추기) */
  polygon: LatLng[];
  /** 레이블 표시 위치 */
  labelCoord: LatLng;
}

/** 「전체」의 id. 코스의 장소가 한 권역에 과반으로 몰리지 않으면 백엔드가 이 값을 준다. */
export const WHOLE_ISLAND_ID = '전체';

/** 순서: 서부 · 북부 · 동부 · 남부 (Swift `JejuRegionDef.all`) */
export const JEJU_REGIONS: readonly JejuRegionDef[] = [
  {
    id: '서부',
    label: '서부',
    sublabel: '한림·애월',
    color: PixelColor.regionWest,
    onColor: PixelColor.onRegionWest,
    polygon: [
      { lat: 33.57, lng: 126.1 },
      { lat: 33.57, lng: 126.4 },
      { lat: 33.1, lng: 126.4 },
      { lat: 33.1, lng: 126.1 },
    ],
    labelCoord: { lat: 33.38, lng: 126.24 },
  },
  {
    id: '북부',
    label: '북부',
    sublabel: '제주시',
    color: PixelColor.regionNorth,
    onColor: PixelColor.onRegionNorth,
    polygon: [
      { lat: 33.57, lng: 126.4 },
      { lat: 33.57, lng: 126.7 },
      { lat: 33.45, lng: 126.7 },
      { lat: 33.45, lng: 126.4 },
    ],
    labelCoord: { lat: 33.51, lng: 126.52 },
  },
  {
    id: '동부',
    label: '동부',
    sublabel: '성산·구좌',
    color: PixelColor.regionEast,
    onColor: PixelColor.onRegionEast,
    polygon: [
      { lat: 33.57, lng: 126.7 },
      { lat: 33.57, lng: 126.97 },
      { lat: 33.1, lng: 126.97 },
      { lat: 33.1, lng: 126.7 },
    ],
    labelCoord: { lat: 33.38, lng: 126.83 },
  },
  {
    id: '남부',
    label: '남부',
    sublabel: '서귀포',
    color: PixelColor.regionSouth,
    onColor: PixelColor.onRegionSouth,
    polygon: [
      { lat: 33.3, lng: 126.4 },
      { lat: 33.3, lng: 126.7 },
      { lat: 33.1, lng: 126.7 },
      { lat: 33.1, lng: 126.4 },
    ],
    labelCoord: { lat: 33.22, lng: 126.55 },
  },
];

export function findRegion(id: string): JejuRegionDef | undefined {
  return JEJU_REGIONS.find((r) => r.id === id);
}

/** 좌표가 이 권역에 드는가 — 백엔드 GPS 필터와 같은 기준. (권역끼리 겹칠 수 있다) */
export function regionContains(id: string, c: LatLng): boolean {
  switch (id) {
    case '서부':
      return c.lng < 126.4;
    case '북부':
      return c.lat >= 33.45;
    case '동부':
      return c.lng >= 126.7;
    case '남부':
      return c.lat < 33.3;
    default:
      return false;
  }
}

/** 권역 id → 색. **모르는 id 와 「전체」는 잉크**다. */
export function regionColors(id: string | null | undefined): { fill: string; on: string } {
  const r = id ? findRegion(id) : undefined;
  if (!r) return { fill: PixelColor.regionAll, on: PixelColor.onRegionAll };
  return { fill: r.color, on: r.onColor };
}

// ── 지도 카메라 목표 (JejuMapFocus) ─────────────────────────────────────

export type JejuMapFocus = { kind: 'wholeIsland' } | { kind: 'region'; id: string };

/** 섬 전체 사각형 */
export const JEJU_ISLAND_BOUNDS: LatLngBounds = { south: 33.1, west: 126.12, north: 33.58, east: 126.98 };

/** 제주 가운데 (좌표가 하나도 없을 때의 기본 중심) */
export const JEJU_CENTER: LatLng = { lat: 33.38, lng: 126.55 };

export function boundsOf(points: LatLng[]): LatLngBounds | null {
  if (points.length === 0) return null;
  let south = Infinity,
    west = Infinity,
    north = -Infinity,
    east = -Infinity;
  for (const p of points) {
    south = Math.min(south, p.lat);
    north = Math.max(north, p.lat);
    west = Math.min(west, p.lng);
    east = Math.max(east, p.lng);
  }
  return { south, west, north, east };
}

/** 지도 탭의 권역 칩이 고른 곳 → 맞출 사각형. */
export function focusBounds(focus: JejuMapFocus): LatLngBounds {
  if (focus.kind === 'wholeIsland') return JEJU_ISLAND_BOUNDS;
  const r = findRegion(focus.id);
  return (r && boundsOf(r.polygon)) ?? JEJU_ISLAND_BOUNDS;
}

export function focusKey(focus: JejuMapFocus): string {
  return focus.kind === 'wholeIsland' ? 'whole' : `region:${focus.id}`;
}
