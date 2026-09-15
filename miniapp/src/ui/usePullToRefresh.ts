/**
 * 당겨서 새로고침 — SwiftUI `.refreshable` 자리 (퀘스트 탭 · 코스 탭이 같이 쓴다).
 *
 * 토스 웹뷰의 당겨서 새로고침은 iOS 에서 기본으로 켜져 있지만(docs: /documentation/integration/props),
 * 그건 웹뷰를 통째로 다시 띄운다(러너의 풀던 미션이 사라진다). 그래서 `apps-in-toss.config.ts` 의
 * `webView.pullToRefreshEnabled: false` 로 끄고, 여기서 화면 안 몸짓으로 받는다. 두 탭은 실패하면 「아래로 당겨 다시 시도해보세요」
 * 「당겨서 새로고침해 주세요」라고 안내하므로 화면 안에서 같은 몸짓을 받는다.
 *
 * 스크롤 상자(`.px-app__main`)가 맨 위에 있을 때 아래로 끌면 당김 거리를 돌려주고,
 * 기준(PULL_THRESHOLD)을 넘겨 손을 떼면 onRefresh 를 부른다. 끝날 때까지 refreshing = true.
 *
 *   const rootRef = useRef<HTMLDivElement>(null);
 *   const ptr = usePullToRefresh(rootRef, reload);
 *   <div ref={rootRef} className="px-screen">
 *     <PullToRefreshIndicator {...ptr} />
 *     …
 */
import { useEffect, useLayoutEffect, useRef, useState, type RefObject } from 'react';

/** 손을 뗐을 때 새로고침이 걸리는 당김 거리 (화면에 보이는 높이 기준) */
export const PULL_THRESHOLD = 64;
/** 당김 표시가 커지는 최대 높이 */
const PULL_MAX = 96;
/** 손가락 이동 대비 표시 높이 (끌수록 무거워지는 느낌) */
const PULL_RESISTANCE = 0.5;

export interface PullToRefreshState {
  /** 지금 당겨진 높이(px) */
  pull: number;
  /** 손가락이 닿아 끄는 중인지 (끄는 동안은 높이가 손을 따라가고, 놓으면 부드럽게 접힌다) */
  dragging: boolean;
  /** onRefresh 가 끝나기를 기다리는 중 */
  refreshing: boolean;
}

export function usePullToRefresh(
  rootRef: RefObject<HTMLElement | null>,
  onRefresh: () => Promise<unknown>,
): PullToRefreshState {
  const [pull, setPull] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const latest = useRef({ onRefresh, refreshing });
  useLayoutEffect(() => {
    latest.current = { onRefresh, refreshing };
  });

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const scroller = root.closest<HTMLElement>('.px-app__main');
    const scrollTop = () => (scroller ? scroller.scrollTop : (document.scrollingElement?.scrollTop ?? 0));

    let startY: number | null = null;
    let current = 0;

    const reset = () => {
      startY = null;
      current = 0;
      setPull(0);
      setDragging(false);
    };

    const onStart = (e: TouchEvent) => {
      if (latest.current.refreshing || e.touches.length !== 1 || scrollTop() > 0) {
        startY = null;
        return;
      }
      startY = e.touches[0].clientY;
      current = 0;
    };

    const onMove = (e: TouchEvent) => {
      if (startY === null) return;
      if (e.touches.length !== 1) {
        reset();
        return;
      }
      const dy = e.touches[0].clientY - startY;
      if (dy <= 0 || scrollTop() > 0) {
        // 위로 밀었다 — 평소 스크롤이다. 당김은 취소.
        if (current > 0) reset();
        else startY = dy < 0 ? null : startY;
        return;
      }
      // 맨 위에서 아래로 끄는 중 — 스크롤 상자가 튕기지 않게 막고 표시를 늘린다.
      if (e.cancelable) e.preventDefault();
      current = Math.min(dy * PULL_RESISTANCE, PULL_MAX);
      setDragging(true);
      setPull(current);
    };

    const onEnd = () => {
      if (startY === null) return;
      const trigger = current >= PULL_THRESHOLD;
      reset();
      if (!trigger || latest.current.refreshing) return;
      setRefreshing(true);
      latest.current
        .onRefresh()
        .catch(() => undefined)
        .finally(() => setRefreshing(false));
    };

    root.addEventListener('touchstart', onStart, { passive: true });
    root.addEventListener('touchmove', onMove, { passive: false });
    root.addEventListener('touchend', onEnd);
    root.addEventListener('touchcancel', onEnd);
    return () => {
      root.removeEventListener('touchstart', onStart);
      root.removeEventListener('touchmove', onMove);
      root.removeEventListener('touchend', onEnd);
      root.removeEventListener('touchcancel', onEnd);
    };
  }, [rootRef]);

  return { pull, dragging, refreshing };
}
