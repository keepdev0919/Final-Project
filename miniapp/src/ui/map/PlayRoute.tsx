/**
 * PLAY 경로 부품 — PlayDetailView.swift 의 PlayRouteMap · RouteListRow · RouteMarkerKind 이식.
 * PLAY 상세의 「탐험 경로」와 러너의 「진행 지도」가 **같이** 쓴다.
 */
import { useMemo } from 'react';
import { pointCoordinate } from '../../api/models';
import type { Play } from '../../api/types';
import { JEJU_CENTER, type LatLng } from '../../lib/region';
import { Icon } from '../Icon';
import { PixelColor, PixelFont, PixelSpacing } from '../tokens';
import { MapView } from './MapView';
import type { MapCamera, MapMarker } from './types';

// ── 경로 지도 ───────────────────────────────────────────────────────────

/**
 * 이 PLAY 가 어디를 도는지 보여주는 작은 지도. Point 마다 번호 사각형(26, 글자 14).
 *
 * ⚠️ Point 를 선으로 잇지 않는다. 검증된 보행 경로가 없는데 선을 그으면 걸을 수 있는 길처럼
 *    읽힌다 (데이터.md §5).
 * 범위는 Point 들의 사각형 × 2.2, 최소 0.004° — Point 가 붙어 있는 성읍에서 과하게 확대되지 않게.
 * 높이는 부모가 정한다 (러너 진행 지도는 220).
 */
export function PlayRouteMap({ play, height }: { play: Play; height?: number | string }) {
  const { markers, camera, key } = useMemo(() => {
    // 번호는 Point 순서 그대로 — 좌표 없는 Point 가 있어도 번호가 밀리지 않는다.
    const pts: { id: string; title: string; i: number; c: LatLng }[] = [];
    play.points.forEach((p, i) => {
      const c = pointCoordinate(p);
      if (c) pts.push({ id: p.id, title: p.title, i, c });
    });
    const markers: MapMarker[] = pts.map(({ id, title, i, c }) => ({
      id,
      kind: 'number',
      position: c,
      label: String(i + 1),
      size: 26,
      font: 'label',
      // MapKit Annotation(point.title, …) — 번호 아래에 지점 이름이 보인다.
      caption: title,
      title,
    }));
    let camera: MapCamera;
    if (pts.length === 0) {
      camera = { kind: 'bounds', bounds: { south: JEJU_CENTER.lat - 0.25, north: JEJU_CENTER.lat + 0.25, west: JEJU_CENTER.lng - 0.25, east: JEJU_CENTER.lng + 0.25 } };
    } else {
      const lats = pts.map((x) => x.c.lat);
      const lngs = pts.map((x) => x.c.lng);
      const cLat = (Math.min(...lats) + Math.max(...lats)) / 2;
      const cLng = (Math.min(...lngs) + Math.max(...lngs)) / 2;
      const hLat = Math.max((Math.max(...lats) - Math.min(...lats)) * 2.2, 0.004) / 2;
      const hLng = Math.max((Math.max(...lngs) - Math.min(...lngs)) * 2.2, 0.004) / 2;
      camera = { kind: 'bounds', bounds: { south: cLat - hLat, north: cLat + hLat, west: cLng - hLng, east: cLng + hLng } };
    }
    return { markers, camera, key: `${play.id}:${markers.map((m) => m.id).join(',')}` };
  }, [play]);

  return <MapView markers={markers} camera={camera} cameraKey={key} height={height} ariaLabel={`${play.title} 탐험 경로 지도`} />;
}

// ── 경로 목록 줄 ────────────────────────────────────────────────────────

export type RouteMarkerKind = 'terminal' | 'step';

/** 시안 `bg-amber-500` — 우리 팔레트 밖이지만 이 자리에만 둔다 (Swift RouteMarkerKind.stepFill). */
const STEP_FILL = '#f59e0b';
/** 주황 위 글자 — on-tertiary-fixed (#231B00), 대비 8:1 이상. */
const STEP_LABEL = PixelColor.onTertiaryFixed;

/**
 * START · 번호 · FINISH 표 한 줄.
 * `done` 을 주면 완료색으로 칠하고 체크를 붙인다 (러너 진행 지도).
 */
export function RouteListRow({
  marker,
  text,
  kind,
  done = false,
}: {
  marker: string;
  text: string;
  kind: RouteMarkerKind;
  done?: boolean;
}) {
  const fill = done ? PixelColor.done : kind === 'terminal' ? PixelColor.primary : STEP_FILL;
  const label = done ? PixelColor.onDone : kind === 'terminal' ? PixelColor.onPrimary : STEP_LABEL;
  return (
    <div
      className="px-border"
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: PixelSpacing.m,
        padding: PixelSpacing.m,
        background: PixelColor.surface,
        width: '100%',
      }}
    >
      <span
        className="px-border px-shadow-small"
        style={{
          ...PixelFont.labelSmall,
          color: label,
          background: fill,
          padding: `2px ${PixelSpacing.s}px`,
          minWidth: kind === 'step' ? 20 + PixelSpacing.s * 2 : undefined,
          textAlign: 'center',
          flex: 'none',
        }}
      >
        {marker}
      </span>
      <span style={{ ...PixelFont.bodySmall, color: PixelColor.ink, flex: '1 1 auto', minWidth: 0 }}>{text || '—'}</span>
      {done && <Icon name="check" size={18} color={PixelColor.primary} />}
    </div>
  );
}
