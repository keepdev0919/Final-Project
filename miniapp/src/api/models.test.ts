/**
 * 정답 판정·표시 문구·서버 키 변환.
 *
 * 왜 이 테스트가 있나 — 정답은 서버 왕복 없이 **단말에서** 판정한다(현장은 통신이 불안하다).
 * 판정이 틀리면 현장에서 맞는 답을 넣고도 진행이 막힌다. 또 서버는 snake_case 로 주므로
 * 키 변환이 틀리면 화면 전체가 조용히 빈다.
 */
import { describe, expect, it } from 'vitest';
import { step } from '../test/fixtures';
import { camelToSnake, convertKeys, snakeToCamel } from './client';
import {
  courseTitleHeadline,
  courseTitleRegion,
  distanceText,
  durationText,
  facilityDistanceText,
  failureText,
  isCorrect,
  partialCorrectCount,
} from './models';

describe('정답 판정 (MissionStep.isCorrect)', () => {
  it('CONFIRM 은 무엇이든 통과', () => {
    expect(isCorrect(step({ inputType: 'CONFIRM' }), null)).toBe(true);
  });

  it('CHOICE·DIRECTION 은 같은 문자열, NUMBER 는 같은 숫자', () => {
    expect(isCorrect(step({ inputType: 'CHOICE', answer: 'b' }), 'b')).toBe(true);
    expect(isCorrect(step({ inputType: 'CHOICE', answer: 'b' }), 'a')).toBe(false);
    expect(isCorrect(step({ inputType: 'DIRECTION', answer: 'RIGHT' }), 'RIGHT')).toBe(true);
    expect(isCorrect(step({ inputType: 'NUMBER', answer: 3 }), 3)).toBe(true);
    expect(isCorrect(step({ inputType: 'NUMBER', answer: 3 }), 4)).toBe(false);
  });

  it('SHORT_TEXT 는 공백·대소문자를 무시하고 허용 답안 중 하나면 통과 — 표기 차이로 막히지 않게', () => {
    const s = step({ inputType: 'SHORT_TEXT', answer: ['호령창', 'Horyeong Chang'] });
    expect(isCorrect(s, ' 호 령 창')).toBe(true);
    expect(isCorrect(s, 'horyeongchang')).toBe(true);
    expect(isCorrect(s, '창문')).toBe(false);
  });

  it('MATCH_ORDER — 순서 세우기는 순서까지, 짝 맞추기는 순서 무관', () => {
    const order = step({ inputType: 'MATCH_ORDER', answer: ['a', 'b', 'c'] });
    expect(isCorrect(order, ['a', 'b', 'c'])).toBe(true);
    expect(isCorrect(order, ['b', 'a', 'c'])).toBe(false);
    expect(partialCorrectCount(order, ['a', 'c', 'b'])).toBe(1);

    const pairs = step({
      inputType: 'MATCH_ORDER',
      answer: ['a>x', 'b>y'],
      matchTargets: [
        { id: 'x', label: 'X', image: null },
        { id: 'y', label: 'Y', image: null },
      ],
    });
    expect(isCorrect(pairs, ['b>y', 'a>x'])).toBe(true);
    expect(isCorrect(pairs, ['a>y', 'b>x'])).toBe(false);
    expect(partialCorrectCount(pairs, ['a>x', 'b>x'])).toBe(1);
  });

  it('오답 문구는 「틀렸습니다」가 아니다 — 원고가 비우면 공용 문구', () => {
    expect(failureText(step())).toBe('아직 아닌 것 같아요. 실제 대상을 다시 한번 살펴보세요.');
    expect(failureText(step({ failureFeedback: '다시 봐요' }))).toBe('다시 봐요');
  });
});

describe('표시 문구', () => {
  it('시간·거리', () => {
    expect(durationText({ estimatedMinutesMin: 60, estimatedMinutesMax: 75 })).toBe('60~75분');
    expect(durationText({ estimatedMinutesMin: 45, estimatedMinutesMax: 45 })).toBe('45분');
    expect(distanceText({ distanceMeters: 850 })).toBe('850m');
    expect(distanceText({ distanceMeters: 1000 })).toBe('약 1km');
    expect(distanceText({ distanceMeters: 1260 })).toBe('약 1.3km');
    expect(facilityDistanceText({ distanceM: 95 })).toBe('95m');
    expect(facilityDistanceText({ distanceM: 1200 })).toBe('1.2km');
  });

  it('코스 제목 쪼개기 — 권역·일수는 배지가 말하니 제목에서 뗀다', () => {
    expect(courseTitleRegion('동부 2일 · 성산일출봉 외 6곳')).toBe('동부');
    expect(courseTitleRegion('전체 3일 · 한라산 외 9곳')).toBe('전체');
    expect(courseTitleRegion('내가 지은 이름')).toBeNull();
    expect(courseTitleHeadline('동부 2일 · 성산일출봉 외 6곳', '동부')).toBe('성산일출봉 외 6곳');
    expect(courseTitleHeadline('내가 지은 이름', null)).toBe('내가 지은 이름');
  });
});

describe('서버 키 변환 (Swift convertFromSnakeCase / convertToSnakeCase)', () => {
  it('응답 키를 깊게 camelCase 로 — 값은 건드리지 않는다', () => {
    const out = convertKeys(
      { active_count: 1, pins: [{ place_key: 'a_b', home_visible: true, play: { card_summary: 'x_y' } }], bus_stops: [{ distance_m: 3 }] },
      snakeToCamel,
    );
    expect(out).toEqual({
      activeCount: 1,
      pins: [{ placeKey: 'a_b', homeVisible: true, play: { cardSummary: 'x_y' } }],
      busStops: [{ distanceM: 3 }],
    });
  });

  it('요청 본문 키는 snake_case 로', () => {
    expect(convertKeys({ durationDays: 2, courseId: 'C', playId: 'p' }, camelToSnake)).toEqual({
      duration_days: 2,
      course_id: 'C',
      play_id: 'p',
    });
  });
});
