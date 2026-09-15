/**
 * PLAY 상세 — 원본: Views/PlayDetailView.swift
 * 라우트: `/play/:playId` (탭바 숨김). 받는 값: usePlayDetailParams() → { playId }
 *
 * **시작 전에 무엇을 하게 되는지 알려주는 화면**이다. 두 질문에 답한다.
 *   1. 여기서 내가 어떤 PLAY 를 하게 되는가?
 *   2. 어디서 시작해서 어디를 탐험하게 되는가?
 *
 *   PixelCard (큰 카드 하나가 화면 전체를 감싼다)
 *     머리      커버(1.75) + 가운데 걸친 제목 카드 · MAIN QUEST
 *     설명      목표 한 문장
 *     스탯 2×2  예상 시간 · 거리 · 난이도 · Missions
 *     경로 안내  지도(선 없음) + START · 1 · 2 … · FINISH
 *     장소 문    「○○ 정보 보러가기」 → 장소 상세(KTO)
 *   아래 고정 바  [플레이하기 / 이어서 하기 / 다시 하기] (+ 진행 중이면 「처음부터 다시 하기」)
 *
 * Swift 에서 옮기지 않은 것: 커버 위 픽셀 뒤로가기(`pixelFloatingBack`) — 토스 네비게이션 바가 준다.
 */
import { useState } from 'react';
import {
  distanceText,
  durationText,
  missionCount,
  PLAY_START_LABEL,
  PlayAPI,
  startCoordinate,
  type Play,
  type PlaySummary,
} from '../../api';
import { useAppNavigation, usePlayDetailParams } from '../../app/routes';
import { useResource } from '../../lib/resource';
import { playProgressStore, progressLabel, usePlayProgress, isFinished as isProgressFinished } from '../../stores';
import {
  coverFor,
  Icon,
  PixelBlink,
  PixelBottomBar,
  PixelCard,
  PixelColor,
  PixelDialog,
  PixelFont,
  PixelPlaceholderScene,
  PixelSpacing,
  PixelSpinner,
  PlayRouteMap,
  RouteListRow,
  type IconName,
} from '../../ui';
import { FitText } from './FitText';
import './play-detail.css';

export function PlayDetailScreen() {
  const { playId } = usePlayDetailParams();
  const nav = useAppNavigation();
  const { data: play, error } = useResource<Play>(playId ? `play:${playId}` : null, () => PlayAPI.detail(playId));

  // 진행 상태 — 러너에서 돌아오면 저장소 구독으로 저절로 새로 읽힌다
  // (Swift: showRunner 가 닫히면 refreshProgress).
  const saved = usePlayProgress(playId);
  const hasProgress = saved !== null;
  const finished = saved ? isProgressFinished(saved) : false;

  const [showResetConfirm, setShowResetConfirm] = useState(false);

  // 서버가 id 를 모르면(빈 id 포함) 불러오기 실패와 같게 보인다.
  const failed = !play && (!!error || !playId);

  return (
    <div className="px-screen">
      {play ? (
        <div className="pd-body">
          <PixelCard>
            {/* 시안은 32 였다. 첫 화면 높이를 맞추려고 16 으로 조였다. */}
            <div className="pd-stack">
              <HeroBlock play={play} />
              <DescriptionBox play={play} />
              <StatsGrid play={play} />
              <RouteBox play={play} />
              <PlaceInfoBox
                play={play}
                onOpen={() => {
                  const start = startCoordinate(play);
                  nav.toPlaceDetail({ name: play.placeName, lat: start?.lat ?? 0, lng: start?.lng ?? 0 });
                }}
              />
            </div>
          </PixelCard>
        </div>
      ) : failed ? (
        <FailedView />
      ) : (
        <div className="pd-state">
          <PixelSpinner />
        </div>
      )}

      {play && (
        // 시안대로 **버튼 하나만** 고정한다. 진행 중일 때만 아래에 「처음부터 다시 하기」를 작게 둔다.
        // Swift 는 위 4px 테두리를 안쪽 여백 16 위에 겹쳐 그린다 → 테두리 아래로 보이는 여백은 12.
        <PixelBottomBar style={{ paddingTop: PixelSpacing.l - PixelSpacing.borderHeavy }}>
          <div className="pd-bottom">
            <StartButton
              label={progressLabel(saved) ?? PLAY_START_LABEL}
              onPress={() => nav.toPlayRunner(play)}
            />
            {hasProgress && !finished && (
              <button
                type="button"
                className="px-reset-button pd-reset"
                style={PixelFont.labelSmall}
                onClick={() => setShowResetConfirm(true)}
              >
                처음부터 다시 하기
              </button>
            )}
          </div>
        </PixelBottomBar>
      )}

      <PixelDialog
        open={showResetConfirm && !!play}
        title="지금까지 진행한 게 사라져요. 처음부터 다시 할까요?"
        onClose={() => setShowResetConfirm(false)}
        actions={[
          {
            label: '처음부터 다시 하기',
            role: 'destructive',
            onPress: () => {
              if (!play) return;
              playProgressStore.clear(play.id);
              nav.toPlayRunner(play);
            },
          },
          { label: '계속 이어서 하기', role: 'cancel' },
        ]}
      />
    </div>
  );
}

// ═══════════════════════════════ 머리 (커버 + 가운데 제목 카드) ═══════════════════════════════

/**
 * 제목 카드는 **커버 그림의 정가운데**에 놓인다 — 위아래로 마을 풍경이 고르게 남는다.
 * 커버는 픽셀 커버 → KTO 실사 사진 → 놀멍봅서 기본 그림 순서 (홈 카드와 같은 규칙).
 */
function HeroBlock({ play }: { play: Play }) {
  return (
    <div className="pd-hero px-border-heavy">
      <Cover play={play} />
      <div className="pd-hero__title px-border px-shadow-small">
        {/* 24 에서 한 줄. 좁은 폭(iPhone SE 급)에서만 0.9 배까지 줄인다. */}
        <FitText
          text={play.title}
          fontSize={24}
          minScale={0.9}
          style={{ ...PixelFont.sectionTitle, color: PixelColor.ink, textAlign: 'center' }}
        />
        {/* ⚠️ 아직 콘텐츠 데이터가 아니다 — Play 에 퀘스트 종류 항목이 없어 문구를 박아 뒀다. */}
        <span className="pd-badge px-border" style={PixelFont.labelSmall}>
          MAIN QUEST
        </span>
      </div>
    </div>
  );
}

function Cover({ play }: { play: Play }) {
  const pixelCover = coverFor(play.placeKey);
  // 사진은 목록 응답에만 있다. 픽셀 커버가 번들에 있으면 필요 없으므로 그때는 부르지 않는다.
  const { data: plays } = useResource<PlaySummary[]>(pixelCover ? null : 'plays', () => PlayAPI.list());
  const thumbnail = pixelCover ? null : (plays?.find((p) => p.id === play.id)?.thumbnail ?? null);
  const [failedUrl, setFailedUrl] = useState<string | null>(null);

  let content;
  if (pixelCover) {
    // 픽셀아트는 보간하지 않는다 — 기본 보간은 도트를 뭉갠다.
    content = <img src={pixelCover} alt="" className="px-pixelated" />;
  } else if (thumbnail && failedUrl !== thumbnail) {
    // 받는 동안은 바탕색(secondaryContainer), 실패하면 기본 그림.
    content = <img src={thumbnail} alt="" referrerPolicy="no-referrer" onError={() => setFailedUrl(thumbnail)} />;
  } else {
    // 회색 사진 아이콘은 「못 불러왔다」로 읽힌다 — 대개는 KTO 에 처음부터 없는 것이다.
    content = <PixelPlaceholderScene />;
  }

  return (
    <div className="pd-hero__cover" aria-hidden="true">
      {content}
    </div>
  );
}

// ═══════════════════════════════ 설명 ═══════════════════════════════

/** 목표 한 문장. 시안은 18 이었는데 첫 화면 높이를 맞추려고 16 으로 내렸다. */
function DescriptionBox({ play }: { play: Play }) {
  return (
    <div className="pd-box px-border px-shadow-card">
      {play.objective.length > 0 && (
        <p className="pd-objective" style={{ ...PixelFont.body, lineHeight: 'calc(16px * var(--px-line) + 4px)' }}>
          {play.objective}
        </p>
      )}
    </div>
  );
}

// ═══════════════════════════════ 스탯 2×2 ═══════════════════════════════

function StatsGrid({ play }: { play: Play }) {
  return (
    <div className="pd-stats">
      <StatBox icon="clock" value={durationText(play)} label="예상 시간" tint={PixelColor.primary} />
      {/* 시안은 route 아이콘 — 걷는 사람으로 둔다 (홈 카드의 거리 표시와 같은 아이콘). */}
      <StatBox icon="walk" value={distanceText(play)} label="거리" tint={PixelColor.secondary} />
      <StatBox icon="star" value={play.difficulty} label="난이도" tint={PixelColor.tertiary} />
      <StatBox icon="check" value={String(missionCount(play))} label="Missions" tint={PixelColor.error} />
    </div>
  );
}

function StatBox({ icon, value, label, tint }: { icon: IconName; value: string; label: string; tint: string }) {
  return (
    <div className="pd-stat px-border px-shadow-card" role="group" aria-label={`${label} ${value}`}>
      <Icon name={icon} size={30} color={tint} />
      <FitText
        text={value}
        fontSize={24}
        minScale={0.7}
        style={{ ...PixelFont.sectionTitle, color: PixelColor.ink, textAlign: 'center' }}
      />
      <span aria-hidden="true" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
        {label}
      </span>
    </div>
  );
}

// ═══════════════════════════════ 퀘스트 경로 안내 ═══════════════════════════════

function RouteBox({ play }: { play: Play }) {
  return (
    <div className="pd-box px-border px-shadow-card">
      {/* 아이콘만 초록, 제목·밑줄은 잉크 2px — PixelSectionHeader 는 셋이 한 색이라 쓰지 않는다. */}
      <div className="pd-route-head">
        <Icon name="map" size={24} color={PixelColor.primary} />
        <h2 style={PixelFont.sectionTitle}>퀘스트 경로 안내</h2>
      </div>

      {/* 시안의 픽셀 마을 그림 대신 실제 지도. Point 를 선으로 잇지 않는다. */}
      <div className="px-border" style={{ height: 200 }}>
        <PlayRouteMap play={play} height={200} />
      </div>

      <div className="pd-route-list">
        <RouteListRow marker="START" text={play.startName} kind="terminal" />
        {play.points.map((point, i) => (
          <RouteListRow key={point.id} marker={String(i + 1)} text={point.title} kind="step" />
        ))}
        <RouteListRow marker="FINISH" text={play.finishName} kind="terminal" />
      </div>
    </div>
  );
}

// ═══════════════════════════════ 장소 정보 문 ═══════════════════════════════

/**
 * 장소 관광정보(KTO)로 가는 문. 경로 안내 아래 — 「이 장소 자체」로 관심이 넘어가는 지점.
 * 파랑 채움 = 다른 화면으로 가는 문. 카드들과 달리 **버튼 문법**(아래로만 던지는 그림자·눌리면
 * 가라앉기)을 쓴다. 앞에 아이콘을 두지 않는다.
 */
function PlaceInfoBox({ play, onOpen }: { play: Play; onOpen: () => void }) {
  return (
    <button type="button" className="px-reset-button pd-place-button px-border px-press" onClick={onOpen}>
      <span style={{ ...PixelFont.bodyLargeBold, color: PixelColor.onSecondary }}>{play.placeName} 정보 보러가기</span>
    </button>
  );
}

// ═══════════════════════════════ 시작 버튼 ═══════════════════════════════

/**
 * 시안 `button.w-full.bg-primary.py-3.border-4.pixel-btn-shadow`.
 * 옛 게임의 「PRESS START」처럼 **화살표까지 한 덩어리로** 깜빡인다 — 초록 바탕과 테두리는 가만히 있다.
 */
function StartButton({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <button
      type="button"
      className="px-reset-button pd-start px-border-heavy px-press"
      style={{ ['--px-press-offset' as string]: `${PixelSpacing.shadowButton}px` }}
      onClick={onPress}
    >
      <PixelBlink style={{ minWidth: 0, maxWidth: '100%' }}>
        <span className="pd-start__label">
          <Icon name="play" size={24} color={PixelColor.onPrimary} />
          <span className="pd-start__text" style={{ ...PixelFont.sectionTitle, color: PixelColor.onPrimary }}>
            {label}
          </span>
        </span>
      </PixelBlink>
    </button>
  );
}

// ═══════════════════════════════ 실패 ═══════════════════════════════

function FailedView() {
  return (
    <div className="pd-state" role="alert">
      <Icon name="warn" size={40} color={PixelColor.locked} />
      <p style={{ ...PixelFont.body, color: PixelColor.inkWeak, margin: 0 }}>PLAY 를 불러오지 못했어요.</p>
    </div>
  );
}
