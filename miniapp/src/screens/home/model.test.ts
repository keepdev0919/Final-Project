import { describe, expect, it } from 'vitest';
import type { PlayMapPin } from '../../api';
import { distanceShort, homeQuestPins } from './model';

const pin = (placeKey: string, status: PlayMapPin['status'], homeVisible: boolean): PlayMapPin => ({
  placeId: placeKey,
  placeKey,
  placeName: placeKey,
  lat: 33.4,
  lng: 126.5,
  status,
  thumbnail: null,
  play: null,
  homeVisible,
});

describe('homeQuestPins', () => {
  // 콘텐츠 제작 착수 전 후보지(homeVisible=false)가 퀘스트 카드로 보이면 안 된다.
  it('homeVisible 이 아닌 곳은 홈에 올리지 않는다', () => {
    const out = homeQuestPins([pin('a', 'preparing', false), pin('b', 'preparing', true), pin('c', 'active', false)]);
    expect(out.map((p) => p.placeKey)).toEqual(['b']);
  });

  // 플레이할 수 있는 것부터, 같은 상태 안에서는 서버가 준 순서를 지킨다.
  it('active 가 먼저, 같은 상태 안에서는 서버 순서', () => {
    const out = homeQuestPins([
      pin('p1', 'preparing', true),
      pin('a1', 'active', true),
      pin('p2', 'preparing', true),
      pin('a2', 'active', true),
    ]);
    expect(out.map((p) => p.placeKey)).toEqual(['a1', 'a2', 'p1', 'p2']);
  });
});

describe('distanceShort', () => {
  // 카드는 「약」 없이 「1km」로 쓴다 (PLAY 상세의 「약 1km」와 다르다).
  it('1km 미만은 m, 이상은 km (.0 은 뗀다)', () => {
    expect(distanceShort({ distanceMeters: 850 })).toBe('850m');
    expect(distanceShort({ distanceMeters: 1000 })).toBe('1km');
    expect(distanceShort({ distanceMeters: 1260 })).toBe('1.3km');
    expect(distanceShort({ distanceMeters: 2400 })).toBe('2.4km');
  });
});
