/**
 * 화면 자리표시 — 화면 담당이 자기 화면을 옮기면 이 부품을 더는 쓰지 않는다.
 * 라우팅이 맞게 이어졌는지 눈으로 확인하려고 받은 값(파라미터·state)을 그대로 보여준다.
 */
import type { ReactNode } from 'react';
import { PixelCard } from '../ui/PixelComponents';
import { PixelColor, PixelFont, PixelSpacing } from '../ui/tokens';

export function ScreenPlaceholder({
  name,
  swift,
  details,
  children,
}: {
  /** 화면 이름 (예: 'PlayDetailScreen') */
  name: string;
  /** 원본 Swift 화면 */
  swift: string;
  /** 받은 값 요약 */
  details?: Record<string, unknown>;
  children?: ReactNode;
}) {
  return (
    <div className="px-screen" style={{ padding: `${PixelSpacing.xl}px ${PixelSpacing.screenMargin}px ${PixelSpacing.xxxl}px` }}>
      <PixelCard>
        <div style={{ padding: 24, display: 'flex', flexDirection: 'column', gap: PixelSpacing.s }}>
          <h1 style={{ ...PixelFont.sectionTitle, color: PixelColor.ink, margin: 0 }}>{name}</h1>
          <p style={{ ...PixelFont.bodySmall, color: PixelColor.inkWeak, margin: 0 }}>원본: {swift}</p>
          <p style={{ ...PixelFont.bodySmall, color: PixelColor.inkWeak, margin: 0 }}>아직 옮기지 않은 화면이에요.</p>
          {details && (
            <pre
              style={{
                ...PixelFont.reading,
                fontSize: 12,
                margin: 0,
                padding: PixelSpacing.s,
                background: PixelColor.surfaceMid,
                whiteSpace: 'pre-wrap',
                wordBreak: 'break-all',
              }}
            >
              {JSON.stringify(details, null, 2)}
            </pre>
          )}
          {children}
        </div>
      </PixelCard>
    </div>
  );
}
