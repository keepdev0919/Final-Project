/**
 * 사진을 **전체 화면**으로 넘겨 본다 — 원본: PlaceDetailView.swift 의 PhotoViewer · ZoomableImage
 * (2026-09-10 조익준님 결정). 검은 바탕에 좌우로 넘기고, 두 손가락으로 키울 수 있다.
 * 두 번 두드리면 원래 크기로. 닫기는 왼쪽 위 픽셀 버튼, 토스 뒤로가기도 닫기다.
 *
 * iOS 는 fullScreenCover 로 띄운다. 웹은 body 에 포털로 붙인 고정 층이다.
 */
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useBackHandler } from '../../app/backHandler';
import { Icon, PixelColor, PixelFont, PixelSpinner } from '../../ui';

export function PhotoViewer({ images, start, onClose }: { images: string[]; start: number; onClose: () => void }) {
  const clamp = (i: number) => Math.min(Math.max(i, 0), Math.max(images.length - 1, 0));
  const initial = clamp(start);
  const [index, setIndex] = useState(initial);
  const pagerRef = useRef<HTMLDivElement>(null);

  // 열려 있는 동안 토스 뒤로가기 = 닫기.
  useBackHandler(onClose);

  // 누른 사진부터 보여준다 (Swift onAppear 에서 index = start).
  useLayoutEffect(() => {
    const el = pagerRef.current;
    if (el) el.scrollLeft = initial * el.clientWidth;
    // 처음 한 번만.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const onScroll = () => {
    const el = pagerRef.current;
    if (!el || el.clientWidth === 0) return;
    const next = clamp(Math.round(el.scrollLeft / el.clientWidth));
    if (next !== index) setIndex(next);
  };

  return createPortal(
    <div className="plc-viewer" role="dialog" aria-modal="true" aria-label="사진">
      <div className="plc-viewer__pager" ref={pagerRef} onScroll={onScroll}>
        {images.map((url, i) => (
          <ZoomableImage key={`${i}-${url}`} url={url} />
        ))}
      </div>

      <div className="plc-viewer__bar">
        <button type="button" className="plc-viewer__close px-reset-button" onClick={onClose} aria-label="닫기">
          <span className="plc-viewer__chip plc-viewer__chip--square px-border px-shadow-small">
            <Icon name="close" size={20} color={PixelColor.ink} />
          </span>
        </button>
        <span
          className="plc-viewer__chip plc-viewer__count px-border px-shadow-small"
          style={{ ...PixelFont.labelSmall, color: PixelColor.ink }}
        >
          {index + 1}/{images.length}
        </span>
      </div>
    </div>,
    document.body,
  );
}

/** 두 손가락으로 키우고(1배 아래로는 안 줄어든다), 두 번 두드리면 원래 크기로. */
function ZoomableImage({ url }: { url: string }) {
  const [phase, setPhase] = useState<'loading' | 'success' | 'failure'>('loading');
  const [scale, setScale] = useState(1);
  const [animate, setAnimate] = useState(false);
  const slideRef = useRef<HTMLDivElement>(null);
  const scaleRef = useRef(1);

  const reset = () => {
    scaleRef.current = 1;
    setAnimate(true);
    setScale(1);
  };
  const resetRef = useRef(reset);
  resetRef.current = reset;

  // 두 손가락 확대는 기본 동작을 막아야 해서(passive: false) 직접 붙인다.
  useEffect(() => {
    const el = slideRef.current;
    if (!el) return;
    const distance = (t: TouchList) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
    let pinchStart = 0;
    let lastScale = 1;
    let tapStart: { x: number; y: number } | null = null;
    let lastTap = 0;

    const onStart = (e: TouchEvent) => {
      if (e.touches.length >= 2) {
        pinchStart = distance(e.touches);
        lastScale = scaleRef.current;
        tapStart = null;
      } else {
        tapStart = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      }
    };
    const onMove = (e: TouchEvent) => {
      if (e.touches.length >= 2 && pinchStart > 0) {
        if (e.cancelable) e.preventDefault();
        const next = Math.max(1, (lastScale * distance(e.touches)) / pinchStart);
        scaleRef.current = next;
        setAnimate(false);
        setScale(next);
        return;
      }
      const t = e.touches[0];
      if (tapStart && t && Math.hypot(t.clientX - tapStart.x, t.clientY - tapStart.y) > 10) tapStart = null;
    };
    const onEnd = (e: TouchEvent) => {
      if (e.touches.length < 2) pinchStart = 0;
      if (e.touches.length > 0) return;
      if (!tapStart) return;
      tapStart = null;
      const now = Date.now();
      if (now - lastTap < 300) {
        lastTap = 0;
        resetRef.current();
      } else {
        lastTap = now;
      }
    };
    el.addEventListener('touchstart', onStart, { passive: true });
    el.addEventListener('touchmove', onMove, { passive: false });
    el.addEventListener('touchend', onEnd, { passive: true });
    el.addEventListener('touchcancel', onEnd, { passive: true });
    return () => {
      el.removeEventListener('touchstart', onStart);
      el.removeEventListener('touchmove', onMove);
      el.removeEventListener('touchend', onEnd);
      el.removeEventListener('touchcancel', onEnd);
    };
  }, []);

  return (
    <div className="plc-viewer__slide" ref={slideRef} onDoubleClick={reset}>
      {phase !== 'failure' && (
        <img
          src={url}
          alt=""
          referrerPolicy="no-referrer"
          draggable={false}
          onLoad={() => setPhase('success')}
          onError={() => setPhase('failure')}
          className="plc-viewer__img"
          style={{
            opacity: phase === 'success' ? 1 : 0,
            transform: `scale(${scale})`,
            transition: animate ? 'transform 0.2s ease-in-out' : 'none',
          }}
        />
      )}
      {phase === 'loading' && (
        <span className="plc-viewer__status">
          <PixelSpinner color={PixelColor.surface} />
        </span>
      )}
      {phase === 'failure' && (
        <span className="plc-viewer__status">
          <Icon name="warn" size={40} color={PixelColor.surface} />
        </span>
      )}
    </div>
  );
}
