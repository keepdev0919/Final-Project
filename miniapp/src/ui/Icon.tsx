/**
 * 아이콘 — PixelIcon.swift 이식.
 *
 * iOS 는 Material Icons 폰트(채움 스타일)를 글자로 찍는다. 웹은 **같은 폰트에서 뽑은
 * 같은 윤곽을 SVG 로** 그린다 (`iconPaths.ts`, 생성: `scripts/gen-icon-paths.py`).
 * 앱인토스 규칙(화살표·꺾쇠는 텍스트 글리프 대신 SVG)과 폰트 로딩 깜빡임을 함께 피한다.
 *
 * 이름은 Swift `PixelIcon.Glyph` 의 case 이름 그대로다: `.mapPin` → `name="mapPin"`.
 *
 * ⚠️ color 를 안 주면 부모의 글자색(currentColor)을 따른다. Swift 도 기본값을 잉크로
 *    고정하지 않는다 — 고정하면 바깥 색 지정이 조용히 무시된다.
 */
import type { CSSProperties } from 'react';
import { ICON_PATHS, ICON_VIEWBOX, type IconName } from './iconPaths';

export type { IconName };

export interface IconProps {
  name: IconName;
  /** px. Swift 기본값과 같은 24. */
  size?: number;
  /** CSS 색. `PixelColor.ink` 같은 값. 비우면 currentColor. */
  color?: string;
  className?: string;
  style?: CSSProperties;
  /** 접근성 이름. 비우면 장식으로 보고 스크린리더에서 숨긴다(Swift 와 같다). */
  label?: string;
}

export function Icon({ name, size = 24, color, className, style, label }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox={ICON_VIEWBOX}
      fill={color ?? 'currentColor'}
      className={className}
      style={{ display: 'block', flex: 'none', ...style }}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      focusable="false"
    >
      <path d={ICON_PATHS[name]} />
    </svg>
  );
}
