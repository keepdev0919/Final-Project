/**
 * 라우트 계약 — 화면 사이의 **유일한 약속**이다.
 *
 * 화면 담당은 URL 문자열을 직접 쓰지 말고 여기 헬퍼만 쓴다:
 *   const nav = useAppNavigation();  nav.toPlayDetail(play.id)
 *   <Link to={paths.playDetail(id)}>  (링크가 필요할 때)
 * 받는 쪽은 `use…Params()` 로 읽는다.
 *
 * ## 무엇을 URL 에, 무엇을 state 에 싣나
 *   - 다시 조회할 API 가 있는 것은 **URL 만으로 열린다** (새로고침·딥링크 가능).
 *   - 방금 받은 큰 객체(코스 상세, PLAY 전체)는 **router state 로 함께 넘겨** 다시 부르지 않는다.
 *     state 가 없으면(새로고침·딥링크) 받는 화면이 URL 의 id 로 다시 조회한다.
 */
import { useCallback, useMemo } from 'react';
import { useLocation, useNavigate, useParams, useSearchParams } from 'react-router';
import type { Course, Play } from '../api/types';
import type { AppTab } from '../stores/preferences';

// ═══════════════════════════════ 경로 ═══════════════════════════════

export type RouteName =
  | 'home'
  | 'course'
  | 'courseList'
  | 'coursePreview'
  | 'savedCourse'
  | 'map'
  | 'profile'
  | 'playDetail'
  | 'playRunner'
  | 'placeDetail';

/** react-router 에 등록하는 패턴. */
export const ROUTE_PATTERNS: Record<RouteName, string> = {
  home: '/',
  course: '/course',
  courseList: '/course/list',
  coursePreview: '/course/preview/:courseId',
  savedCourse: '/profile/course/:savedId',
  map: '/map',
  profile: '/profile',
  playDetail: '/play/:playId',
  playRunner: '/play/:playId/run',
  placeDetail: '/place',
};

/** 장소 상세를 여는 데 필요한 것 — Swift `PlaceDetailView(place: CoursePlace)` 의 name·lat·lng. */
export interface PlaceRef {
  name: string;
  /** **관광지 좌표** (사용자 위치 금지) */
  lat: number;
  lng: number;
}

const enc = encodeURIComponent;

/** 경로 문자열 헬퍼. */
export const paths = {
  home: () => '/',
  course: () => '/course',
  /** 코스 찾기 결과. region = 동부|서부|남부|북부|전체, days = 1~4 */
  courseList: (region: string, days: number) => `/course/list?${new URLSearchParams({ region, days: String(days) })}`,
  /** courseId = 목록 항목 id (= Course.sourceCourseId). */
  coursePreview: (courseId: string) => `/course/preview/${enc(courseId)}`,
  /** savedId = savedCourseKey(saved) */
  savedCourse: (savedId: string) => `/profile/course/${enc(savedId)}`,
  map: () => '/map',
  profile: () => '/profile',
  playDetail: (playId: string) => `/play/${enc(playId)}`,
  playRunner: (playId: string) => `/play/${enc(playId)}/run`,
  placeDetail: (place: PlaceRef) =>
    `/place?${new URLSearchParams({ name: place.name, lat: String(place.lat), lng: String(place.lng) })}`,
};

/** 탭 뿌리 경로. */
export const TAB_ROOTS: Record<AppTab, string> = {
  home: '/',
  course: '/course',
  map: '/map',
  profile: '/profile',
};

// ═══════════════════════════════ state ═══════════════════════════════

/** coursePreview 로 갈 때 함께 넘기는 것. */
export interface CoursePreviewState {
  course: Course;
}

/** playRunner 로 갈 때 함께 넘기는 것. */
export interface PlayRunnerState {
  play: Play;
}

// ═══════════════════════════════ 이동 ═══════════════════════════════

/**
 * 화면 이동. 모두 **push**(뒤로가기로 돌아올 수 있음)다.
 * 탭 전환은 탭바가 한다 — 화면이 탭을 바꿔야 하면 `toTab` 을 쓴다.
 */
export function useAppNavigation() {
  const navigate = useNavigate();
  const goBack = useGoBack();
  return useMemo(
    () => ({
      /** PLAY 상세 (홈 카드·지도 활성 핀) */
      toPlayDetail: (playId: string) => navigate(paths.playDetail(playId)),
      /** PLAY 진행 — 이미 받은 Play 를 함께 넘긴다 */
      toPlayRunner: (play: Play) => navigate(paths.playRunner(play.id), { state: { play } satisfies PlayRunnerState }),
      /** 장소 상세 (지도 준비 중 핀·PLAY 상세 「○○ 정보 보러가기」·코스 장소) */
      toPlaceDetail: (place: PlaceRef) => navigate(paths.placeDetail(place)),
      /** 코스 찾기 결과 목록 */
      toCourseList: (region: string, days: number) => navigate(paths.courseList(region, days)),
      /** 코스 상세 — `CourseAPI.detail()` 로 받은 코스를 함께 넘긴다 */
      toCoursePreview: (course: Course) =>
        navigate(paths.coursePreview(course.sourceCourseId || course.id), { state: { course } satisfies CoursePreviewState }),
      /** 담아 둔 코스 (프로필) */
      toSavedCourse: (savedId: string) => navigate(paths.savedCourse(savedId)),
      /** 탭 뿌리로 (현재 기록을 바꿔치기 — 탭끼리는 뒤로가기로 오가지 않는다) */
      toTab: (tab: AppTab) => navigate(TAB_ROOTS[tab], { replace: true }),
      /** 뒤로. 돌아갈 기록이 없으면(딥링크로 들어온 경우) 부모 화면으로. */
      back: goBack,
    }),
    [navigate, goBack],
  );
}

/** 이 화면을 여는 기록이 없을 때 돌아갈 부모. */
export function parentPathOf(pathname: string): string {
  if (pathname.startsWith('/course/')) return '/course';
  if (pathname.startsWith('/profile/')) return '/profile';
  const run = /^\/play\/([^/]+)\/run$/.exec(pathname);
  if (run) return `/play/${run[1]}`;
  return '/';
}

/** 뒤로가기 함수. 앱 안에서 쌓인 기록이 있으면 history.back, 없으면 부모로 바꿔치기. */
export function useGoBack(): () => void {
  const navigate = useNavigate();
  const location = useLocation();
  return useCallback(() => {
    const idx = (window.history.state as { idx?: number } | null)?.idx ?? 0;
    if (idx > 0) navigate(-1);
    else navigate(parentPathOf(location.pathname), { replace: true });
  }, [navigate, location.pathname]);
}

// ═══════════════════════════════ 받는 쪽 ═══════════════════════════════

export function usePlayDetailParams(): { playId: string } {
  const { playId = '' } = useParams();
  return { playId };
}

/** play 는 state 로 넘어왔을 때만 있다. null 이면 `PlayAPI.detail(playId)` 로 받는다. */
export function usePlayRunnerParams(): { playId: string; play: Play | null } {
  const { playId = '' } = useParams();
  const state = useLocation().state as Partial<PlayRunnerState> | null;
  const play = state?.play && state.play.id === playId ? state.play : null;
  return { playId, play };
}

/** 쿼리가 모자라면 null (→ 화면은 「장소 정보를 불러오지 못했어요」). */
export function usePlaceDetailParams(): PlaceRef | null {
  const [sp] = useSearchParams();
  return useMemo(() => {
    const name = sp.get('name');
    const latRaw = sp.get('lat');
    const lngRaw = sp.get('lng');
    // Number(null)·Number('') 은 0 이 된다 — 빠진 좌표를 (0,0) 으로 서버에 보내지 않게 먼저 거른다.
    if (!name || !latRaw?.trim() || !lngRaw?.trim()) return null;
    const lat = Number(latRaw);
    const lng = Number(lngRaw);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    return { name, lat, lng };
  }, [sp]);
}

export function useCourseListParams(): { region: string; days: number } | null {
  const [sp] = useSearchParams();
  return useMemo(() => {
    const region = sp.get('region');
    const days = Number(sp.get('days'));
    if (!region || !Number.isInteger(days) || days < 1) return null;
    return { region, days };
  }, [sp]);
}

/** course 는 state 로 넘어왔을 때만 있다. null 이면 `CourseAPI.detail(courseId)` 로 받는다. */
export function useCoursePreviewParams(): { courseId: string; course: Course | null } {
  const { courseId = '' } = useParams();
  const state = useLocation().state as Partial<CoursePreviewState> | null;
  const c = state?.course;
  const course = c && (c.sourceCourseId || c.id) === courseId ? c : null;
  return { courseId, course };
}

/** savedId 로 `useSavedCourse(savedId)` 를 부른다. 지워졌으면 null 이 온다. */
export function useSavedCourseParams(): { savedId: string } {
  const { savedId = '' } = useParams();
  return { savedId };
}
