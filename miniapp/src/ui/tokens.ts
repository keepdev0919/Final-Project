/**
 * Swift 디자인 시스템 이름을 그대로 쓰는 TS 토큰.
 *
 * - `PixelColor.xxx`   → CSS 변수 문자열 (`'var(--px-ink)'`). 값의 정본은 `src/styles/pixel.css`.
 * - `PixelSpacing.xxx` → px 숫자. 인라인 style 에 그대로 넣는다.
 * - `PixelFont.xxx`    → `CSSProperties` 조각. `style={{ ...PixelFont.label, color: PixelColor.ink }}`
 *
 * Swift 코드를 옮길 때 `PixelColor.primary` → `PixelColor.primary`,
 * `PixelFont.label` → `...PixelFont.label`, `PixelSpacing.l` → `PixelSpacing.l` 로 1:1 대응한다.
 */
import type { CSSProperties } from 'react';

const v = (name: string) => `var(--px-${name})`;

/** PixelColor.swift 의 라이트 값. 여기 없는 색을 화면에서 만들지 않는다. */
export const PixelColor = {
  background: v('background'),
  surface: v('surface'),
  surfaceLow: v('surface-low'),
  surfaceMid: v('surface-mid'),
  surfaceHigh: v('surface-high'),
  surfaceVariant: v('surface-variant'),
  surfaceDim: v('surface-dim'),

  ink: v('ink'),
  inkWeak: v('ink-weak'),

  outline: v('outline'),
  outlineVariant: v('outline-variant'),

  primary: v('primary'),
  onPrimary: v('on-primary'),
  primaryContainer: v('primary-container'),
  onPrimaryContainer: v('on-primary-container'),

  secondary: v('secondary'),
  onSecondary: v('on-secondary'),
  secondaryContainer: v('secondary-container'),
  onSecondaryContainer: v('on-secondary-container'),

  tertiary: v('tertiary'),
  onTertiary: v('on-tertiary'),
  tertiaryContainer: v('tertiary-container'),
  onTertiaryContainer: v('on-tertiary-container'),
  tertiaryFixed: v('tertiary-fixed'),
  onTertiaryFixed: v('on-tertiary-fixed'),

  error: v('error'),
  onError: v('on-error'),

  regionEast: v('region-east'),
  onRegionEast: v('on-region-east'),
  regionWest: v('region-west'),
  onRegionWest: v('on-region-west'),
  regionSouth: v('region-south'),
  onRegionSouth: v('on-region-south'),

  // 의미 별칭
  sunk: v('sunk'),
  accent: v('accent'),
  onAccent: v('on-accent'),
  done: v('done'),
  onDone: v('on-done'),
  locked: v('locked'),
  onLocked: v('on-locked'),
  regionNorth: v('region-north'),
  onRegionNorth: v('on-region-north'),
  regionAll: v('region-all'),
  onRegionAll: v('on-region-all'),
} as const;

export type PixelColorName = keyof typeof PixelColor;

/** PixelSpacing.swift — 간격은 4의 배수다. */
export const PixelSpacing = {
  xs: 4,
  s: 8,
  m: 12,
  l: 16,
  xl: 20,
  xxl: 32,
  xxxl: 48,

  cardPadding: 16,
  cardGap: 16,
  sectionGap: 32,
  screenMargin: 20,

  buttonHeight: 48,
  tabBarHeight: 80,

  border: 2,
  borderHeavy: 4,

  shadowCard: 4,
  shadowSmall: 2,
  shadowStrong: 8,
  shadowButton: 4,
} as const;

const FONT = 'var(--px-font)';
const LINE = 'var(--px-line)';
const g = (size: number, bold = false): CSSProperties => ({
  fontFamily: FONT,
  fontSize: size,
  fontWeight: bold ? 700 : 400,
  lineHeight: LINE,
});

/**
 * PixelFont.swift — 갈무리11 Regular/Bold 두 벌뿐이다. 굵기는 400·700 만 쓴다.
 * 같은 이름의 CSS 클래스도 있다: `px-t-screen-title` · `px-t-label` …
 */
export const PixelFont = {
  /** 화면 최상단 큰 제목 — 28 / Bold */
  screenTitle: g(28, true),
  /** 섹션 제목 · 카드 제목 — 24 / Bold */
  sectionTitle: g(24, true),
  /** 소개문 — 18 */
  bodyLarge: g(18),
  /** 소개문 안에서 낱말 하나를 강조할 때 — 18 / Bold */
  bodyLargeBold: g(18, true),
  /** 본문 — 16 */
  body: g(16),
  /** 라벨 · 버튼 · 칩 — 14 / Bold */
  label: g(14, true),
  /** 작은 라벨 · 배지 — 12 / Bold (앱인토스 최소 12px) */
  labelSmall: g(12, true),
  /** 14 Regular */
  bodySmall: g(14),
  /** 읽는 글꼴 — 두 줄 넘는 설명문. 시스템 서체 14. */
  reading: {
    fontFamily: 'var(--px-font-reading)',
    fontSize: 14,
    fontWeight: 400,
    lineHeight: 1.5,
  } as CSSProperties,
  /** 앱 이름·로고 */
  logo: (size = 22): CSSProperties => g(size, true),
} as const;

/** `pixelShadow(offset)` 을 인라인 style 로 쓸 때. */
export function pixelShadow(offset: number = PixelSpacing.shadowCard): CSSProperties {
  return { boxShadow: `${offset}px ${offset}px 0 0 ${PixelColor.ink}` };
}
