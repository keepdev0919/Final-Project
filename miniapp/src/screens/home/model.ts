/** 퀘스트 탭이 서버 응답에서 뽑아 쓰는 값 (HomeViewModel · PlaySummary 확장 이식). */
import type { PlayMapPin, PlaySummary } from '../../api';

/**
 * 홈 퀘스트 카드에 올릴 핀.
 * 지도에는 다 뜨지만 홈은 `homeVisible` 인 곳만 — 콘텐츠 제작에 아직 착수하지 않은
 * 후보지까지 퀘스트로 보이면 안 된다. 플레이할 수 있는 것부터, 같은 상태 안에서는 서버 순서.
 */
export function homeQuestPins(pins: readonly PlayMapPin[]): PlayMapPin[] {
  const visible = pins.filter((p) => p.homeVisible);
  return [...visible.filter((p) => p.status === 'active'), ...visible.filter((p) => p.status !== 'active')];
}

/** 시안은 거리를 「1km」로 쓴다 — 「약」을 붙이지 않는다. (Swift `PlaySummary.distanceShort`) */
export function distanceShort(p: Pick<PlaySummary, 'distanceMeters'>): string {
  const m = p.distanceMeters;
  return m < 1000 ? `${m}m` : `${(m / 1000).toFixed(1)}km`.replace('.0km', 'km');
}
