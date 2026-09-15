/**
 * ⚠️ 임시 구현 — Leaflet + OpenStreetMap 타일.
 *
 * 앱인토스 안에서 어떤 웹 지도를 쓸 수 있는지(허용 도메인·키) 아직 정해지지 않았다.
 * 정해지면 **이 파일 하나만** 바꾼다. 화면들은 `types.ts` 의 `MapViewProps` 만 알고 있으므로
 * 같은 props 를 받는 새 구현으로 갈아 끼우면 된다. (OSM 타일은 대량 트래픽 용도가 아니다 —
 * 출시 전에 반드시 교체한다.)
 *
 * 동작 약속 (Swift 와 같다)
 *   - 마커는 id 로 기억해 바뀐 것만 다시 그린다 — 매번 지우면 선택 상태가 흔들린다.
 *   - 카메라는 `cameraKey` 가 바뀔 때만 다시 맞춘다 — 사용자가 옮긴 지도를 되돌리지 않는다.
 *   - 크기가 0 일 때 맞추면 엉뚱한 배율이 되므로, 크기가 정해지면 그때 맞춘다.
 *   - 지도 영역 안에서만 두 손가락 확대가 된다 (페이지 자체 확대는 막혀 있다).
 */
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useEffect, useLayoutEffect, useRef } from 'react';
import './map.css';
import type { LatLngBounds, MapCamera, MapMarker, MapViewProps } from './types';

export type { MapViewProps, MapMarker, MapPolyline, MapCamera, MapViewState } from './types';

const TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
/**
 * 출처는 **링크 없는 글자**로 둔다. Leaflet 은 이 HTML 을 그대로 넣을 뿐이라 `<a>` 를 두면 누르는 순간
 * 토스 WebView 자체가 openstreetmap.org 로 넘어간다 — 미니앱 화면이 사라지고 토스 도메인 밖 사이트가
 * 앱 안에 그려진다(비게임 출시 가이드 「보안 및 안정성」 위반). 지도 공급자를 바꿀 때도 같은 규칙이다.
 */
const TILE_ATTRIBUTION = '&copy; OpenStreetMap contributors';

// ── 마커 그림 ───────────────────────────────────────────────────────────

/** `X` 잉크 테두리 · `o` 채움 · `+` 가운데 점(플레이 가능 표시) · `.` 투명 — PlayPinMap.swift 그대로 */
const ACTIVE_GRID = ['.XXXXXX.', 'XooooooX', 'Xo+  +oX', 'Xo+++ oX', 'Xoo++ oX', '.XooooX.', '..XooX..', '...XX...'];
/** 준비 중은 **속이 비어 있다** — 색을 못 봐도 구분된다. */
const PREPARING_GRID = ['.XXXXXX.', 'X......X', 'X......X', 'X......X', 'X......X', '.X....X.', '..X..X..', '...XX...'];

function pinSvg(status: 'active' | 'preparing', selected: boolean): { html: string; w: number; h: number } {
  const grid = status === 'active' ? ACTIVE_GRID : PREPARING_GRID;
  // 플레이 가능한 곳을 더 크게. 선택되면 한 칸 더.
  const unit = (status === 'active' ? 3 : 2) + (selected ? 1 : 0);
  const fill = selected ? 'var(--px-accent)' : status === 'active' ? 'var(--px-primary)' : 'var(--px-surface)';
  const ink = status === 'active' ? 'var(--px-ink)' : 'var(--px-locked)';
  const rects: string[] = [];
  grid.forEach((row, y) => {
    [...row].forEach((ch, x) => {
      if (ch === '.') return;
      // 격자의 ' ' 는 채움색이다(Swift: default → fill).
      const color = ch === 'X' ? ink : ch === '+' ? 'var(--px-surface)' : fill;
      rects.push(`<rect x="${x * unit}" y="${y * unit}" width="${unit}" height="${unit}" style="fill:${color}"/>`);
    });
  });
  const w = grid[0].length * unit;
  const h = grid.length * unit;
  return {
    html: `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges" aria-hidden="true">${rects.join('')}</svg>`,
    w,
    h,
  };
}

/** Leaflet 은 선 색을 SVG 속성으로 넣는다 — 속성에서는 var() 가 안 먹으므로 실제 색으로 풀어 준다. */
function resolveColor(color: string): string {
  const m = /^var\((--[\w-]+)\)$/.exec(color.trim());
  if (!m) return color;
  const v = getComputedStyle(document.documentElement).getPropertyValue(m[1]).trim();
  return v || '#006d39';
}

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string);

/**
 * 장소 핀 — GoogleMapPreview 의 `GMSMarker.markerImage(with: PixelColor.primary)` 자리.
 * 구글 기본 마커(물방울)를 주색으로 칠하고 가운데에 짙은 점. 꼭짓점이 좌표에 닿는다.
 */
const PLACE_W = 27;
const PLACE_H = 43;
const PLACE_SVG =
  `<svg width="${PLACE_W}" height="${PLACE_H}" viewBox="0 0 27 43" aria-hidden="true">` +
  '<path d="M13.5 1C6.6 1 1 6.6 1 13.5c0 9.4 12.5 28 12.5 28S26 22.9 26 13.5C26 6.6 20.4 1 13.5 1z" ' +
  'style="fill:var(--px-primary);stroke:var(--px-on-primary-container);stroke-width:1.5"/>' +
  '<circle cx="13.5" cy="13.5" r="4.5" style="fill:var(--px-on-primary-container)"/></svg>';

function markerIcon(m: MapMarker): L.DivIcon {
  if (m.kind === 'pin') {
    const { html, w, h } = pinSvg(m.status, !!m.selected);
    // 핀 꼭짓점(격자 맨 아래 가운데)이 좌표에 닿는다. 누르는 자리는 map.css 가 44px 로 넓힌다.
    return L.divIcon({ html, className: 'px-map-marker px-map-marker--pin', iconSize: [w, h], iconAnchor: [w / 2, h] });
  }
  if (m.kind === 'place') {
    return L.divIcon({
      html: PLACE_SVG,
      className: 'px-map-marker',
      iconSize: [PLACE_W, PLACE_H],
      iconAnchor: [PLACE_W / 2, PLACE_H - 1],
    });
  }
  const size = m.size ?? 28;
  const font = m.font === 'label' ? 'px-t-label' : 'px-t-label-small';
  return L.divIcon({
    html: `<div class="px-map-number ${font}" style="width:${size}px;height:${size}px">${escapeHtml(m.label)}</div>`,
    className: 'px-map-marker',
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2], // 번호 한가운데가 그 좌표다
  });
}

/**
 * 번호 아래 이름표. 번호와 **다른 마커**로 따로 그린다 — 한 마커 안에 두면 이웃 번호 사각형이
 * 이름을 덮는다(Leaflet 은 마커마다 층이 따로다). 이름표는 모든 번호 아래 층에 깐다.
 */
function captionIcon(text: string, squareSize: number): L.DivIcon {
  return L.divIcon({
    html: `<div class="px-map-caption px-t-label-small">${escapeHtml(text)}</div>`,
    className: 'px-map-marker',
    iconSize: [0, 0],
    // 좌표(번호 한가운데)에서 사각형 절반 + 2px 아래가 이름표 윗변
    iconAnchor: [0, -(squareSize / 2 + 2)],
  });
}
const CAPTION_Z = -100_000;

const markerSignature = (m: MapMarker) =>
  m.kind === 'pin'
    ? `pin|${m.status}|${m.selected ? 1 : 0}|${m.position.lat},${m.position.lng}`
    : m.kind === 'place'
      ? `place|${m.position.lat},${m.position.lng}`
      : `num|${m.label}|${m.size ?? 28}|${m.font ?? 'labelSmall'}|${m.caption ?? ''}|${m.position.lat},${m.position.lng}`;

const USER_ICON = L.divIcon({
  html: '<div class="px-map-user"></div>',
  className: 'px-map-marker',
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});

// ── 카메라 ─────────────────────────────────────────────────────────────

const M_PER_DEG_LAT = 111_320;

/** 좁은 사각형을 가운데 두고 minSpanMeters 까지 넓힌다 (Swift: 반경 800m 확보). */
function widen(b: LatLngBounds, minSpanMeters?: number): LatLngBounds {
  if (!minSpanMeters) return b;
  const cLat = (b.south + b.north) / 2;
  const cLng = (b.west + b.east) / 2;
  const minLat = minSpanMeters / M_PER_DEG_LAT;
  const minLng = minSpanMeters / (M_PER_DEG_LAT * Math.cos((cLat * Math.PI) / 180));
  const hLat = Math.max(b.north - b.south, minLat) / 2;
  const hLng = Math.max(b.east - b.west, minLng) / 2;
  return { south: cLat - hLat, north: cLat + hLat, west: cLng - hLng, east: cLng + hLng };
}

function applyCamera(map: L.Map, camera: MapCamera, animate: boolean) {
  if (camera.kind === 'center') {
    map.setView([camera.center.lat, camera.center.lng], camera.zoom, { animate });
    return;
  }
  const b = widen(camera.bounds, camera.minSpanMeters);
  const p = camera.padding ?? 0;
  const pad = typeof p === 'number' ? { top: p, right: p, bottom: p, left: p } : p;
  map.fitBounds(
    [
      [b.south, b.west],
      [b.north, b.east],
    ],
    {
      paddingTopLeft: [pad.left, pad.top],
      paddingBottomRight: [pad.right, pad.bottom],
      maxZoom: camera.maxZoom ?? 18,
      animate,
    },
  );
}

// ── 부품 ───────────────────────────────────────────────────────────────

export function MapView({
  markers = [],
  polylines = [],
  camera,
  cameraKey,
  animateCamera = false,
  userLocation,
  interactive = true,
  onMarkerClick,
  onMapClick,
  onCameraChange,
  height,
  className,
  style,
  ariaLabel = '지도',
}: MapViewProps) {
  const elRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markerLayer = useRef(new Map<string, { marker: L.Marker; sig: string }>());
  const captionLayer = useRef(new Map<string, { marker: L.Marker; sig: string }>());
  const lineLayer = useRef<L.LayerGroup | null>(null);
  const userMarker = useRef<L.Marker | null>(null);

  // 최신 콜백·카메라를 이펙트 밖에서 읽는다 (지도를 다시 만들지 않으려고).
  const onMarkerClickRef = useRef(onMarkerClick);
  const onMapClickRef = useRef(onMapClick);
  const onCameraChangeRef = useRef(onCameraChange);
  const cameraRef = useRef(camera);
  useLayoutEffect(() => {
    onMarkerClickRef.current = onMarkerClick;
    onMapClickRef.current = onMapClick;
    onCameraChangeRef.current = onCameraChange;
    cameraRef.current = camera;
  });

  const appliedKey = useRef<string | null>(null);
  const pendingCamera = useRef(false);

  // 지도 만들기 (한 번)
  useEffect(() => {
    const el = elRef.current;
    if (!el) return;
    const map = L.map(el, {
      zoomControl: false,
      attributionControl: true,
      dragging: interactive,
      touchZoom: interactive,
      scrollWheelZoom: interactive,
      doubleClickZoom: interactive,
      boxZoom: false,
      keyboard: interactive,
      zoomSnap: 0.1,
      // 회전·기울임은 Leaflet 에 없다 (Swift 도 껐다).
    });
    map.attributionControl.setPrefix(false);
    L.tileLayer(TILE_URL, { attribution: TILE_ATTRIBUTION, maxZoom: 19 }).addTo(map);
    lineLayer.current = L.layerGroup().addTo(map);
    map.on('click', () => onMapClickRef.current?.());
    map.on('moveend', () => {
      if (pendingCamera.current) return; // 아직 진짜 카메라를 맞추기 전의 임시 위치
      const c = map.getCenter();
      onCameraChangeRef.current?.({ center: { lat: c.lat, lng: c.lng }, zoom: map.getZoom() });
    });
    mapRef.current = map;

    const sized = () => el.clientWidth > 0 && el.clientHeight > 0;
    if (sized()) {
      applyCamera(map, cameraRef.current, false);
    } else {
      // 크기 0 에서 맞추면 엉뚱한 배율 → 일단 제주 가운데를 보여주고 크기가 정해지면 맞춘다.
      // (pending 을 먼저 켠다 — 이 임시 위치를 onCameraChange 로 알리지 않으려고)
      pendingCamera.current = true;
      map.setView([33.38, 126.55], 9);
    }
    appliedKey.current = cameraKey ?? '__initial__';

    const ro = new ResizeObserver(() => {
      map.invalidateSize({ animate: false });
      if (pendingCamera.current && sized()) {
        pendingCamera.current = false;
        applyCamera(map, cameraRef.current, false);
      }
    });
    ro.observe(el);

    const markersNow = markerLayer.current;
    const captionsNow = captionLayer.current;
    return () => {
      ro.disconnect();
      map.remove();
      mapRef.current = null;
      markersNow.clear();
      captionsNow.clear();
      userMarker.current = null;
      lineLayer.current = null;
    };
    // interactive·cameraKey 는 처음 값으로 만든다 — interactive 를 바꿔야 하면 key 로 새로 그린다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 카메라 — cameraKey 가 바뀔 때만
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const key = cameraKey ?? '__initial__';
    if (appliedKey.current === key) return;
    appliedKey.current = key;
    const el = elRef.current;
    if (el && el.clientWidth > 0 && el.clientHeight > 0) applyCamera(map, cameraRef.current, animateCamera);
    else pendingCamera.current = true;
  }, [cameraKey, animateCamera]);

  // 마커 동기화 — id 로 기억하고 바뀐 것만 다시 그린다
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const layer = markerLayer.current;
    const wanted = new Set(markers.map((m) => m.id));
    for (const [id, entry] of layer) {
      if (!wanted.has(id)) {
        entry.marker.remove();
        layer.delete(id);
      }
    }
    for (const m of markers) {
      const sig = markerSignature(m);
      const existing = layer.get(m.id);
      const selected = m.kind === 'pin' && !!m.selected;
      if (existing) {
        if (existing.sig !== sig) {
          existing.marker.setLatLng([m.position.lat, m.position.lng]);
          existing.marker.setIcon(markerIcon(m));
          existing.marker.setZIndexOffset(selected ? 1000 : 0);
          existing.sig = sig;
        }
        continue;
      }
      const marker = L.marker([m.position.lat, m.position.lng], {
        icon: markerIcon(m),
        keyboard: false,
        title: m.title ?? '',
        alt: m.title ?? '',
        zIndexOffset: selected ? 1000 : 0,
        interactive: true,
        bubblingMouseEvents: false,
      });
      marker.on('click', () => onMarkerClickRef.current?.(m.id));
      marker.addTo(map);
      layer.set(m.id, { marker, sig });
    }

    // 번호 아래 이름표 (caption)
    const captions = captionLayer.current;
    const wantedCaptions = new Map<string, { text: string; size: number; lat: number; lng: number }>();
    for (const m of markers) {
      if (m.kind === 'number' && m.caption) {
        wantedCaptions.set(m.id, { text: m.caption, size: m.size ?? 28, lat: m.position.lat, lng: m.position.lng });
      }
    }
    for (const [id, entry] of captions) {
      if (!wantedCaptions.has(id)) {
        entry.marker.remove();
        captions.delete(id);
      }
    }
    for (const [id, c] of wantedCaptions) {
      const sig = `${c.text}|${c.size}|${c.lat},${c.lng}`;
      const existing = captions.get(id);
      if (existing) {
        if (existing.sig !== sig) {
          existing.marker.setLatLng([c.lat, c.lng]);
          existing.marker.setIcon(captionIcon(c.text, c.size));
          existing.sig = sig;
        }
        continue;
      }
      const marker = L.marker([c.lat, c.lng], {
        icon: captionIcon(c.text, c.size),
        keyboard: false,
        interactive: false,
        zIndexOffset: CAPTION_Z,
      }).addTo(map);
      captions.set(id, { marker, sig });
    }
  }, [markers]);

  // 선
  useEffect(() => {
    const group = lineLayer.current;
    if (!group) return;
    group.clearLayers();
    for (const line of polylines) {
      if (line.path.length < 2) continue;
      L.polyline(
        line.path.map((p) => [p.lat, p.lng] as [number, number]),
        {
          color: resolveColor(line.color ?? 'var(--px-primary)'),
          weight: line.width ?? 3.5,
          opacity: line.opacity ?? 0.85,
          dashArray: line.dashArray,
          interactive: false,
          lineCap: 'butt',
        },
      ).addTo(group);
    }
  }, [polylines]);

  // 내 위치
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (!userLocation) {
      userMarker.current?.remove();
      userMarker.current = null;
      return;
    }
    const ll: [number, number] = [userLocation.lat, userLocation.lng];
    if (userMarker.current) userMarker.current.setLatLng(ll);
    else userMarker.current = L.marker(ll, { icon: USER_ICON, interactive: false, keyboard: false, zIndexOffset: 2000 }).addTo(map);
    // 좌표 숫자가 같으면 객체가 새로 와도 다시 그리지 않는다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userLocation?.lat, userLocation?.lng]);

  return (
    <div
      ref={elRef}
      className={`px-map${interactive ? '' : ' px-map--static'}${className ? ` ${className}` : ''}`}
      style={{ height: height ?? '100%', ...style }}
      role="region"
      aria-label={ariaLabel}
    />
  );
}
