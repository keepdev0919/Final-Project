/** 당겨서 새로고침 표시 — 몸짓은 `usePullToRefresh.ts`. */
import { PixelSpinner } from './PixelComponents';
import { PixelSpacing } from './tokens';
import { PULL_THRESHOLD, type PullToRefreshState } from './usePullToRefresh';

/**
 * 화면 맨 위 당김 표시. iOS `.refreshable` 처럼 내용을 아래로 밀어내며 스피너가 드러나고,
 * 새로고침이 끝날 때까지 48px(xxxl) 자리에 떠 있다. 화면 루트의 **첫 자식**으로 둔다.
 */
export function PullToRefreshIndicator({ pull, dragging, refreshing }: PullToRefreshState) {
  const height = refreshing ? PixelSpacing.xxxl : pull;
  return (
    <div
      className="px-ptr"
      data-dragging={dragging}
      style={{ height }}
      role={refreshing ? 'status' : undefined}
      aria-label={refreshing ? '새로고침 중' : undefined}
      aria-hidden={!refreshing}
    >
      {(refreshing || pull > 0) && (
        <span style={{ opacity: refreshing ? 1 : Math.min(pull / PULL_THRESHOLD, 1) }}>
          <PixelSpinner />
        </span>
      )}
    </div>
  );
}
