/** 테스트용 PLAY — 실제 원고 모양을 줄여 만든 것 (Point 3개 · 미션 4개 · FINAL). */
import type { Mission, MissionStep, Play, PlayPoint } from '../api/types';

const step = (over: Partial<MissionStep> = {}): MissionStep => ({
  inputType: 'CONFIRM',
  prompt: '찾았어요?',
  options: [],
  matchTargets: [],
  answer: null,
  successFeedback: '',
  failureFeedback: '',
  ...over,
});

const mission = (id: string, over: Partial<Mission> = {}): Mission => ({
  id,
  title: `미션 ${id}`,
  patterns: ['FIND'],
  prompt: '',
  steps: [step()],
  hints: [],
  discovery: null,
  progressReward: null,
  verification: 'strong',
  isShowcase: false,
  ...over,
});

const point = (id: string, missions: Mission[], lat: number | null = 33.43, lng: number | null = 126.8): PlayPoint => ({
  id,
  title: `지점 ${id}`,
  objective: '',
  lat,
  lng,
  navigationText: '',
  intro: '',
  missions,
});

export function makePlay(id = 'seongeup'): Play {
  return {
    id,
    placeId: 'P-1',
    placeKey: 'seongeup-folk-village',
    placeName: '성읍민속마을',
    title: '성읍 생활기록 복원작전',
    objective: '',
    cardSummary: '',
    estimatedMinutesMin: 60,
    estimatedMinutesMax: 75,
    distanceMeters: 1000,
    difficulty: '보통',
    difficultyStars: 3,
    progressLabel: '생활기록',
    progressRecords: [],
    routeRevealMode: 'FULL',
    startName: '주차장',
    startLat: null,
    startLng: null,
    finishName: '마을 입구',
    points: [
      point('P1', [mission('M01'), mission('M02', { progressReward: 'R1' })]),
      point('P2', [mission('M03')]),
      point('P3', [mission('M04')], null, null),
    ],
    stories: [],
    final: null,
    clear: null,
  };
}

export { step, mission };
