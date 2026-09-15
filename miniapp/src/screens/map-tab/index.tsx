/**
 * 지도 탭 — 원본: Views/MapTabView.swift (+ Components/PlayPinMap.swift)
 * 라우트: `/map` (탭 뿌리, 탭바 보임)
 *
 * **제주 어디에서 PLAY 할 수 있고, 앞으로 어디에 생기는가**를 보여준다.
 * 무엇이 뜨는지는 서버 `data/places.json` 의 상태가 정한다 —
 * `LIVE` 는 활성 핀, `PLANNED` 는 준비 중 핀, `CANDIDATE` 는 안 뜬다.
 * 서버가 `/map/pins` 에서 CANDIDATE 를 이미 뺀다. 여기서도 `active`/`preparing` 이 아닌 핀은 한 번 더 거른다.
 *
 * 화면 구성 (Swift 그대로, 상단바 없음 — 퀘스트·코스 탭과 같다)
 *   머리말 카드 → 핀 뜻풀이 → 권역 칩 → 지도(+ 핀을 누르면 아래에서 올라오는 미니 카드)
 *
 * 이동
 *   활성 핀 카드 「PLAY 보기」     → nav.toPlayDetail(pin.play.id)
 *   준비 중 핀 카드 「장소 정보 보기」 → nav.toPlaceDetail({ name, lat, lng })
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { PlayAPI, distanceText, durationText, type MapPins, type PlayMapPin } from '../../api';
import { useAppNavigation } from '../../app/routes';
import { JEJU_REGIONS, focusBounds, focusKey, regionColors, WHOLE_ISLAND_ID, type JejuMapFocus } from '../../lib/region';
import { useResource } from '../../lib/resource';
import {
  Icon,
  MapView,
  PixelButton,
  PixelCard,
  PixelChip,
  PixelColor,
  PixelIntroCard,
  type MapCamera,
  type MapMarker,
  type MapViewState,
} from '../../ui';
import './map-tab.css';

// ── 탭 상태 기억 ────────────────────────────────────────────────────────
//
// iOS 는 탭 화면을 살려 둔다 — PLAY 상세에 다녀오거나 다른 탭에 갔다 와도 고른 권역과
// 열어 둔 카드가 그대로다. 웹은 화면이 다시 마운트되므로 앱이 살아 있는 동안만 메모리에 둔다.
// (기기 저장이 아니다 — 앱을 다시 켜면 Swift 처럼 「전체」에서 시작한다.)
const remembered: {
  focus: JejuMapFocus;
  selectedId: string | null;
  /** 손으로 옮겨 둔 지도 위치. 어느 권역에서 옮겼는지(focusKey)와 함께 둔다. */
  view: (MapViewState & { focusKey: string }) | null;
} = {
  focus: { kind: 'wholeIsland' },
  selectedId: null,
  view: null,
};

/** 카드가 올라오고 내려가는 시간 — SwiftUI `.animation(.default)` (map-tab.css 와 같은 값) */
const CARD_ANIMATION_MS = 350;

const sameFocus = (a: JejuMapFocus, b: JejuMapFocus) => focusKey(a) === focusKey(b);

/** 공개 지도에 띄워도 되는 핀만 — `LIVE`(active)·`PLANNED`(preparing). CANDIDATE 는 절대 안 뜬다. */
const isPublicPin = (p: PlayMapPin) => p.status === 'active' || p.status === 'preparing';

export function MapTabScreen() {
  const nav = useAppNavigation();
  const { data, error, loading } = useResource<MapPins>('mapPins', () => PlayAPI.mapPins());

  const pins = useMemo(() => (data?.pins ?? []).filter(isPublicPin), [data]);
  // 숫자는 **서버가 준 값 그대로** 쓴다. 화면에 박아두면 PLAY 가 늘어날 때 조용히 거짓이 된다.
  const activeCount = data?.activeCount ?? 0;
  const preparingCount = data?.preparingCount ?? 0;
  // Swift `vm.isLoading && vm.pins.isEmpty` — 첫 요청이 나가기 전 한 순간도 「불러오는 중」으로 본다.
  const isLoading = loading || (data === undefined && !error);

  const [focus, setFocusState] = useState<JejuMapFocus>(remembered.focus);
  const [selectedId, setSelectedIdState] = useState<string | null>(remembered.selectedId);
  // 되돌아와 다시 그린 카드는 올라오는 움직임 없이 그 자리에 있어야 한다 (iOS 는 화면을 살려 둔다).
  const [instant, setInstant] = useState(remembered.selectedId !== null);

  const setSelectedId = useCallback((id: string | null) => {
    remembered.selectedId = id;
    setInstant(false);
    setSelectedIdState(id);
  }, []);

  const selectFocus = (target: JejuMapFocus) => {
    remembered.focus = target;
    setFocusState(target);
    setSelectedId(null);
  };

  const selectedPin = selectedId ? (pins.find((p) => p.placeId === selectedId) ?? null) : null;

  // 카드가 내려가는 동안에는 마지막 핀을 붙들고 있는다 (.transition(.move(edge: .bottom))).
  const [cardPin, setCardPin] = useState<PlayMapPin | null>(selectedPin);
  if (selectedPin && selectedPin !== cardPin) setCardPin(selectedPin);
  const shownPin = selectedPin ?? cardPin;
  const leaving = !selectedPin && cardPin !== null;
  // 내려가는 움직임(350ms)이 끝나면 카드를 뗀다. animationend 는 화면이 그려지지 않는 동안(백그라운드 등)
  // 오지 않을 수 있어 타이머로 뗀다. 그 사이 다른 핀을 누르면 leaving 이 풀려 타이머가 취소된다.
  useEffect(() => {
    if (!leaving) return;
    const t = window.setTimeout(() => setCardPin(null), CARD_ANIMATION_MS);
    return () => window.clearTimeout(t);
  }, [leaving]);

  const markers = useMemo<MapMarker[]>(
    () =>
      pins.map((p) => ({
        id: p.placeId,
        kind: 'pin' as const,
        status: p.status,
        selected: p.placeId === selectedId,
        position: { lat: p.lat, lng: p.lng },
        title: p.placeName,
      })),
    [pins, selectedId],
  );

  // 다시 그려질 때는 **옮겨 둔 자리**에서 시작한다 (iOS 는 탭 화면을 살려 둬서 지도가 그대로다).
  // 권역 칩을 바꾸면 cameraKey 가 바뀌고, 그때는 저장된 자리가 다른 권역 것이라 그 권역 전체로 맞춘다.
  const key = focusKey(focus);
  const saved = remembered.view && remembered.view.focusKey === key ? remembered.view : null;
  const camera: MapCamera = saved
    ? { kind: 'center', center: saved.center, zoom: saved.zoom }
    : { kind: 'bounds', bounds: focusBounds(focus), padding: 40 };
  const rememberView = useCallback(
    (view: MapViewState) => {
      remembered.view = { ...view, focusKey: key };
    },
    [key],
  );

  const openPin = (pin: PlayMapPin) => {
    if (pin.play) nav.toPlayDetail(pin.play.id);
    else nav.toPlaceDetail({ name: pin.placeName, lat: pin.lat, lng: pin.lng });
  };

  return (
    <div className="px-screen maptab">
      {/* ── 머리말 카드 ──
          지도 탭의 색은 **파랑**이다 — 잉크 블록에는 밝은 파랑, 글자 강조에는 진한 파랑.
          「플레이할까요」가 아니라 「열렸을까요」— 이 지도에는 아직 플레이할 수 없는 준비 중 핀이 같이 뜬다. */}
      <div className="maptab-intro">
        <PixelIntroCard
          icon="mapPin"
          iconColor={PixelColor.secondaryContainer}
          title={
            <>
              제주 어디가 <span style={{ color: PixelColor.secondary }}>열렸을까요</span>
            </>
          }
          message={
            isLoading && pins.length === 0 ? (
              '열린 곳을 불러오는 중이에요'
            ) : (
              // 숫자가 먼저 온다 — 「지금 N곳이 열렸고」가 앞에 서면 지금 할 수 있는 일이 먼저 보인다.
              <>
                지금 <span style={{ color: PixelColor.secondary }}>{activeCount}곳</span>이 열렸고,{' '}
                <span style={{ color: PixelColor.secondary }}>{preparingCount}곳</span>이 곧 열려요
              </>
            )
          }
        />
      </div>

      {/* ── 핀 뜻풀이 ── 색만으로 구분하지 않는다 — 모양(채움/빈칸)도 다르다. */}
      <div className="maptab-legend">
        <LegendItem color={PixelColor.primary} filled text="플레이 가능" />
        <LegendItem color={PixelColor.locked} filled={false} text="준비 중" />
      </div>

      {/* ── 권역 칩 ── 고른 권역은 그 권역의 색 (코스 탭 권역 버튼·코스 카드 배지와 같다). */}
      <div className="maptab-chips">
        <div className="maptab-chips__row" role="group" aria-label="권역">
          <RegionChip
            title="전체"
            colorId={WHOLE_ISLAND_ID}
            on={focus.kind === 'wholeIsland'}
            onPress={() => selectFocus({ kind: 'wholeIsland' })}
          />
          {JEJU_REGIONS.map((region) => {
            const target: JejuMapFocus = { kind: 'region', id: region.id };
            return (
              <RegionChip
                key={region.id}
                title={region.label}
                colorId={region.label}
                on={sameFocus(focus, target)}
                onPress={() => selectFocus(target)}
              />
            );
          })}
        </div>
      </div>

      {/* ── 지도 + 미니 카드 ── */}
      <div className="maptab-map px-border">
        <MapView
          camera={camera}
          // 권역 칩이 바뀌었을 때만 카메라를 옮긴다 — 손으로 끌어놓은 위치를 되돌리지 않는다.
          cameraKey={key}
          animateCamera
          onCameraChange={rememberView}
          markers={markers}
          onMarkerClick={(id) => setSelectedId(id)}
          onMapClick={() => setSelectedId(null)}
          ariaLabel="PLAY 지도"
        />

        {shownPin && (
          <div
            className={`maptab-card-slot${leaving ? ' maptab-card-slot--leaving' : instant ? ' maptab-card-slot--instant' : ''}`}
            aria-hidden={leaving || undefined}
          >
            <PlayMapCard pin={shownPin} onClose={() => setSelectedId(null)} onOpen={() => openPin(shownPin)} />
          </div>
        )}
      </div>
    </div>
  );
}

// ═══════════════════════════════ 범례 ═══════════════════════════════

function LegendItem({ color, filled, text }: { color: string; filled: boolean; text: string }) {
  return (
    <span className="maptab-legend__item">
      <span className="maptab-legend__swatch" style={{ background: filled ? color : PixelColor.surface }} aria-hidden="true" />
      <span className="px-t-label-small">{text}</span>
    </span>
  );
}

// ═══════════════════════════════ 권역 칩 ═══════════════════════════════

function RegionChip({ title, colorId, on, onPress }: { title: string; colorId: string; on: boolean; onPress: () => void }) {
  const c = regionColors(colorId);
  return (
    <button type="button" className="px-reset-button maptab-chip" aria-pressed={on} onClick={onPress}>
      <PixelChip text={title} fill={on ? c.fill : PixelColor.surface} label={on ? c.on : PixelColor.ink} />
    </button>
  );
}

// ═══════════════════════════════ 미니 카드 ═══════════════════════════════

/**
 * 핀을 눌렀을 때 아래에서 올라오는 카드 (Swift `PlayMapCard`).
 * 활성이면 **PLAY 정보**를, 준비 중이면 장소 이름과 「PLAY 준비 중」을 보여준다.
 */
function PlayMapCard({ pin, onClose, onOpen }: { pin: PlayMapPin; onClose: () => void; onOpen: () => void }) {
  const play = pin.play;
  return (
    <PixelCard>
      <div className="maptab-card__body">
        <div className="maptab-card__head">
          <CardThumbnail pin={pin} />
          <div className="maptab-card__text">
            <h2 className="px-t-section-title" style={{ color: PixelColor.ink }}>
              {pin.placeName}
            </h2>
            {play ? (
              <>
                <p className="px-t-body" style={{ color: PixelColor.ink }}>
                  {play.title}
                </p>
                <p className="px-t-label-small" style={{ color: PixelColor.inkWeak }}>
                  {`${durationText(play)} · ${distanceText(play)} · ${play.missionCount} Missions`}
                </p>
              </>
            ) : (
              <PixelChip text="PLAY 준비 중" icon="lock" fill={PixelColor.locked} label={PixelColor.onLocked} />
            )}
          </div>
          <button type="button" className="px-reset-button maptab-card__close" aria-label="닫기" onClick={onClose}>
            <Icon name="close" size={24} color={PixelColor.inkWeak} />
          </button>
        </div>
        <PixelButton title={play ? 'PLAY 보기' : '장소 정보 보기'} kind={play ? 'primary' : 'plain'} onClick={onOpen} />
      </div>
    </PixelCard>
  );
}

/** 72×72 썸네일 — 활성 PLAY 의 사진, 없거나 못 받으면 사진/자물쇠 아이콘. */
function CardThumbnail({ pin }: { pin: PlayMapPin }) {
  const src = pin.play?.thumbnail ?? null;
  return (
    <div className="maptab-card__thumb px-border" aria-hidden="true">
      <Icon name={pin.play ? 'photo' : 'lock'} size={24} color={PixelColor.inkWeak} />
      {src && <ThumbImage key={src} src={src} />}
    </div>
  );
}

/** AsyncImage — 받는 중·실패면 뒤의 아이콘이 보인다. */
function ThumbImage({ src }: { src: string }) {
  const [failed, setFailed] = useState(false);
  if (failed) return null;
  return <img src={src} alt="" decoding="async" referrerPolicy="no-referrer" onError={() => setFailed(true)} />;
}
