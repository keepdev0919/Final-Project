/**
 * 확인창·시트 — iOS `.alert` / `.confirmationDialog` / `.sheet` 자리.
 *
 * 여러 화면이 같은 모양을 쓰도록 여기 하나로 둔다:
 *   PLAY 상세   「처음부터 다시 할까요?」 (confirmationDialog)
 *   러너        「나가기 (완료한 지점까지 저장돼요)」 (alert) · 신고 시트 · 진행 지도 시트
 *   코스 상세   이름 변경 시트 · 「이 코스를 뺄까요?」 (alert)
 *   코스 목록   「코스를 가져오지 못했어요」 (alert)
 *
 * 둘 다 열려 있는 동안 **토스 뒤로가기 = 닫기**다(useBackHandler). 문구는 호출부가 Swift 그대로 넣는다.
 */
import { useEffect, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { useBackHandler } from '../app/backHandler';
import { Icon } from './Icon';
import { PixelCard } from './PixelComponents';
import { PixelColor, PixelFont, PixelSpacing } from './tokens';

export interface DialogAction {
  label: string;
  /** cancel = 닫기만 · destructive = 빨간 글자 · default */
  role?: 'cancel' | 'destructive' | 'default';
  onPress?: () => void;
}

/**
 * 가운데 뜨는 확인창. 버튼을 누르면 onPress 를 부르고 **닫힌다**(onClose).
 * 배경(dim)을 누르거나 뒤로가기를 누르면 cancel 과 같다.
 */
export function PixelDialog({
  open,
  title,
  message,
  actions,
  onClose,
}: {
  open: boolean;
  title: ReactNode;
  message?: ReactNode;
  actions: DialogAction[];
  onClose: () => void;
}) {
  useBackHandler(open ? onClose : null);
  useEscape(open, onClose);
  if (!open) return null;
  return createPortal(
    <div className="px-overlay px-overlay--center" onClick={onClose}>
      <div
        role="alertdialog"
        aria-modal="true"
        style={{ width: '100%', maxWidth: 320 }}
        onClick={(e) => e.stopPropagation()}
      >
        <PixelCard strong>
          <div style={{ padding: 24, display: 'flex', flexDirection: 'column', gap: PixelSpacing.m }}>
            <h2 style={{ ...PixelFont.body, fontWeight: 700, color: PixelColor.ink, textAlign: 'center', margin: 0 }}>{title}</h2>
            {message && (
              <p style={{ ...PixelFont.bodySmall, color: PixelColor.inkWeak, textAlign: 'center', lineHeight: 1.5, margin: 0 }}>{message}</p>
            )}
            <div style={{ display: 'flex', flexDirection: 'column', gap: PixelSpacing.s, marginTop: PixelSpacing.s }}>
              {actions.map((a, i) => (
                <button
                  key={i}
                  type="button"
                  className="px-button-style px-border px-press"
                  style={{
                    ['--px-btn-fill' as string]: a.role === 'cancel' ? PixelColor.surfaceMid : PixelColor.surface,
                    ['--px-btn-label' as string]: a.role === 'destructive' ? PixelColor.locked : PixelColor.ink,
                    width: '100%',
                  }}
                  onClick={() => {
                    a.onPress?.();
                    onClose();
                  }}
                >
                  {a.label}
                </button>
              ))}
            </div>
          </div>
        </PixelCard>
      </div>
    </div>,
    document.body,
  );
}

/**
 * 아래에서 올라오는 시트. 오른쪽 위에 닫기(✕) 버튼이 늘 있다(앱인토스: 바텀시트엔 닫기 어포던스).
 * 내용이 길면 시트 안에서 스크롤한다. 하단 safe area 를 지킨다.
 */
export function PixelSheet({
  open,
  onClose,
  title,
  children,
  height = 'auto',
}: {
  open: boolean;
  onClose: () => void;
  title?: ReactNode;
  children: ReactNode;
  /** 'auto' = 내용만큼(최대 90%) · 'medium' = 화면 절반 · 'large' = 90% */
  height?: 'auto' | 'medium' | 'large';
}) {
  useBackHandler(open ? onClose : null);
  useEscape(open, onClose);
  if (!open) return null;
  const h = height === 'medium' ? '50dvh' : height === 'large' ? '90dvh' : undefined;
  return createPortal(
    <div className="px-overlay px-overlay--bottom" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        className="px-sheet"
        style={{ height: h }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-sheet__head">
          <h2 style={{ ...PixelFont.label, color: PixelColor.ink, flex: '1 1 auto', margin: 0 }}>{title}</h2>
          <button type="button" className="px-reset-button px-sheet__close" aria-label="닫기" onClick={onClose}>
            <Icon name="close" size={24} color={PixelColor.ink} />
          </button>
        </div>
        <div className="px-sheet__body">{children}</div>
      </div>
    </div>,
    document.body,
  );
}

function useEscape(open: boolean, onClose: () => void) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);
}
