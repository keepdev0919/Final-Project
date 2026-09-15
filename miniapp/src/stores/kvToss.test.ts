/**
 * SDK 가 답하지 않던 세션에 localStorage 로 대신 쓴 값을, 다음에 SDK 가 살아났을 때 합치는 규칙.
 *
 * 왜 이 테스트가 있나 — 이 합치기가 조용히 틀리면 「앱을 다시 켰더니 진행이 사라졌다」가 된다
 * (출시 가이드: 종료했다 다시 들어와도 필요한 데이터가 유지돼요). 현장 60~75분짜리 PLAY 진행이다.
 */
import { describe, expect, it } from 'vitest';
import { mergeFallbackValue } from './kvToss';

const j = JSON.stringify;

describe('localStorage 로 대신 쓴 값을 SDK 로 옮길 때', () => {
  it('SDK 에 값이 없으면 localStorage 값을 그대로 옮긴다', () => {
    expect(mergeFallbackValue(null, j({ a: 1 }))).toBe(j({ a: 1 }));
  });

  it('PLAY 진행은 PLAY 별로 합치고, 같은 PLAY 는 더 늦게 저장한 쪽을 남긴다', () => {
    const sdk = { seongeup: { playId: 'seongeup', updatedAt: 100 }, bijarim: { playId: 'bijarim', updatedAt: 500 } };
    const loc = { seongeup: { playId: 'seongeup', updatedAt: 300 }, bijarim: { playId: 'bijarim', updatedAt: 200 }, other: { playId: 'other', updatedAt: 1 } };
    expect(JSON.parse(mergeFallbackValue(j(sdk), j(loc)))).toEqual({
      seongeup: loc.seongeup,
      bijarim: sdk.bijarim, // SDK 쪽이 더 새롭다
      other: loc.other,
    });
  });

  it('담은 코스는 합치고, 같은 코스(sourceCourseId)는 하나만 남긴다', () => {
    const sdk = [
      { id: 'u1', sourceCourseId: 'c1', title: '옛 이름' },
      { id: 'u2', sourceCourseId: 'c2', title: 'B' },
    ];
    const loc = [
      { id: 'u9', sourceCourseId: 'c1', title: '새 이름' },
      { id: 'u3', sourceCourseId: null, title: 'C' },
    ];
    const merged = JSON.parse(mergeFallbackValue(j(sdk), j(loc))) as { title: string }[];
    expect(merged.map((c) => c.title)).toEqual(['B', '새 이름', 'C']);
  });

  it('값 하나짜리 설정은 localStorage 쪽(더 나중 세션)을 쓴다', () => {
    expect(mergeFallbackValue(j(false), j(true))).toBe(j(true));
  });

  it('JSON 이 아니면 SDK 값을 건드리지 않는다', () => {
    expect(mergeFallbackValue(j({ a: 1 }), '{broken')).toBe(j({ a: 1 }));
  });
});
