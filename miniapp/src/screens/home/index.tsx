/**
 * 퀘스트 탭 (홈) — 원본: Views/HomeView.swift (+ Components/PlayCard.swift)
 * 라우트: `/` (탭 뿌리, 탭바 보임)
 *
 * 게임으로 들어가는 화면. 시안(2026-09-02) 그대로다.
 *
 *     [!] 관광지를 플레이하세요
 *         제주 관광지 하나가 통째로 게임 속 장소가 됩니다…
 *
 *     🗺 수행 가능한 퀘스트
 *     ────────────────────
 *     [퀘스트 카드 × N]
 *
 * 무엇이 뜨는지는 서버 `/map/pins` 가 정한다 — `active` 는 퀘스트 카드, `preparing` 은
 * 준비 중 카드. 그중 `homeVisible` 인 곳만(콘텐츠 제작 착수 전 후보지는 지도에만).
 * 시안에 상단바가 없다 — 토스 네비게이션 바가 위를 맡는다.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import { PlayAPI, type MapPins } from '../../api';
import { useAppNavigation } from '../../app/routes';
import { useResource } from '../../lib/resource';
import { progressLabel, usePlayProgressMap } from '../../stores';
import {
  Icon,
  PixelColor,
  PixelFont,
  PixelIntroCard,
  PixelSectionHeader,
  PixelSpacing,
  PixelSpinner,
  PullToRefreshIndicator,
  usePullToRefresh,
} from '../../ui';
import { PlayCard, PreparingPlaceCard } from './components';
import { homeQuestPins } from './model';
import './home.css';

export function HomeScreen() {
  const nav = useAppNavigation();
  // 지도 탭과 같은 캐시 키 — 한 번 받은 핀을 두 탭이 같이 쓴다.
  // 요청은 화면이 사라져도 끝까지 간다 (Swift `.task` 취소 사고, 2026-09-11).
  const { data, error, loading, reload } = useResource<MapPins>('mapPins', () => PlayAPI.mapPins());
  const progressMap = usePlayProgressMap();
  const pins = useMemo(() => homeQuestPins(data?.pins ?? []), [data]);

  // 진짜로 실패했을 때만 참 (Swift `vm.failed`). 다시 부르는 동안에는 직전 판정을 유지한다 —
  // 실패 안내를 보던 사람이 당겨서 다시 시도해도 안내가 그대로 있고, 끝나면 바뀐다.
  const settledFailed = data === undefined && error != null;
  const [failed, setFailed] = useState(!loading && settledFailed);
  if (!loading && failed !== settledFailed) setFailed(settledFailed);

  // 실패를 삼키지 않고 기록한다 — 「불러오지 못했어요」만 보이면 원인을 알 수 없다.
  useEffect(() => {
    if (error != null) console.warn('[home] map/pins 실패', error);
  }, [error]);

  const rootRef = useRef<HTMLDivElement>(null);
  const ptr = usePullToRefresh(rootRef, reload);

  return (
    <div ref={rootRef} className="px-screen">
      {/* 당겨서 새로고침 표시 (.refreshable) */}
      <PullToRefreshIndicator {...ptr} />

      <div className="home-content">
        <IntroCard />

        <section className="home-quests" aria-busy={loading}>
          {/* 시안: 아이콘만 초록, 제목은 잉크, 밑줄은 잉크 4px. */}
          <PixelSectionHeader
            title="수행 가능한 퀘스트"
            icon="map"
            iconColor={PixelColor.primaryContainer}
            underline={PixelSpacing.borderHeavy}
          />

          {pins.length === 0 && !failed ? (
            <LoadingRow />
          ) : pins.length === 0 ? (
            <EmptyRow />
          ) : (
            pins.map((pin) =>
              pin.play ? (
                <PlayCard
                  key={pin.placeId}
                  play={pin.play}
                  progressText={progressLabel(progressMap[pin.play.id])}
                  onAction={() => nav.toPlayDetail(pin.play!.id)}
                />
              ) : (
                <PreparingPlaceCard
                  key={pin.placeId}
                  placeName={pin.placeName}
                  coverName={pin.placeKey}
                  thumbnail={pin.thumbnail}
                  onAction={() => nav.toPlaceDetail({ name: pin.placeName, lat: pin.lat, lng: pin.lng })}
                />
              ),
            )
          )}
        </section>
      </div>
    </div>
  );
}

// ═══════════════════════════════ 인트로 ═══════════════════════════════

/**
 * 이 앱이 뭘 하는 물건인지 한 번에 말한다. 항상 띄운다(2026-09-02 결정) —
 * 처음 여는 사람이 「퀘스트」라는 말만 보고는 관광 앱인지 게임인지 모른다.
 * 「플레이」와 「클리어」만 강조색. 두 낱말이 이 앱의 전부다.
 */
function IntroCard() {
  const accent = { color: PixelColor.primaryContainer };
  return (
    <PixelIntroCard
      icon="bang"
      iconColor={PixelColor.primaryContainer}
      title={
        <>
          관광지를 <span style={accent}>플레이</span>하세요
        </>
      }
      message={
        <>
          제주 관광지 하나가 통째로 게임 속 장소가 됩니다. 실제 장소를 돌아다니며 미션을 수행하고 그곳을{' '}
          <b style={{ ...accent, fontWeight: 700 }}>클리어</b>하세요.
        </>
      }
    />
  );
}

// ═══════════════════════════════ 비었을 때 ═══════════════════════════════

function LoadingRow() {
  return (
    <div className="home-status home-status--loading" role="status">
      <PixelSpinner />
      <p style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>불러오는 중…</p>
    </div>
  );
}

function EmptyRow() {
  return (
    <div className="home-status home-status--empty" role="alert">
      <Icon name="warn" size={40} color={PixelColor.locked} />
      <p style={{ ...PixelFont.body, color: PixelColor.inkWeak }}>퀘스트를 불러오지 못했어요.</p>
      <p style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>아래로 당겨 다시 시도해보세요.</p>
    </div>
  );
}
