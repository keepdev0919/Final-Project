/**
 * 모델 파생값·판정 — Swift 모델의 computed property·메서드 이식.
 *
 *   Play.swift          durationText · distanceText · startCoordinate · orderedMissions ·
 *                       missionCount · story(after:) · point(id:) · startLabel · resumeLabel
 *                       MissionStep.isCorrect · partialCorrectCount · failureText
 *   Course.swift        CourseListItem.regionOrAll · placeHeadline · CourseTitle.region/headline
 *   PlaceNearby.swift   NearbyFacility.distanceText
 *   PlaceDetail.swift   hasIntroduction
 *
 * 순수 함수만 둔다 — 화면 어디서나 import 해서 쓴다.
 */
import { findRegion, JEJU_REGIONS, WHOLE_ISLAND_ID, type LatLng } from '../lib/region';
import type {
  Course,
  CourseListItem,
  Mission,
  MissionAnswer,
  MissionStep,
  NearbyFacility,
  PlaceDetail,
  Play,
  PlayPoint,
  PlayStory,
  PlaySummary,
} from './types';

// ═══════════════════════════════ 표시 문구 ═══════════════════════════════

/** 「60~75분」. 최소·최대가 같으면 하나만. */
export function durationText(p: { estimatedMinutesMin: number; estimatedMinutesMax: number }): string {
  return p.estimatedMinutesMin === p.estimatedMinutesMax
    ? `${p.estimatedMinutesMin}분`
    : `${p.estimatedMinutesMin}~${p.estimatedMinutesMax}분`;
}

/** 「약 1km」 — 1km 미만은 m 로 쓴다. 「약 1.0km」는 「약 1km」로. */
export function distanceText(p: { distanceMeters: number }): string {
  const m = p.distanceMeters;
  return m < 1000 ? `${m}m` : `약 ${(m / 1000).toFixed(1)}km`.replace('.0km', 'km');
}

/** 주변 시설 거리 「95m」 / 「1.2km」 (「약」 없음, .0 을 떼지 않음 — Swift 그대로) */
export function facilityDistanceText(f: Pick<NearbyFacility, 'distanceM'>): string {
  return f.distanceM < 1000 ? `${f.distanceM}m` : `${(f.distanceM / 1000).toFixed(1)}km`;
}

/** 카드용 두 줄 요약. 비어 있으면 objective. */
export function playCardText(p: Pick<PlaySummary, 'cardSummary' | 'objective'>): string {
  return p.cardSummary ? p.cardSummary : p.objective;
}

/** 시작 버튼 — **모든 PLAY 가 같은 말을 쓴다.** */
export const PLAY_START_LABEL = '플레이하기';
/** 이어서 할 때. */
export const PLAY_RESUME_LABEL = '이어서 하기';
/** 이미 CLEAR 한 기록이 있을 때 (홈 카드 · PLAY 상세 버튼). */
export const PLAY_REPLAY_LABEL = '다시 하기';

// ═══════════════════════════════ PLAY 구조 ═══════════════════════════════

export function missionCount(play: Play): number {
  return play.points.reduce((n, p) => n + p.missions.length, 0);
}

export function pointCoordinate(p: PlayPoint): LatLng | null {
  return p.lat != null && p.lng != null ? { lat: p.lat, lng: p.lng } : null;
}

/** 시작점. 원고에 좌표가 없으면 첫 Point. **추측 좌표를 넣지 않는다.** */
export function startCoordinate(play: Play): LatLng | null {
  if (play.startLat != null && play.startLng != null) return { lat: play.startLat, lng: play.startLng };
  const first = play.points[0];
  return first ? pointCoordinate(first) : null;
}

/** 이 미션을 끝내면 열리는 이야기. */
export function storyAfter(play: Play, missionId: string): PlayStory | undefined {
  return play.stories.find((s) => s.unlockAfterMission === missionId);
}

export function pointById(play: Play, id: string): PlayPoint | undefined {
  return play.points.find((p) => p.id === id);
}

/** 모든 미션을 Point 순서대로 편 목록. 진행 계산에 쓴다. */
export function orderedMissions(play: Play): { point: PlayPoint; mission: Mission }[] {
  return play.points.flatMap((point) => point.missions.map((mission) => ({ point, mission })));
}

// ═══════════════════════════════ 정답 판정 ═══════════════════════════════

const GENERIC_FAILURE = '아직 아닌 것 같아요. 실제 대상을 다시 한번 살펴보세요.';

/** 오답 문구. 원고가 비워두면 공용 문구 — **「틀렸습니다」라고 하지 않는다.** */
export function failureText(step: MissionStep): string {
  return step.failureFeedback ? step.failureFeedback : GENERIC_FAILURE;
}

const isList = (a: MissionAnswer): a is string[] => Array.isArray(a);

/**
 * 사용자가 넣은 답이 맞는지 **단말에서** 판정한다 (MissionStep.isCorrect).
 *
 *   CONFIRM                 무엇이든 통과
 *   문자열 == 문자열          CHOICE · DIRECTION
 *   숫자 == 숫자              NUMBER
 *   SHORT_TEXT              공백·대소문자를 무시하고 허용 답안 중 하나와 같으면 통과
 *   MATCH_ORDER             순서 세우기(matchTargets 없음)는 순서까지 같아야,
 *                           짝 맞추기("a>x")는 집합이 같으면 통과
 */
export function isCorrect(step: MissionStep, submitted: MissionAnswer): boolean {
  const want = step.answer;
  if (step.inputType === 'CONFIRM') return true;
  if (typeof want === 'string' && typeof submitted === 'string') return want === submitted;
  if (typeof want === 'number' && typeof submitted === 'number') return want === submitted;
  if (step.inputType === 'SHORT_TEXT' && isList(want) && typeof submitted === 'string') {
    const norm = (s: string) => s.replaceAll(' ', '').toLowerCase();
    return want.map(norm).includes(norm(submitted));
  }
  if (step.inputType === 'MATCH_ORDER' && isList(want) && isList(submitted)) {
    if (step.matchTargets.length === 0) {
      return want.length === submitted.length && want.every((w, i) => w === submitted[i]);
    }
    const a = new Set(want);
    const b = new Set(submitted);
    return a.size === b.size && [...a].every((x) => b.has(x));
  }
  return false;
}

/**
 * 순서 세우기·짝짓기가 몇 개나 맞았는지. 다른 입력 타입은 null.
 * 오답이어도 「거의 다 왔다」를 알려줘 다시 시도할 힘을 준다.
 */
export function partialCorrectCount(step: MissionStep, submitted: MissionAnswer): number | null {
  if (step.inputType !== 'MATCH_ORDER' || !isList(step.answer) || !isList(submitted)) return null;
  const want = step.answer;
  if (step.matchTargets.length === 0) {
    const n = Math.min(want.length, submitted.length);
    let same = 0;
    for (let i = 0; i < n; i++) if (want[i] === submitted[i]) same++;
    return same;
  }
  const wantSet = new Set(want);
  return submitted.filter((x) => wantSet.has(x)).length;
}

/**
 * 같은 Mission 안에서 Step 을 구분하는 키 (React key 용). 서버가 Step id 를 주지 않는다.
 * Swift 는 `"\(inputType)-\(prompt.hashValue)"` — 웹은 순번을 섞어 같은 문장도 겹치지 않게 한다.
 */
export function stepKey(step: MissionStep, index: number): string {
  return `${step.inputType}-${index}-${step.prompt}`;
}

// ═══════════════════════════════ 코스 ═══════════════════════════════

/** 목록 항목의 권역. 서버가 안 주면 「전체」. */
export function courseListItemRegion(item: Pick<CourseListItem, 'region'>): string {
  return item.region ?? WHOLE_ISLAND_ID;
}

/** 제목 앞의 권역. 「동부 2일 · 성산일출봉 외 6곳」 → 「동부」. 아는 권역·「전체」로 시작하지 않으면 null. */
export function courseTitleRegion(title: string): string | null {
  const known = [...JEJU_REGIONS.map((r) => r.id as string), WHOLE_ISLAND_ID];
  return known.find((k) => title.startsWith(`${k} `)) ?? null;
}

/**
 * 제목에서 「서부 3일 · 」 접두사를 뗀 나머지 (화면에서만 뗀다 — 원본은 그대로 둔다).
 * 「동부 2일 · 성산일출봉 외 6곳」 → 「성산일출봉 외 6곳」
 */
export function courseTitleHeadline(title: string, region: string | null): string {
  let t = title;
  if (region && t.startsWith(`${region} `)) t = t.slice(region.length + 1);
  const dot = t.indexOf('일 · ');
  if (dot >= 0 && /^\d*$/.test(t.slice(0, dot))) t = t.slice(dot + '일 · '.length);
  return t.length === 0 ? title : t;
}

/** 목록 카드의 큰 글자 「성산일출봉 외 6곳」. */
export function courseListItemHeadline(item: Pick<CourseListItem, 'title' | 'region'>): string {
  return courseTitleHeadline(item.title, courseListItemRegion(item));
}

/** 상세(Course)에는 권역 필드가 없다 — 제목 앞머리에서 읽는다. 못 읽으면 「전체」. */
export function courseRegion(course: Pick<Course, 'title'>): string {
  return courseTitleRegion(course.title) ?? WHOLE_ISLAND_ID;
}

export function courseHeadline(course: Pick<Course, 'title'>): string {
  return courseTitleHeadline(course.title, courseRegion(course));
}

/** 알려진 권역인지 (색·필터를 줄 수 있는지). */
export function isKnownRegion(id: string): boolean {
  return findRegion(id) !== undefined;
}

// ═══════════════════════════════ 장소 ═══════════════════════════════

/** KTO 에 **소개할 거리가 있는가** — 소개글 탭을 보여줄지 정한다. */
export function hasIntroduction(d: Pick<PlaceDetail, 'overview' | 'images'>): boolean {
  return d.overview.length > 0 || d.images.length > 0;
}
