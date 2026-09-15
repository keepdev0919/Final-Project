/**
 * 한 줄 글자 — SwiftUI `.lineLimit(1).minimumScaleFactor(x)` 이식.
 *
 * 자리가 모자라면 글자 크기를 `minScale` 배까지 줄이고, 그래도 넘치면 끝을 「…」로 자른다.
 * 자리가 넉넉하면 원래 크기 그대로다 — 줄이는 건 모자랄 때만이다.
 *
 * 바깥 상자는 블록(가로 가득)이어야 한다. 남은 폭을 바깥 상자의 폭으로 잰다.
 */
import { useLayoutEffect, useRef, useState, type CSSProperties } from 'react';

export function FitText({
  text,
  fontSize,
  minScale,
  style,
  className,
}: {
  text: string;
  /** 원래 크기 px (Swift 폰트 크기) */
  fontSize: number;
  /** Swift minimumScaleFactor */
  minScale: number;
  style?: CSSProperties;
  className?: string;
}) {
  const outerRef = useRef<HTMLSpanElement>(null);
  const innerRef = useRef<HTMLSpanElement>(null);
  const scaleRef = useRef(1);
  const [scale, setScale] = useState(1);

  useLayoutEffect(() => {
    const outer = outerRef.current;
    const inner = innerRef.current;
    if (!outer || !inner) return;
    const fit = () => {
      const avail = outer.clientWidth;
      if (avail <= 0) return;
      // 지금 크기에서 잰 글자 폭을 원래 크기 기준으로 되돌린다 (글자 폭은 크기에 비례).
      const natural = inner.offsetWidth / scaleRef.current;
      const next = natural <= avail ? 1 : Math.max(minScale, Math.floor((avail / natural) * 1000) / 1000);
      if (Math.abs(next - scaleRef.current) > 0.001) {
        scaleRef.current = next;
        setScale(next);
      }
    };
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(outer);
    // 갈무리 글꼴이 늦게 도착하면 폭이 달라진다.
    document.fonts?.ready.then(fit).catch(() => undefined);
    return () => ro.disconnect();
  }, [text, fontSize, minScale]);

  return (
    <span
      ref={outerRef}
      className={className}
      style={{
        display: 'block',
        width: '100%',
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        ...style,
        fontSize: fontSize * scale,
      }}
    >
      <span ref={innerRef}>{text}</span>
    </span>
  );
}
