/**
 * PLAY 진행 로직 — START → 미션 → 발견 → 이야기 → FINAL → CLEAR.
 *
 * 왜 이 테스트가 있나 — 러너 화면은 눌러 보기 전엔 멀쩡해 보인다. 그런데 이 흐름이 조용히
 * 깨지면 (1) CLEAR 기록이 안 남아 홈 카드가 「이어서 하기」에 머물거나, (2) 저장이 안 돼
 * 현장에서 앱을 내렸다가 대장간집부터 다시 하거나, (3) 막힌 미션을 넘길 길이 없어진다.
 * 셋 다 60~75분짜리 현장 PLAY 를 망치는 고장이라 여기서 지킨다.
 */
import { describe, expect, it } from 'vitest';
import { makePlay, mission, step } from '../../test/fixtures';
import type { Play } from '../../api/types';
import { createPlayProgress } from '../../stores/playProgress';
import {
  clearStats,
  currentLine,
  currentMission,
  elapsedText,
  initRunner,
  ktoSourceLabel,
  missionSpeech,
  nextLines,
  pointNumber,
  reduceRunner,
  reportTarget,
  speechKey,
  speechOf,
  speechOrder,
  waitsForSpeech,
  type RunnerAction,
  type RunnerState,
} from './runnerLogic';

/** 성읍과 같은 모양 — 성공 문구가 있는 Step · 발견 없는 미션 · 이야기 · 기록 칸 · FINAL(순서 세우기). */
function seongeup(): Play {
  const base = makePlay();
  return {
    ...base,
    progressRecords: [
      { id: 'boundary', label: '경계' },
      { id: 'entrance', label: '출입' },
    ],
    points: [
      {
        ...base.points[0],
        id: 'p1',
        navigationText: '주차장에서 안쪽으로 들어가 봐!',
        objective: '대문이 없는 집',
        missions: [
          // 발견 없음 · 성공 문구 있음 (성읍 m01)
          mission('m01', {
            prompt: '대문이 보여?',
            steps: [step({ inputType: 'CHOICE', prompt: '', answer: 'no', successFeedback: '맞아!' })],
            hints: [{ text: 'h1' }, { text: 'h2' }],
          }),
          // CONFIRM → CHOICE 두 Step · 발견 · 기록 칸 · 이야기 (성읍 m02)
          mission('m02', {
            prompt: '돌기둥을 찾아봐',
            steps: [step({ inputType: 'CONFIRM', prompt: '찾았어?' }), step({ inputType: 'CHOICE', prompt: '구멍은 몇 개?', answer: 'pole' })],
            hints: [{ text: 'h1' }, { text: 'h2' }],
            discovery: { title: '정주석', body: '정주석이야' },
            progressReward: 'boundary',
          }),
        ],
      },
      {
        ...base.points[1],
        id: 'p2',
        missions: [
          mission('m03', {
            steps: [step({ inputType: 'CHOICE', answer: 'gate' })],
            hints: [{ text: 'h1' }],
            discovery: { title: '', body: '올레야' },
            progressReward: 'entrance',
          }),
        ],
      },
    ],
    stories: [{ id: 's01', title: '경계 이야기', script: '정주석 이야기', sources: [{ kind: 'odii', ref: '성읍', note: '' }], unlockAfterMission: 'm02' }],
    final: {
      id: 'final',
      title: '생활기록 복원',
      prompt: '순서대로 이어봐',
      step: step({
        inputType: 'MATCH_ORDER',
        options: [
          { id: 'a', label: 'A', image: null },
          { id: 'b', label: 'B', image: null },
          { id: 'c', label: 'C', image: null },
        ],
        answer: ['a', 'b', 'c'],
        failureFeedback: '다시 생각해봐.',
      }),
      story: null,
      hints: [{ text: 'f1' }, { text: 'f2' }],
    },
    clear: { title: '복원 완료', body: '네가 복원한 건 살았던 방식이야.' },
  };
}

function run(play: Play, s: RunnerState, ...actions: RunnerAction[]): RunnerState {
  return actions.reduce((acc, a) => reduceRunner(play, acc, a), s);
}

describe('처음부터 CLEAR 까지', () => {
  it('정답 경로를 따라가면 FINAL 을 거쳐 CLEAR 가 되고 finalCleared 가 남는다', () => {
    const play = seongeup();
    let s = initRunner(play, null, 0);
    expect(s.phase).toBe('pointIntro');
    expect(pointNumber(play, s)).toBe(1);

    s = run(play, s, { type: 'arrived' });
    expect(s.phase).toBe('mission');

    // m01 — 성공 문구가 있으니 먼저 듣는다
    s = run(play, s, { type: 'submit', answer: 'no' });
    expect(s.phase).toBe('stepFeedback');
    expect(s.pendingSuccess).toBe('맞아!');
    expect(currentLine(play, s)).toBe('feedback:m01:0');

    // 발견·이야기 없는 미션 → 같은 Point 의 다음 미션으로 곧장 (도착 안내 없이)
    s = run(play, s, { type: 'afterStepFeedback' });
    expect(s.phase).toBe('mission');
    expect(currentMission(play, s)?.id).toBe('m02');
    expect(s.progress.completedMissionIds).toEqual(['m01']);

    // m02 — Step 두 개
    s = run(play, s, { type: 'submit', answer: null });
    expect(s.phase).toBe('mission');
    expect(s.stepIndex).toBe(1);
    s = run(play, s, { type: 'submit', answer: 'pole' });
    expect(s.phase).toBe('discovery');
    expect(s.justEarnedRecord).toBe('경계');
    expect(s.progress.discoveredRecordIds).toEqual(['boundary']);
    expect(s.lastSkipped).toBe(false);

    s = run(play, s, { type: 'afterDiscovery' });
    expect(s.phase).toBe('story');
    expect(s.pendingStory?.id).toBe('s01');

    // 다른 Point → 도착 안내부터
    s = run(play, s, { type: 'afterStory' });
    expect(s.phase).toBe('pointIntro');
    expect(pointNumber(play, s)).toBe(2);

    s = run(play, s, { type: 'arrived' }, { type: 'submit', answer: 'gate' });
    expect(s.phase).toBe('discovery');
    // 이야기가 없는 마지막 미션 → FINAL
    s = run(play, s, { type: 'afterDiscovery' });
    expect(s.phase).toBe('finalStage');
    expect(s.progress.finalCleared).toBe(false);

    s = run(play, s, { type: 'submitFinal', answer: ['a', 'b', 'c'] });
    expect(s.phase).toBe('clear');
    expect(s.progress.finalCleared).toBe(true);
    expect(s.progress.completedMissionIds).toEqual(['m01', 'm02', 'm03']);
  });

  it('FINAL 이 없으면 마지막 미션 다음이 곧 CLEAR 다', () => {
    const play = { ...seongeup(), final: null };
    const s = run(play, initRunner(play, null, 0), { type: 'skip' }, { type: 'skip' }, { type: 'afterDiscovery' }, { type: 'afterStory' }, { type: 'skip' }, { type: 'afterDiscovery' });
    expect(s.phase).toBe('clear');
    expect(s.progress.finalCleared).toBe(true);
  });

  it('FINAL 뒤 이야기가 있으면 이야기를 듣고 CLEAR 로 간다 (FINAL 로 되돌아가지 않는다)', () => {
    const base = seongeup();
    const play: Play = { ...base, final: { ...base.final!, story: { id: 'sf', title: '', script: '끝 이야기', sources: [], unlockAfterMission: '' } } };
    let s = initRunner(play, null, 0);
    s = { ...s, phase: 'finalStage', missionIndex: 2 };
    s = run(play, s, { type: 'submitFinal', answer: ['a', 'b', 'c'] });
    expect(s.phase).toBe('story');
    expect(currentLine(play, s)).toBe('story:sf');
    expect(s.progress.finalCleared).toBe(false);
    s = run(play, s, { type: 'afterStory' });
    expect(s.phase).toBe('clear');
    expect(s.progress.finalCleared).toBe(true);
  });
});

describe('막히지 않는다', () => {
  it('오답은 문구만 띄우고 제자리에 있다 — 원고 문구가 없으면 공용 문구', () => {
    const play = seongeup();
    const s = run(play, initRunner(play, null, 0), { type: 'arrived' }, { type: 'submit', answer: 'yes' });
    expect(s.phase).toBe('mission');
    expect(s.wrongMessage).toBe('아직 아닌 것 같아요. 실제 대상을 다시 한번 살펴보세요.');
    // 다시 맞히면 오답 문구가 걷힌다
    expect(run(play, s, { type: 'submit', answer: 'no' }).wrongMessage).toBeNull();
  });

  it('힌트는 원고에 있는 개수까지만 열린다', () => {
    const play = seongeup();
    const s = run(play, initRunner(play, null, 0), { type: 'arrived' }, { type: 'showHint' }, { type: 'showHint' }, { type: 'showHint' });
    expect(s.hintLevel).toBe(2);
  });

  it('건너뛰기는 진행을 채우지만 「건너뛴 미션」으로 따로 센다', () => {
    const play = seongeup();
    let s = run(play, initRunner(play, null, 0), { type: 'arrived' }, { type: 'submit', answer: 'no' }, { type: 'afterStepFeedback' });
    s = run(play, s, { type: 'skip' });
    expect(s.phase).toBe('discovery');
    expect(s.lastSkipped).toBe(true); // 배지가 「NEW DISCOVERY」 대신 「정답」
    expect(s.progress.skippedMissionIds).toEqual(['m02']);
    expect(s.progress.completedMissionIds).toEqual(['m01', 'm02']);
    expect(s.progress.discoveredRecordIds).toEqual(['boundary']);
  });

  // 건너뛰는 사람은 대개 오답을 낸 사람이다. 앞 미션의 빨간 오답 상자가 아직 풀지도 않은
  // 다음 미션·FINAL 에 떠 있으면 「내가 또 틀렸나?」로 읽힌다.
  it('오답 뒤 건너뛰면 같은 Point 의 다음 미션에 앞 미션 오답 문구가 남지 않는다', () => {
    const play = seongeup();
    let s = run(play, initRunner(play, null, 0), { type: 'arrived' }, { type: 'submit', answer: 'yes' });
    expect(s.wrongMessage).not.toBeNull();
    s = run(play, s, { type: 'showHint' }, { type: 'showHint' }, { type: 'skip' });
    // m01 은 발견·이야기가 없어 곧장 같은 Point 의 m02 로 간다 (도착 안내가 문구를 지워 주지 않는 길)
    expect(s.phase).toBe('mission');
    expect(currentMission(play, s)?.id).toBe('m02');
    expect(s.wrongMessage).toBeNull();
  });

  it('오답 뒤 건너뛰면 FINAL 에 앞 미션 오답 문구가 남지 않는다', () => {
    const play = seongeup();
    let s = run(play, initRunner(play, null, 0), { type: 'arrived' }, { type: 'submit', answer: 'no' }, { type: 'afterStepFeedback' });
    s = run(play, s, { type: 'skip' }, { type: 'afterDiscovery' }, { type: 'afterStory' }, { type: 'arrived' });
    s = run(play, s, { type: 'submit', answer: 'wrong' });
    expect(s.wrongMessage).not.toBeNull();
    s = run(play, s, { type: 'skip' }, { type: 'afterDiscovery' });
    expect(s.phase).toBe('finalStage');
    expect(s.wrongMessage).toBeNull();
  });

  it('FINAL 오답은 몇 개가 맞았는지 먼저 말해준다', () => {
    const play = seongeup();
    let s = initRunner(play, null, 0);
    s = { ...s, phase: 'finalStage' };
    s = run(play, s, { type: 'submitFinal', answer: ['a', 'c', 'b'] });
    expect(s.phase).toBe('finalStage');
    expect(s.wrongMessage).toBe('3개 중 1개는 순서가 맞았어! 다시 생각해봐.');
    s = run(play, s, { type: 'showFinalHint' }, { type: 'showFinalHint' }, { type: 'showFinalHint' });
    expect(s.hintLevel).toBe(2);
  });

  it('개발용 바로 통과는 정답과 같은 길을 탄다', () => {
    const play = seongeup();
    const s = run(play, { ...initRunner(play, null, 0), phase: 'finalStage' }, { type: 'debugPassFinal' });
    expect(s.phase).toBe('clear');
    expect(s.progress.finalCleared).toBe(true);
  });
});

describe('저장 시점과 이어하기', () => {
  it('progress 는 미션을 끝낼 때와 CLEAR 때만 새 객체가 된다 (= 그때만 저장한다)', () => {
    const play = seongeup();
    const s0 = run(play, initRunner(play, null, 0), { type: 'arrived' });
    const s1 = run(play, s0, { type: 'showHint' }, { type: 'submit', answer: 'wrong' });
    expect(s1.progress).toBe(s0.progress); // 힌트·오답은 저장하지 않는다
    const s2 = run(play, s1, { type: 'submit', answer: 'no' });
    expect(s2.progress).toBe(s0.progress); // 성공 문구를 듣는 중 — 아직 미션이 안 끝났다
    const s3 = run(play, s2, { type: 'afterStepFeedback' });
    expect(s3.progress).not.toBe(s0.progress);
  });

  it('CLEAR 전 기록은 완료한 미션 다음 Point 안내부터 이어받는다', () => {
    const play = seongeup();
    const saved = { ...createPlayProgress(play, 5), completedMissionIds: ['m01', 'm02'], discoveredRecordIds: ['boundary'] };
    const s = initRunner(play, saved, 999);
    expect(s.phase).toBe('pointIntro');
    expect(currentMission(play, s)?.id).toBe('m03');
    expect(s.progress.startedAt).toBe(5); // 걸린 시간은 처음 시작한 때부터
  });

  it('미션을 다 끝내고 FINAL 에서 나갔으면 FINAL 부터 연다', () => {
    const play = seongeup();
    const saved = { ...createPlayProgress(play, 5), completedMissionIds: ['m01', 'm02', 'm03'] };
    expect(initRunner(play, saved).phase).toBe('finalStage');
  });

  it('이미 CLEAR 한 기록은 이어받지 않는다 — 「다시 하기」는 처음부터', () => {
    const play = seongeup();
    const saved = { ...createPlayProgress(play, 5), completedMissionIds: ['m01', 'm02', 'm03'], finalCleared: true };
    const s = initRunner(play, saved, 999);
    expect(s.phase).toBe('pointIntro');
    expect(s.missionIndex).toBe(0);
    expect(s.progress.completedMissionIds).toEqual([]);
    expect(s.progress.startedAt).toBe(999);
  });
});

describe('곱딱이 대사', () => {
  it('첫 Step 은 미션 안내 + 질문, 뒤 Step 은 질문만', () => {
    const m = mission('m', { prompt: '안내' });
    expect(missionSpeech(m, step({ prompt: '질문' }), 0)).toBe('안내\n\n질문');
    expect(missionSpeech(m, step({ prompt: '' }), 0)).toBe('안내');
    expect(missionSpeech(m, step({ prompt: '질문2' }), 1)).toBe('질문2');
    expect(missionSpeech(m, step({ prompt: '' }), 1)).toBe('안내');
  });

  it('도착 안내는 navigationText, 없으면 objective', () => {
    const play = seongeup();
    expect(speechOf(play, initRunner(play, null))?.text).toBe('주차장에서 안쪽으로 들어가 봐!');
    play.points[0].navigationText = '';
    expect(speechOf(play, initRunner(play, null))?.text).toBe('대문이 없는 집');
  });

  it('대사 열쇠 순서는 서버 resolve_line 형식이고, 다음 두 줄을 미리 받는다', () => {
    const play = seongeup();
    expect(speechOrder(play)).toEqual([
      'point:p1',
      'mission:m01:0',
      'feedback:m01:0',
      'mission:m02:0',
      'mission:m02:1',
      'discovery:m02',
      'story:s01',
      'point:p2',
      'mission:m03:0',
      'discovery:m03',
      'final',
      'clear',
    ]);
    expect(nextLines(play, 'mission:m02:1')).toEqual(['discovery:m02', 'story:s01']);
    expect(nextLines(play, 'clear')).toEqual([]);
    expect(nextLines(play, 'nope')).toEqual([]);
  });

  it('미션·FINAL·발견은 말이 끝난 뒤 위 칸을 띄우고, 나머지는 같이 띄운다', () => {
    expect(['mission', 'finalStage', 'discovery'].every((p) => waitsForSpeech(p as never))).toBe(true);
    expect(['pointIntro', 'stepFeedback', 'story', 'clear'].some((p) => waitsForSpeech(p as never))).toBe(false);
  });

  it('Step 이 바뀌면 말 열쇠가 바뀐다 (두 번째 질문도 다시 기다린다)', () => {
    const play = seongeup();
    const s = run(play, initRunner(play, null), { type: 'arrived' }, { type: 'submit', answer: 'no' }, { type: 'afterStepFeedback' });
    const k0 = speechKey(play, s);
    const k1 = speechKey(play, run(play, s, { type: 'submit', answer: null }));
    expect(k0).not.toBe(k1);
    // 오답은 열쇠를 바꾸지 않는다 — 같은 말을 처음부터 다시 읽지 않는다
    expect(speechKey(play, run(play, s, { type: 'showHint' }))).toBe(k0);
  });

  it('출처는 관광공사(오디) 것만 표시한다', () => {
    const story = { id: 's', title: '', script: '', unlockAfterMission: '', sources: [{ kind: 'encykorea', ref: 'x', note: '' }, { kind: 'odii', ref: '성읍', note: '' }] };
    expect(ktoSourceLabel(story)).toBe('출처: ⓒ한국관광공사 (성읍)');
    expect(ktoSourceLabel({ ...story, sources: [{ kind: 'heritage', ref: 'x', note: '' }] })).toBeNull();
  });
});

describe('CLEAR 화면 값', () => {
  it('걸린 시간은 「N분」, 60분부터 「N시간 M분」', () => {
    expect(elapsedText(0, 59 * 60_000 + 59_000)).toBe('59분');
    expect(elapsedText(0, 65 * 60_000)).toBe('1시간 5분');
  });

  it('완료 미션은 「완료 / 전체」, 건너뛴 수를 따로 센다', () => {
    const play = seongeup();
    const s = { ...initRunner(play, null, 0), progress: { ...createPlayProgress(play, 0), completedMissionIds: ['m01', 'm02'], skippedMissionIds: ['m02'] } };
    expect(clearStats(play, s, 12 * 60_000)).toEqual({ completed: '2 / 3', skipped: 1, elapsed: '12분' });
  });

  it('신고는 지금 미션을 가리킨다', () => {
    const play = seongeup();
    expect(reportTarget(play, initRunner(play, null))).toEqual({ id: 'm01', title: '미션 m01' });
  });
});
