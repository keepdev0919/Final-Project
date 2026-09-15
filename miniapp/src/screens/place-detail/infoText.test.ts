/**
 * 장소 정보 탭의 칩·카드·타일 가르기.
 *
 * 왜 이 테스트가 있나 — 이 화면은 KTO OpenAPI 관광정보가 실제로 보이는 곳이다(공모전 핵심).
 * KTO 원문은 모양이 제각각이라, 가르는 규칙이 조용히 틀어지면 「주차 무료」가 두 줄로 쪼개지거나
 * 「휠체어 접근 불가능」이 「가능」 타일로 잘못 나온다. 무장애 정보는 틀리면 없느니만 못하다.
 * 기대값은 iOS PlaceInfoSections.swift 의 카멜리아힐 미리보기와 같다.
 */
import { describe, expect, it } from 'vitest';
import type { PlaceDetail } from '../../api';
import {
  availabilityRemainder,
  parsePlaceInfoText,
  priceTableOf,
  sourceLines,
  splitAccessibility,
  splitUsage,
  usageRows,
} from './infoText';

const FEE =
  '[개인]\n- 성인 12,000원\n- 청소년/경로/군인 10,000원\n- 어린이/장애인/보훈대상/4.3유족 9,000원\n' +
  '[단체(30명 이상)]\n- 성인 10,000원\n- 청소년/경로/군인 9,000원\n- 어린이/장애인/보훈대상/4.3유족 8,000원\n' +
  '※ 자세한 입장료는 공식 홈페이지 참조';

function detail(over: Partial<PlaceDetail> = {}): PlaceDetail {
  return {
    name: '카멜리아힐',
    overview: '',
    images: [],
    address: '',
    tel: '',
    openTime: '',
    restDate: '',
    useFee: '',
    parking: '',
    info: [],
    accessibility: [],
    ...over,
  };
}

describe('KTO 원문 파서', () => {
  it('[머리] · - 항목 · ※ 각주를 가른다', () => {
    const t = parsePlaceInfoText(FEE);
    expect(t.groups.map((g) => g.header)).toEqual(['개인', '단체(30명 이상)']);
    expect(t.groups[0].items[0]).toBe('성인 12,000원');
    expect(t.footnotes).toEqual(['자세한 입장료는 공식 홈페이지 참조']);
  });

  it('같은 구분의 가격 묶음은 표가 된다', () => {
    const table = priceTableOf(parsePlaceInfoText(FEE));
    expect(table?.columns).toEqual(['개인', '단체(30명 이상)']);
    expect(table?.rows[0]).toEqual({ name: '성인', prices: ['12,000', '10,000'] });
  });

  it('구분이 다르면 표로 만들지 않는다', () => {
    expect(priceTableOf(parsePlaceInfoText('[개인]\n- 성인 5,000원\n[단체]\n- 어른 4,000원'))).toBeNull();
  });

  it('머리가 없는 줄은 이름 없는 묶음에 들어간다', () => {
    const t = parsePlaceInfoText('매월 첫째 주 월요일');
    expect(t.groups).toEqual([{ header: null, items: ['매월 첫째 주 월요일'] }]);
  });
});

describe('이용 정보 — 칩과 카드', () => {
  it('카멜리아힐: 주차+주차요금은 「주차 무료」 칩 하나, 긴 표는 카드', () => {
    const rows = usageRows(
      detail({
        openTime: '[하절기]\n- 08:30~18:30',
        restDate: '연중무휴',
        parking: '가능',
        info: [
          { label: '입장료', value: FEE },
          { label: '주차요금', value: '무료' },
          { label: '화장실', value: '있음' },
        ],
      }),
    );
    const { chips, cards } = splitUsage(rows);
    expect(chips.map((c) => c.text)).toEqual(['연중무휴', '주차 무료', '화장실']);
    expect(cards.map((c) => c.label)).toEqual(['운영시간', '입장료']);
  });

  it('이용팁에 입장료가 있으면 반복정보의 입장료는 뺀다', () => {
    const rows = usageRows(detail({ useFee: '무료', info: [{ label: '입장료', value: '1,000원' }] }));
    expect(rows).toEqual([{ label: '입장료', value: '무료' }]);
  });

  it('대수가 붙은 주차는 칩으로 접지 않는다', () => {
    const { chips, cards } = splitUsage([{ label: '주차', value: '가능 (약 대형 60대, 소형 75대)' }]);
    expect(chips).toEqual([]);
    expect(cards).toHaveLength(1);
  });

  it('주차 불가는 칩', () => {
    expect(splitUsage([{ label: '주차', value: '불가' }]).chips[0].text).toBe('주차 불가');
  });
});

describe('무장애 정보 — 타일과 설명', () => {
  it('부정어가 있으면 절대 타일로 만들지 않는다', () => {
    expect(availabilityRemainder('휠체어 접근 불가능')).toBeNull();
    expect(availabilityRemainder('가능하나 계단 있음')).toBeNull();
  });

  it('꼬리는 설명 상자로, 「있음」 짧은 문장은 타일 하나', () => {
    const { tiles, notes } = splitAccessibility([
      { label: '장애인 주차', value: '장애인 주차장 있음' },
      { label: '휠체어 대여', value: '대여가능(1대/관리사무소)' },
      { label: '기타 편의', value: '일부 박석 구간이 있어 휠체어 이용시 주의' },
    ]);
    expect(tiles.map((t) => t.label)).toEqual(['장애인 주차', '휠체어 대여']);
    expect(notes).toEqual([
      { label: '휠체어 대여', text: '1대/관리사무소', warns: false },
      { label: '기타 편의', text: '일부 박석 구간이 있어 휠체어 이용시 주의', warns: true },
    ]);
  });
});

describe('출처', () => {
  it('실제로 쓴 출처만 적는다', () => {
    const nearby = { toilets: [], busStops: [{ name: '정류장', distanceM: 90, lat: 0, lng: 0, openTime: null, accessible: null }] };
    expect(sourceLines(detail({ address: '제주' }), nearby)).toEqual([
      '관광정보 출처: ⓒ한국관광공사',
      '정류장 출처: 국토교통부(TAGO)',
    ]);
    expect(sourceLines(detail(), undefined)).toEqual([]);
  });
});
