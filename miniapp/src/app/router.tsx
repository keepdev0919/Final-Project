/**
 * 라우터. 경로·탭 소속·탭바 표시는 여기서만 정한다 (계약: routes.ts).
 *
 * 경로 기반 라우터(createBrowserRouter)를 쓴다 — 앱인토스 딥링크 `intoss://{appName}/경로` 가
 * 웹 경로에 그대로 대응한다 (docs: 주요 기능 등록하기).
 */
import { createBrowserRouter, Navigate } from 'react-router';
import { CourseDiscoverScreen, CourseListScreen } from '../screens/course-discover';
import { CoursePreviewScreen } from '../screens/course-preview';
import { HomeScreen } from '../screens/home';
import { MapTabScreen } from '../screens/map-tab';
import { PlaceDetailScreen } from '../screens/place-detail';
import { PlayDetailScreen } from '../screens/play-detail';
import { PlayRunnerScreen } from '../screens/play-runner';
import { ProfileScreen } from '../screens/profile';
import { AppShell, type RouteHandle } from './AppShell';
import { RouteError } from './RouteError';
import { ROUTE_PATTERNS } from './routes';

const h = (handle: RouteHandle) => handle;

export const router = createBrowserRouter([
  {
    element: <AppShell />,
    errorElement: <RouteError />,
    children: [
      // ── 탭 뿌리 (탭바 보임) ──
      { path: ROUTE_PATTERNS.home, element: <HomeScreen />, handle: h({ name: 'home', tab: 'home', tabRoot: true, showTabBar: true }) },
      { path: ROUTE_PATTERNS.course, element: <CourseDiscoverScreen />, handle: h({ name: 'course', tab: 'course', tabRoot: true, showTabBar: true }) },
      { path: ROUTE_PATTERNS.map, element: <MapTabScreen />, handle: h({ name: 'map', tab: 'map', tabRoot: true, showTabBar: true }) },
      { path: ROUTE_PATTERNS.profile, element: <ProfileScreen />, handle: h({ name: 'profile', tab: 'profile', tabRoot: true, showTabBar: true }) },

      // ── 탭 안에서 밀려 올라온 화면 ──
      // CourseListView 는 iOS 에서도 탭바를 숨기지 않는다.
      { path: ROUTE_PATTERNS.courseList, element: <CourseListScreen />, handle: h({ name: 'courseList', tab: 'course', showTabBar: true }) },
      // 「지금 이것만 정하는」 화면은 탭바를 숨긴다 (PLAY 상세·장소 상세·코스 상세).
      { path: ROUTE_PATTERNS.coursePreview, element: <CoursePreviewScreen mode="discover" />, handle: h({ name: 'coursePreview', tab: 'course' }) },
      { path: ROUTE_PATTERNS.savedCourse, element: <CoursePreviewScreen mode="saved" />, handle: h({ name: 'savedCourse', tab: 'profile' }) },
      { path: ROUTE_PATTERNS.playDetail, element: <PlayDetailScreen />, handle: h({ name: 'playDetail' }) },
      // iOS fullScreenCover — 탭바 없이 화면 전체.
      { path: ROUTE_PATTERNS.playRunner, element: <PlayRunnerScreen />, handle: h({ name: 'playRunner' }) },
      { path: ROUTE_PATTERNS.placeDetail, element: <PlaceDetailScreen />, handle: h({ name: 'placeDetail' }) },

      { path: '*', element: <Navigate to="/" replace /> },
    ],
  },
]);
