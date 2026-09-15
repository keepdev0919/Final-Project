/**
 * 퀘스트 카드 — 원본: Views/Components/PlayCard.swift
 *
 *   PlayCard            플레이할 수 있는 곳 (LIVE)
 *   PreparingPlaceCard  아직 퀘스트가 없는 곳 (PLANNED) — 같은 뼈대, 흑백 커버 + 자물쇠
 *   QuestCoverImage     카드 커버 160 — 픽셀 커버 → KTO 사진 → 기본 그림
 *   QuestButton         카드 맨 아래 버튼 (높이 44)
 *   StarRating          난이도 별 다섯 개
 *
 * 시안 px 를 그대로 쓴다(Swift 주석: 토큰 이름으로 "번역"했다가 카드가 부풀었다).
 */
import { useState } from 'react';
import { durationText, playCardText, type PlaySummary } from '../../api';
import { coverFor, Icon, PixelCard, PixelColor, PixelFont, PixelPlaceholderScene, type IconName } from '../../ui';
import { distanceShort } from './model';

// ═══════════════════════════════ PlayCard ═══════════════════════════════

export function PlayCard({
  play,
  progressText,
  onAction,
}: {
  play: PlaySummary;
  /** 진행 중이면 「이어서 하기」, 끝냈으면 「다시 하기」. 손 안 댄 퀘스트는 null → 「퀘스트 수락」. */
  progressText: string | null;
  onAction: () => void;
}) {
  const cardText = playCardText(play);
  const duration = durationText(play);
  const distance = distanceShort(play);
  return (
    <PixelCard
      role="group"
      aria-label={`${play.title}. ${play.placeName}. ${duration}, ${distance}. 난이도 별 ${play.difficultyStars}개. ${cardText}`}
    >
      <div className="home-card__body">
        <QuestCoverImage coverName={play.placeKey} url={play.thumbnail} locked={false} />

        <div className="home-card__info">
          {/* 제목 왼쪽, 시간·거리 오른쪽. 시안의 `justify-between`. */}
          <div className="home-card__title-row">
            <h3 className="home-card__title" style={{ ...PixelFont.label, color: PixelColor.ink }}>
              {play.title}
            </h3>
            <span className="home-card__spacer" />
            <div className="home-card__meta">
              <MetaItem icon="clock" text={duration} />
              <MetaItem icon="walk" text={distance} />
            </div>
          </div>
          <StarRating filled={play.difficultyStars} />
          {/* 시안의 `text-body-sm` 은 Tailwind config 에 없는 클래스라 브라우저 기본 16 으로 렌더된다 → body(16). */}
          <p className="home-card__text home-card__text--clamp" style={{ ...PixelFont.body, color: PixelColor.inkWeak }}>
            {cardText}
          </p>
        </div>

        <QuestButton title={progressText ?? '퀘스트 수락'} filled onClick={onAction} />
      </div>
    </PixelCard>
  );
}

function MetaItem({ icon, text }: { icon: IconName; text: string }) {
  return (
    <span className="home-card__meta-item">
      <Icon name={icon} size={18} color={PixelColor.inkWeak} />
      <span style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>{text}</span>
    </span>
  );
}

// ═══════════════════════════════ 준비 중 카드 ═══════════════════════════════

/**
 * 아직 퀘스트가 없는 곳. 활성 카드와 같은 뼈대에 사진만 흑백으로 낮추고 자물쇠를 얹는다.
 * 별도, 별점도, 우상단 딱지도 없다 — 아직 정한 것이 없으니 보여줄 것도 없다.
 */
export function PreparingPlaceCard({
  placeName,
  coverName,
  thumbnail,
  onAction,
}: {
  placeName: string;
  coverName: string | null;
  thumbnail: string | null;
  onAction: () => void;
}) {
  return (
    <PixelCard role="group" aria-label={`${placeName}. 퀘스트 준비 중. 장소 정보를 봅니다.`}>
      <div className="home-card__body">
        <QuestCoverImage coverName={coverName} url={thumbnail} locked />

        <div className="home-card__info">
          <h3 className="home-card__place" style={{ ...PixelFont.label, color: PixelColor.ink }}>
            {placeName}
          </h3>
          <p className="home-card__text" style={{ ...PixelFont.body, color: PixelColor.inkWeak }}>
            준비 중인 퀘스트입니다.
          </p>
        </div>

        <QuestButton title="준비 중" filled={false} onClick={onAction} />
      </div>
    </PixelCard>
  );
}

// ═══════════════════════════════ 부품 ═══════════════════════════════

function parseImageURL(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    return new URL(url).href;
  } catch {
    return null;
  }
}

/**
 * 카드 커버. 시안 `div.h-40.pixel-border-sm`.
 * 픽셀 커버가 있으면 그것을(보간 끔), 없으면 KTO 실사 사진을, 그것도 없거나 못 받으면 기본 그림.
 * 받는 동안은 secondaryContainer 면이 보인다 (AsyncImage 의 기본 단계).
 */
export function QuestCoverImage({
  coverName,
  url,
  locked,
}: {
  /** 픽셀 커버 파일 이름 (= place_key). 번들에 없으면 사진으로 떨어진다. */
  coverName: string | null;
  url: string | null;
  /** 준비 중이면 흑백으로 낮추고 자물쇠를 얹는다 (시안 `grayscale opacity-50`). */
  locked: boolean;
}) {
  const pixelCover = coverFor(coverName);
  const photo = pixelCover ? null : parseImageURL(url);
  const [failedPhoto, setFailedPhoto] = useState<string | null>(null);

  let content;
  if (pixelCover) {
    content = <img className="home-cover__img px-pixelated" src={pixelCover} alt="" />;
  } else if (photo && failedPhoto !== photo) {
    content = (
      <img
        className="home-cover__img"
        src={photo}
        alt=""
        loading="lazy"
        decoding="async"
        referrerPolicy="no-referrer"
        onError={() => setFailedPhoto(photo)}
      />
    );
  } else {
    content = <PixelPlaceholderScene />;
  }

  return (
    <div className="home-cover px-border" aria-hidden="true">
      <div className="home-cover__shadow" />
      <div className="home-cover__frame" data-locked={locked}>
        {content}
      </div>
      {locked && (
        <div className="home-cover__lock">
          <Icon name="lock" size={36} color={PixelColor.ink} />
        </div>
      )}
    </div>
  );
}

/**
 * 카드 맨 아래 버튼. 시안 `button.py-2.font-label-lg.pixel-border`.
 * PixelButton 을 쓰지 않는다 — 높이 48 이라 카드 안에서 두꺼워진다. 높이는 44(손가락 최소 크기).
 * ⚠️ 「퀘스트 수락」과 「준비 중」이 이 버튼 하나를 같이 쓴다.
 */
function QuestButton({ title, filled, onClick }: { title: string; filled: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      className="home-quest-button px-reset-button px-border-heavy px-shadow-card"
      style={{
        ...PixelFont.label,
        color: filled ? PixelColor.onPrimary : PixelColor.outline,
        background: filled ? PixelColor.primary : PixelColor.surfaceVariant,
        textAlign: 'center',
      }}
      onClick={onClick}
    >
      {title}
    </button>
  );
}

/** 시안 인라인 색 — 테마 팔레트에 없다. 이 자리에만 둔다. */
const STAR_FILLED = '#F2B233';
const STAR_EMPTY = '#BCCABC';

/** 난이도 별 다섯 개. 5단계 척도는 콘텐츠를 만들면서 PLAY 끼리 견줘 정한다. */
export function StarRating({ filled, total = 5 }: { filled: number; total?: number }) {
  return (
    <div className="home-stars" role="img" aria-label={filled > 0 ? `난이도 별 ${filled}개` : '난이도 미정'}>
      {Array.from({ length: total }, (_, i) => (
        <Icon key={i} name="star" size={14} color={i < filled ? STAR_FILLED : STAR_EMPTY} />
      ))}
    </div>
  );
}
