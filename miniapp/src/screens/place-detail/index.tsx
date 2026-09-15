/**
 * 장소 상세 — 원본: Views/PlaceDetailView.swift (+ PlaceInfoSections.swift, Components/GoogleMapPreview.swift)
 * 라우트: `/place?name=&lat=&lng=` (탭바 숨김). 받는 값: usePlaceDetailParams() → { name, lat, lng } | null
 *
 * **읽는 것과 이용하는 것을 두 탭으로 가른다** (2026-09-10 조익준님 결정).
 *
 *     [대표 사진]
 *     이름 · 주소 · 전화
 *     [소개글] [장소 정보]        ← 기본은 소개글
 *
 * 소개글은 여행 전에 읽고, 지도·화장실·주차·무장애는 현장에서 찾는 정보라 쓰이는 때가
 * 다르다. KTO 에 소개할 거리(사진·소개글)가 없으면 소개글 탭을 아예 두지 않는다 —
 * 빈 탭에 「없어요」를 띄우는 것보다 있는 것만 보여주는 게 낫다.
 *
 * 이 화면의 사진·개요·주소·이용정보·무장애 정보는 한국관광공사(KTO) OpenAPI 에서 온다
 * (서버 `GET /place/detail`). 좌표는 **관광지 좌표**만 서버로 보낸다.
 */
import { useEffect, useState, type KeyboardEvent } from 'react';
import {
  facilityDistanceText,
  hasIntroduction,
  PlaceAPI,
  type NearbyFacility,
  type PlaceDetail,
  type PlaceNearby,
} from '../../api';
import { usePlaceDetailParams, type PlaceRef } from '../../app/routes';
import { googleMapsDirectionsURL, openExternalURL } from '../../lib/external';
import { useResource } from '../../lib/resource';
import {
  Icon,
  MapView,
  PixelColor,
  PixelFont,
  PixelPlaceholderScene,
  PixelSectionHeader,
  PixelStyledButton,
  type IconName,
} from '../../ui';
import { hasKTOData, KTO_ATTRIBUTION, sourceLines, usageRows } from './infoText';
import { PhotoViewer } from './PhotoViewer';
import { PlaceAccessibilitySection, PlaceUsageSection } from './sections';
import './place-detail.css';

type DetailTab = 'intro' | 'info';

export function PlaceDetailScreen() {
  const place = usePlaceDetailParams();

  const detailState = useResource<PlaceDetail>(
    place ? `place:${place.name}:${place.lat}:${place.lng}` : null,
    () => PlaceAPI.detail(place!.name, place!.lat, place!.lng),
  );
  // 주변 화장실·정류장. **관광지 좌표**로 묻는다 — 사용자 위치를 넘기지 않는다.
  // 실패하면 구역을 통째로 뺀다 (Swift `try?`).
  const nearbyState = useResource<PlaceNearby>(place ? `nearby:${place.lat}:${place.lng}` : null, () =>
    PlaceAPI.nearby(place!.lat, place!.lng),
  );

  const detail = detailState.data;
  const nearby = nearbyState.data;

  // 이전에 실패한 기록이 캐시에 남아 있으면 다시 들어올 때 곧바로 다시 부른다(Swift `.task`).
  // 그 요청이 시작되기 전 한 순간 「불러오지 못했어요」가 비치지 않게, 이번에 한 번이라도
  // 부르기 시작했는지를 본다.
  const [tried, setTried] = useState(false);
  useEffect(() => {
    if (detailState.loading) setTried(true);
  }, [detailState.loading]);
  const failed = !place || (!detail && !!detailState.error && !detailState.loading && tried);

  const [tab, setTab] = useState<DetailTab>('intro');
  /** 전체 화면으로 보고 있는 사진의 번호. null 이면 닫힌 상태. */
  const [viewerIndex, setViewerIndex] = useState<number | null>(null);

  const images = detail?.images ?? [];
  const showsIntro = detail ? hasIntroduction(detail) : false;

  return (
    <div className="px-screen plc-screen">
      <Hero images={images} onOpen={() => setViewerIndex(0)} />
      <TitleBlock name={place?.name ?? ''} detail={detail} />

      {detail ? (
        <>
          {showsIntro && <TabPicker tab={tab} onChange={setTab} />}
          {showsIntro && tab === 'intro' ? (
            <>
              <IntroTab detail={detail} onOpenPhoto={setViewerIndex} />
              {hasKTOData(detail) && <KtoAttribution />}
            </>
          ) : (
            // 장소 정보 탭은 자기 안의 출처 구역으로 맨 아래를 맺는다 —
            // 여기서 다시 KtoAttribution 을 붙이면 출처가 두 번 나온다.
            place && <InfoTab place={place} detail={detail} nearby={nearby} />
          )}
        </>
      ) : failed ? (
        <FailedView />
      ) : (
        <SkeletonView />
      )}

      {viewerIndex !== null && images.length > 0 && (
        <PhotoViewer images={images} start={viewerIndex} onClose={() => setViewerIndex(null)} />
      )}
    </div>
  );
}

// ═══════════════════════════════ Hero ═══════════════════════════════

/** 대표 사진 한 장. KTO 사진이 없거나 못 불러오면 놀멍봅서 기본 그림. 누르면 전체 화면. */
function Hero({ images, onOpen }: { images: string[]; onOpen: () => void }) {
  const first = images[0];
  const [loadedUrl, setLoadedUrl] = useState<string | null>(null);
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  const showPhoto = !!first && failedUrl !== first;

  const body = (
    <>
      <PlaceholderPhoto />
      {showPhoto && (
        <img
          src={first}
          alt=""
          referrerPolicy="no-referrer"
          className="plc-hero__img"
          style={{ opacity: loadedUrl === first ? 1 : 0 }}
          onLoad={() => setLoadedUrl(first)}
          onError={() => setFailedUrl(first)}
        />
      )}
    </>
  );

  if (images.length === 0) return <div className="plc-hero">{body}</div>;
  return (
    <button type="button" className="plc-hero px-reset-button" onClick={onOpen} aria-label="사진 크게 보기">
      {body}
    </button>
  );
}

/**
 * KTO 에 사진이 없거나 못 불러왔을 때 까는 **놀멍봅서 기본 그림** (2026-09-10 조익준님 결정).
 * 코스 카드가 쓰는 것과 같은 장면이다. 「사진을 못 불러왔다」로 읽히는 회색 아이콘 대신
 * 그림이 깔려 있으면 그 자체로 화면이 완성돼 보인다.
 */
function PlaceholderPhoto() {
  return (
    <span className="plc-hero__placeholder" style={{ background: PixelColor.secondaryContainer }}>
      <PixelPlaceholderScene />
    </span>
  );
}

// ═══════════════════════════════ Title ═══════════════════════════════

/**
 * 이름, 주소, 전화. iOS 는 KTO 주소가 없으면 좌표로 기기 안에서 찾은 주소(CLGeocoder)를 쓰는데,
 * 웹에는 그런 기기 기능이 없어 KTO 주소만 쓴다.
 */
function TitleBlock({ name, detail }: { name: string; detail: PlaceDetail | undefined }) {
  const address = detail?.address ?? '';
  const tel = detail?.tel ?? '';
  return (
    <div className="plc-title">
      <h1 className="plc-h" style={{ ...PixelFont.sectionTitle, color: PixelColor.ink }}>
        {name}
      </h1>
      {address.length > 0 && <InfoRow icon="mapPin" text={address} />}
      {tel.length > 0 && <InfoRow icon="phone" text={tel} />}
    </div>
  );
}

function InfoRow({ icon, text }: { icon: IconName; text: string }) {
  return (
    <div className="plc-info-row">
      <Icon name={icon} size={20} color={PixelColor.inkWeak} />
      <span style={{ ...PixelFont.body, color: PixelColor.ink }}>{text}</span>
    </div>
  );
}

// ═══════════════════════════════ Tabs ═══════════════════════════════

/** 고른 탭은 잉크로 채우고, 나머지는 흰 바탕. 둘이 붙어 있어 한 벌로 읽힌다. */
function TabPicker({ tab, onChange }: { tab: DetailTab; onChange: (t: DetailTab) => void }) {
  const button = (title: string, value: DetailTab) => {
    const selected = tab === value;
    return (
      <button
        type="button"
        role="tab"
        aria-selected={selected}
        className="plc-tab px-reset-button px-border"
        style={{
          ...PixelFont.label,
          color: selected ? PixelColor.surface : PixelColor.inkWeak,
          background: selected ? PixelColor.ink : PixelColor.surface,
        }}
        onClick={() => onChange(value)}
      >
        {title}
      </button>
    );
  };
  return (
    <div className="plc-tabs" role="tablist">
      {button('소개글', 'intro')}
      {button('장소 정보', 'info')}
    </div>
  );
}

// ═══════════════════════════════ 소개글 탭 ═══════════════════════════════

function IntroTab({ detail, onOpenPhoto }: { detail: PlaceDetail; onOpenPhoto: (index: number) => void }) {
  return (
    <>
      {detail.images.length > 1 && <PhotoStrip images={detail.images} onOpen={onOpenPhoto} />}
      {detail.overview.length > 0 && (
        <p
          className="plc-p plc-pre plc-overview"
          style={{ ...PixelFont.body, color: PixelColor.ink, lineHeight: 'calc(16px * var(--px-line) + 5px)' }}
        >
          {detail.overview}
        </p>
      )}
    </>
  );
}

/** 사진 여러 장을 가로로 넘겨 본다. 첫 장은 위 대표 사진이 이미 보여주고 있어 그다음 장부터 둔다. */
function PhotoStrip({ images, onOpen }: { images: string[]; onOpen: (index: number) => void }) {
  return (
    <div className="plc-strip">
      <div className="plc-strip__row">
        {images.slice(1).map((url, offset) => (
          // slice(1) 로 한 장 밀렸으니 전체 목록 번호는 +1.
          <StripPhoto key={`${offset}-${url}`} url={url} onClick={() => onOpen(offset + 1)} label={`사진 ${offset + 2}`} />
        ))}
      </div>
    </div>
  );
}

function StripPhoto({ url, onClick, label }: { url: string; onClick: () => void; label: string }) {
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  return (
    <button
      type="button"
      className="plc-strip__photo px-reset-button px-border"
      style={{ background: PixelColor.surfaceMid }}
      onClick={onClick}
      aria-label={label}
    >
      {!failed && (
        <img
          src={url}
          alt=""
          loading="lazy"
          referrerPolicy="no-referrer"
          style={{ opacity: loaded ? 1 : 0 }}
          onLoad={() => setLoaded(true)}
          onError={() => setFailed(true)}
        />
      )}
    </button>
  );
}

/**
 * 이 화면의 사진·개요·주소가 KTO OpenAPI 에서 온다. **소개글 탭 전용** — 장소 정보 탭은
 * `SourcesSection` 을 따로 쓴다.
 *
 * ⚠️ 공지가 지정한 유일한 형식이다. 텍스트만 허용되고 공사 CI/BI 로고는 금지다.
 * KTO 개요 본문에 이미 「(출처 : ○○ 홈페이지)」가 들어 있는 장소가 있어, 그것과
 * 섞이지 않도록 **화면 맨 아래**에 따로 둔다.
 */
function KtoAttribution() {
  return (
    <p className="plc-p plc-attribution" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
      {KTO_ATTRIBUTION}
    </p>
  );
}

// ═══════════════════════════════ 장소 정보 탭 ═══════════════════════════════

function InfoTab({ place, detail, nearby }: { place: PlaceRef; detail: PlaceDetail; nearby: PlaceNearby | undefined }) {
  // 소개글 탭이 없을 때 「한국관광공사에 등록된 소개가 없는 곳이에요」를 띄우던 줄은 뺐다
  // (2026-09-10 조익준님 결정). 없는 것을 알리는 말보다 있는 정보를 바로 보여주는 게 낫다.
  const usage = usageRows(detail);
  return (
    <>
      <MapBlock place={place} />
      {usage.length > 0 && <PlaceUsageSection rows={usage} />}
      {detail.accessibility.length > 0 && (
        // KTO 무장애 여행정보. 장애인 주차·화장실·휠체어 대여처럼 현장에서
        // 미리 알아야 움직일 수 있는 것들이다.
        <PlaceAccessibilitySection rows={detail.accessibility} />
      )}
      {nearby && (nearby.toilets.length > 0 || nearby.busStops.length > 0) && (
        <NearbySection place={place} nearby={nearby} />
      )}
      {/* 이 탭에서 쓰인 출처를 전부 모아 맨 아래 한 번만 (2026-09-10 조익준님 결정). */}
      <SourcesSection lines={sourceLines(detail, nearby)} />
    </>
  );
}

/**
 * 길찾기. 주변 시설은 걸어가는 거리라 도보로, 관광지 자체는 차로 길을 찾는다.
 * iOS 는 구글맵 앱(comgooglemaps://)을 먼저 시도하지만 웹은 설치 여부를 알 수 없어
 * 구글맵 웹 길찾기 주소만 연다.
 */
function openInMaps(place: PlaceRef, lat: number, lng: number) {
  const walking = lat !== place.lat || lng !== place.lng;
  void openExternalURL(googleMapsDirectionsURL(lat, lng, walking ? 'walking' : 'driving'));
}

/** GoogleMapPreview — 핀 하나 · 줌 15 · 손으로 못 움직임. 누르면 길찾기. */
function MapBlock({ place }: { place: PlaceRef }) {
  const open = () => openInMaps(place, place.lat, place.lng);
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      open();
    }
  };
  const position = { lat: place.lat, lng: place.lng };
  return (
    <div className="plc-map-block">
      <div
        className="plc-map px-border"
        role="button"
        tabIndex={0}
        aria-label={`${place.name} 지도 — 눌러서 길찾기`}
        onClick={open}
        onKeyDown={onKeyDown}
      >
        <MapView
          height={150}
          interactive={false}
          camera={{ kind: 'center', center: position, zoom: 15 }}
          markers={[{ id: 'place', kind: 'place', position, title: place.name }]}
          ariaLabel={`${place.name} 지도`}
        />
      </div>
      <PixelStyledButton kind="primary" style={{ width: '100%' }} onClick={open}>
        길찾기
      </PixelStyledButton>
    </div>
  );
}

// ═══════════════════════════════ 주변 시설 ═══════════════════════════════

/**
 * 관광지 주변 1km 의 공중화장실과 버스정류장. 줄을 누르면 구글맵에서 그 자리로 길을 찾는다.
 *
 * 화장실은 **제주시 관할만** 있다 — 서귀포시는 공공데이터포털에 API 가 없다.
 * 그래서 없는 쪽은 묶음째 뺀다. 「없음」이라고 적으면 서귀포에 화장실이 없다는 말로 읽힌다.
 */
function NearbySection({ place, nearby }: { place: PlaceRef; nearby: PlaceNearby }) {
  return (
    <section className="plc-section">
      {/* 제목·밑줄은 잉크, 아이콘만 파랑 — 같은 탭의 이용 정보·무장애 정보와 맞춘다. */}
      <PixelSectionHeader title="주변 시설" icon="mapPin" iconColor={PixelColor.secondary} />
      {nearby.toilets.length > 0 && (
        <FacilityGroup
          place={place}
          title="공중화장실"
          rows={nearby.toilets}
          icon="wc"
          tint={PixelColor.secondary}
          subtitle={(row) => {
            const bits = [facilityDistanceText(row)];
            if (row.openTime) bits.push(row.openTime);
            if (row.accessible === true) bits.push('장애인용');
            return bits.join(' · ');
          }}
        />
      )}
      {nearby.busStops.length > 0 && (
        <FacilityGroup
          place={place}
          title="버스정류장"
          rows={nearby.busStops}
          icon="bus"
          tint={PixelColor.primary}
          subtitle={(row) => facilityDistanceText(row)}
        />
      )}
    </section>
  );
}

/**
 * 줄마다 잉크 테두리·그림자를 가진 낱장 카드 (2026-09-10 조익준님 결정, 시안 C).
 * 아이콘은 시설 종류를 알려주는 색칠된 사각 배지에 — 화장실은 파랑, 정류장은 초록.
 */
function FacilityGroup({
  place,
  title,
  rows,
  icon,
  tint,
  subtitle,
}: {
  place: PlaceRef;
  title: string;
  rows: NearbyFacility[];
  icon: IconName;
  tint: string;
  subtitle: (row: NearbyFacility) => string;
}) {
  return (
    <div className="plc-facility-group">
      <h3 className="plc-h" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
        {title}
      </h3>
      {rows.map((row, i) => (
        <button
          key={`${i}-${row.name}`}
          type="button"
          className="plc-facility px-reset-button px-border px-shadow-small"
          onClick={() => openInMaps(place, row.lat, row.lng)}
        >
          <span className="plc-facility__badge">
            {/* tint.opacity(0.14) — 같은 색 층을 14% 로 깐다 */}
            <span className="plc-facility__badge-fill" style={{ background: tint }} />
            <Icon name={icon} size={20} color={tint} style={{ position: 'relative' }} />
          </span>
          <span className="plc-facility__text">
            <span style={{ ...PixelFont.body, color: PixelColor.ink }}>{row.name}</span>
            <span style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>{subtitle(row)}</span>
          </span>
          <Icon name="forward" size={18} color={PixelColor.inkWeak} />
        </button>
      ))}
    </div>
  );
}

// ═══════════════════════════════ 출처 ═══════════════════════════════

/** 장소 정보 탭의 출처 — 실제로 쓴 것만 한 구역에. KTO 문구는 공지가 지정한 형식 그대로. */
function SourcesSection({ lines }: { lines: string[] }) {
  if (lines.length === 0) return null;
  return (
    <div className="plc-sources">
      <div style={{ height: 2, background: PixelColor.ink }} />
      <div className="plc-sources__body">
        <p className="plc-p plc-sources__title" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
          출처
        </p>
        {lines.map((line) => (
          <p key={line} className="plc-p" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
            {line}
          </p>
        ))}
      </div>
    </div>
  );
}

// ═══════════════════════════════ Skeleton / Failed ═══════════════════════════════

function SkeletonView() {
  return (
    <div className="plc-skeleton" aria-busy="true" aria-label="불러오는 중">
      {[0, 1, 2].map((i) => (
        <div key={i} className="plc-skeleton__bar" style={{ background: PixelColor.inkWeak }} />
      ))}
    </div>
  );
}

function FailedView() {
  return (
    <div className="plc-failed" role="alert">
      <Icon name="warn" size={40} color={PixelColor.locked} />
      <p className="plc-p" style={{ ...PixelFont.body, color: PixelColor.inkWeak, textAlign: 'center' }}>
        장소 정보를 불러오지 못했어요.
      </p>
    </div>
  );
}
