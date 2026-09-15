/**
 * 공용 픽셀 부품 — PixelComponents.swift 이식.
 *
 * 부품마다 Swift 이름을 그대로 쓴다. 스타일 값은 `src/styles/pixel.css` 에 있다.
 *
 * 옮기지 않은 것
 *   - `PixelFloatingBack` : 앱인토스는 토스 네비게이션 바가 뒤로가기를 준다. 화면 안에
 *     뒤로가기를 또 그리면 두 개가 겹친다(출시 검수 반려 사유). 화면 이름이 필요하면
 *     본문 첫 줄에 쓴다.
 *   - `PixelScene`·`PixelPortrait` : PLAY 진행 화면 전용이라 play-runner 가 옮긴다.
 */
import {
  type ButtonHTMLAttributes,
  type CSSProperties,
  type HTMLAttributes,
  type ReactNode,
} from 'react';
import { Icon, type IconName } from './Icon';
import { PixelColor, PixelFont, PixelSpacing } from './tokens';
import { images } from './images';

const cx = (...names: (string | false | null | undefined)[]) => names.filter(Boolean).join(' ');

// ═══════════════════════════════ 버튼 ═══════════════════════════════

/**
 * PixelButton.Style. `{ fill, label }` 은 Swift `.tinted(fill:label:)` —
 * 화면의 문맥색(예: 코스의 권역색)을 입는 버튼.
 */
export type PixelButtonKind = 'primary' | 'accent' | 'plain' | { fill: string; label: string };

function buttonColors(kind: PixelButtonKind): { fill: string; label: string } {
  if (typeof kind === 'object') return kind;
  switch (kind) {
    case 'primary':
      return { fill: PixelColor.primary, label: PixelColor.onPrimary };
    case 'accent':
      return { fill: PixelColor.accent, label: PixelColor.onAccent };
    case 'plain':
      return { fill: PixelColor.surface, label: PixelColor.ink };
  }
}

function kindStyle(kind: PixelButtonKind): CSSProperties {
  const c = buttonColors(kind);
  return { ['--px-btn-fill' as string]: c.fill, ['--px-btn-label' as string]: c.label };
}

export interface PixelButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'title'> {
  title: ReactNode;
  kind?: PixelButtonKind;
  leadingIcon?: IconName;
}

/** 높이 48 · 가로 가득 · 2px 테두리 · 4px 그림자 · 누르면 가라앉는다. */
export function PixelButton({
  title,
  kind = 'primary',
  leadingIcon,
  className,
  style,
  type = 'button',
  ...rest
}: PixelButtonProps) {
  return (
    <button
      type={type}
      className={cx('px-button px-border px-press', className)}
      style={{ ...kindStyle(kind), ...style }}
      {...rest}
    >
      {leadingIcon && <Icon name={leadingIcon} size={24} />}
      <span>{title}</span>
    </button>
  );
}

export interface PixelStyledButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  kind?: PixelButtonKind;
}

/**
 * PixelButtonStyle — 레이블을 직접 그린 버튼에 씌운다.
 * 글자 14 Bold · 좌우 16 · 위아래 12 · 2px 테두리 · 4px 그림자 · 누르면 가라앉는다.
 */
export function PixelStyledButton({
  kind = 'primary',
  className,
  style,
  type = 'button',
  children,
  ...rest
}: PixelStyledButtonProps) {
  return (
    <button
      type={type}
      className={cx('px-button-style px-border px-press', className)}
      style={{ ...kindStyle(kind), ...style }}
      {...rest}
    >
      {children}
    </button>
  );
}

// ═══════════════════════════════ 카드 ═══════════════════════════════

export interface PixelCardProps extends HTMLAttributes<HTMLDivElement> {
  /** 강조 상자는 그림자를 8px 로 키운다 (대화상자·히어로). */
  strong?: boolean;
}

/** 흰 면 + 4px 테두리 + 4px(강조 8px) 그림자. 안쪽 여백은 호출부가 준다. */
export function PixelCard({ strong = false, className, ...rest }: PixelCardProps) {
  return (
    <div
      className={cx('px-card px-border-heavy', strong ? 'px-shadow-strong' : 'px-shadow-card', className)}
      {...rest}
    />
  );
}

// ═══════════════════════════════ 칩 · 배지 ═══════════════════════════════

export interface PixelChipProps {
  text: ReactNode;
  icon?: IconName;
  fill?: string;
  label?: string;
  className?: string;
  style?: CSSProperties;
}

/** `제주도` `2-3시간` 처럼 가로로 나열하는 작은 태그. */
export function PixelChip({ text, icon, fill = PixelColor.surface, label = PixelColor.ink, className, style }: PixelChipProps) {
  return (
    <span className={cx('px-chip px-border px-shadow-small', className)} style={{ background: fill, color: label, ...style }}>
      {icon && <Icon name={icon} size={16} />}
      {text}
    </span>
  );
}

/** 카드 밖으로 튀어나온 스티커. 3도 기울임. **특별한 것 하나에만.** */
export function PixelStickerBadge({ text, fill = PixelColor.accent, style }: { text: ReactNode; fill?: string; style?: CSSProperties }) {
  return (
    <span className="px-sticker px-border px-shadow-small" style={{ background: fill, ...style }}>
      {text}
    </span>
  );
}

export type PixelBadgeKind = 'free' | 'here' | 'audio' | 'heard' | 'locked';

const BADGE: Record<PixelBadgeKind, { fill: string; label: string; icon?: IconName }> = {
  free: { fill: PixelColor.accent, label: PixelColor.onAccent },
  here: { fill: PixelColor.primary, label: PixelColor.onPrimary, icon: 'mapPin' },
  // 체크(✔)는 「다 들었다」는 뜻이라 틀린다
  audio: { fill: PixelColor.surface, label: PixelColor.ink, icon: 'play' },
  heard: { fill: PixelColor.done, label: PixelColor.onDone, icon: 'check' },
  locked: { fill: PixelColor.locked, label: PixelColor.onLocked, icon: 'lock' },
};

/** 상태 배지. 색만으로 상태를 구분하지 않는다 — 아이콘이 함께 붙는다. */
export function PixelBadge({ text, kind }: { text: ReactNode; kind: PixelBadgeKind }) {
  const b = BADGE[kind];
  return (
    <span className="px-badge px-border px-shadow-small" style={{ background: b.fill, color: b.label }}>
      {b.icon && <Icon name={b.icon} size={16} />}
      {text}
    </span>
  );
}

// ═══════════════════════════════ 막대 ═══════════════════════════════

export interface PixelMeterProps {
  /** 0.0 ~ 1.0 */
  value: number;
  fill?: string;
  /** 막대 안에 넣을 글자. 비우면 안 그린다. */
  caption?: string;
  height?: number;
}

/** 정도(난이도·거리·진행률)를 나타내는 채워지는 막대. 셀 수 있는 것에는 PixelProgressBar. */
export function PixelMeter({ value, fill = PixelColor.primary, caption, height = 32 }: PixelMeterProps) {
  const clamped = Math.max(0, Math.min(1, value));
  return (
    <div
      className="px-meter px-border"
      style={{ height }}
      role="meter"
      aria-valuemin={0}
      aria-valuemax={1}
      aria-valuenow={clamped}
      aria-valuetext={caption ?? `${Math.round(value * 100)}퍼센트`}
    >
      <div className="px-meter__fill" style={{ width: `${clamped * 100}%`, background: fill }} />
      {caption && <span className="px-meter__caption">{caption}</span>}
    </div>
  );
}

/** 칸으로 나뉜 막대 — 셀 수 있는 것 (이야기 5개 중 3개). */
export function PixelProgressBar({ total, filled }: { total: number; filled: number }) {
  const count = Math.max(total, 1);
  return (
    <div className="px-progress" role="img" aria-label={`${total}개 중 ${filled}개`}>
      {Array.from({ length: count }, (_, i) => (
        <div
          key={i}
          className="px-progress__cell px-border"
          style={{ background: i < filled ? PixelColor.primary : 'transparent' }}
        />
      ))}
    </div>
  );
}

// ═══════════════════════════════ 섹션 헤더 ═══════════════════════════════

export interface PixelSectionHeaderProps {
  title: ReactNode;
  icon?: IconName;
  /** 제목·밑줄 색. 기본 잉크. */
  accent?: string;
  /** 아이콘만 다른 색으로. 비우면 accent. */
  iconColor?: string;
  /** 밑줄 두께 — 2(카드 안 작은 구획) · 4(화면을 가르는 큰 섹션) */
  underline?: number;
  /** 제목 줄 오른쪽 (곁수치·버튼) */
  trailing?: ReactNode;
  /** 제목 태그. 기본 h2. */
  as?: 'h1' | 'h2' | 'h3';
}

/** 아이콘 + 제목 + 하단 밑줄. 카드마다 반복되면서 「일지」 인상을 만든다. */
export function PixelSectionHeader({
  title,
  icon,
  accent = PixelColor.ink,
  iconColor,
  underline = PixelSpacing.border,
  trailing,
  as: Tag = 'h2',
}: PixelSectionHeaderProps) {
  return (
    <div>
      <div className="px-section-header__row">
        {icon && <Icon name={icon} size={24} color={iconColor ?? accent} />}
        <Tag className="px-section-header__title px-t-section-title" style={{ color: accent }}>
          {title}
        </Tag>
        {trailing}
      </div>
      <div style={{ height: underline, background: accent }} />
    </div>
  );
}

// ═══════════════════════════════ 탭 머리말 카드 ═══════════════════════════════

export interface PixelIntroCardProps {
  icon: IconName;
  /** 잉크 블록 안 아이콘 색. 그 탭을 대표하는 **밝은 톤**(`*Container`). */
  iconColor: string;
  /** 강조 낱말에 색을 넣을 수 있게 ReactNode 를 받는다: `<>관광지를 <span style={{color}}>플레이</span>하세요</>` */
  title: ReactNode;
  message: ReactNode;
}

/** 퀘스트·코스·지도 탭 맨 위 「이 탭이 무엇을 하는 곳인지」 카드. */
export function PixelIntroCard({ icon, iconColor, title, message }: PixelIntroCardProps) {
  return (
    <PixelCard>
      <div className="px-intro">
        <div className="px-intro__icon px-border px-shadow-small" aria-hidden="true">
          <Icon name={icon} size={30} color={iconColor} />
        </div>
        <div className="px-intro__text">
          <h2 className="px-intro__title px-t-section-title">{title}</h2>
          <p className="px-intro__message px-t-body-large">{message}</p>
        </div>
      </div>
    </PixelCard>
  );
}

// ═══════════════════════════════ 상단 제목 띠 ═══════════════════════════════

/**
 * PixelTopBar — 아래 4px 테두리가 있는 **제목 띠**(프로필 탭).
 * 뒤로가기·닫기는 넣지 않는다 — 그건 토스 네비게이션 바의 몫이다.
 */
export function PixelTopBar({
  title,
  isAppName = false,
  accent = PixelColor.primary,
  trailing,
}: {
  title: ReactNode;
  /** 앱 이름일 때만 로고 크기(22)를 쓴다. */
  isAppName?: boolean;
  accent?: string;
  trailing?: ReactNode;
}) {
  return (
    <div className="px-top-bar">
      <h1 className={cx('px-top-bar__title', isAppName ? 'px-t-logo' : 'px-t-screen-title')} style={{ color: accent }}>
        {title}
      </h1>
      {trailing}
    </div>
  );
}

// ═══════════════════════════════ 하단 고정 바 ═══════════════════════════════

/**
 * 화면 아래에 붙박이로 두는 CTA 바 — Swift `.safeAreaInset(edge: .bottom)` 자리.
 * 흰 면 + 위 4px 잉크 테두리 + 안쪽 16 + **하단 safe area(최소 34px)**.
 * 스크롤 상자(`.px-app__main`) 바닥에 sticky 로 붙는다 — 화면 루트의 마지막 자식으로 둔다.
 */
export function PixelBottomBar({ children, style, className }: { children: ReactNode; style?: CSSProperties; className?: string }) {
  return (
    <div className={cx('px-bottom-bar', className)} style={style}>
      {children}
    </div>
  );
}

// ═══════════════════════════════ 움직임 ═══════════════════════════════

/** 제자리에서 위아래로 통통 떠다닌다. `delay` 로 표식마다 시작을 어긋나게 한다. */
export function PixelBob({
  children,
  delay = 0,
  distance = 3,
  period = 1.8,
  style,
}: {
  children: ReactNode;
  delay?: number;
  distance?: number;
  period?: number;
  style?: CSSProperties;
}) {
  return (
    <span
      className="px-bob"
      style={{
        ['--px-bob-distance' as string]: `${distance}px`,
        ['--px-bob-half' as string]: `${period / 2}s`,
        ['--px-bob-delay' as string]: `${delay}s`,
        ...style,
      }}
    >
      {children}
    </span>
  );
}

/**
 * 「PRESS START」 처럼 1초 보이고 1초 사라진다. 동작 줄이기 설정이면 깜빡이지 않는다.
 * flex 안에서 말줄임이 걸려야 하면 `style={{ minWidth: 0 }}` 처럼 넘긴다.
 */
export function PixelBlink({
  children,
  className,
  style,
}: {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <span className={`px-blink${className ? ` ${className}` : ''}`} style={style}>
      {children}
    </span>
  );
}

// ═══════════════════════════════ 기본 그림 ═══════════════════════════════

/**
 * 사진이 없을 때 까는 **놀멍봅서 기본 그림** (PixelScene.swift 의 PixelPlaceholderScene).
 * 부모 상자를 꽉 채운다(object-fit: cover). 부모가 크기를 정해야 한다.
 */
export function PixelPlaceholderScene({ style }: { style?: CSSProperties }) {
  return (
    <img
      src={images.placeholderScene}
      alt=""
      aria-hidden="true"
      className="px-pixelated"
      style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', ...style }}
    />
  );
}

// ═══════════════════════════════ 로딩 ═══════════════════════════════

/** 전면 로딩 (SharedComponents.swift 의 LoadingOverlay). */
export function LoadingOverlay({ text }: { text: string }) {
  return (
    <div
      role="status"
      aria-live="polite"
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 50,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'var(--dim)',
      }}
    >
      <div
        className="px-border px-shadow-card"
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 16,
          padding: 32,
          background: PixelColor.surface,
        }}
      >
        {/* Swift ProgressView().scaleEffect(1.5) — 기본 20pt 의 1.5배 */}
        <PixelSpinner size={30} />
        <span style={{ ...PixelFont.label, color: PixelColor.ink }}>{text}</span>
      </div>
    </div>
  );
}

/** 작은 픽셀 스피너 — ProgressView 자리. 네 칸이 돌아가며 채워진다. */
export function PixelSpinner({ size = 24, color = PixelColor.primary }: { size?: number; color?: string }) {
  const cell = size / 2;
  return (
    <span
      role="progressbar"
      aria-label="불러오는 중"
      style={{ display: 'inline-grid', gridTemplateColumns: `${cell}px ${cell}px`, width: size, height: size }}
    >
      {[0, 1, 3, 2].map((order, i) => (
        <span
          key={i}
          style={{
            background: color,
            animation: `px-blink 0.8s steps(1, end) ${(order * 0.2).toFixed(1)}s infinite`,
          }}
        />
      ))}
    </span>
  );
}
