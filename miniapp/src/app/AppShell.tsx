/**
 * 앱 뼈대 — Views/ContentView.swift 이식.
 *
 *   ┌──────────────────────────┐
 *   │ (토스 네비게이션 바 — 플랫폼이 그린다) │
 *   ├──────────────────────────┤
 *   │ .px-app__main  ← 화면이 스크롤하는 곳 │
 *   │   <Outlet/>                        │
 *   ├──────────────────────────┤
 *   │ PixelTabBar (탭 화면에서만)          │
 *   └──────────────────────────┘
 *
 * 하는 일
 *   - 탭바: 라우트 handle 의 showTabBar 가 true 인 화면에서만 보인다 (PLAY 상세·장소 상세·코스 상세·러너는 숨김).
 *   - 탭 전환은 **기록을 바꿔치기(replace)** 한다 — 탭끼리는 뒤로가기로 오가지 않는다.
 *     탭마다 마지막으로 보던 경로를 기억해 돌아가면 그 자리로 간다 (iOS 가 탭 스택을 살려 두듯이).
 *   - 마지막 탭을 기억해 다음 실행 때 그 탭에서 시작한다 (@AppStorage("selected_tab")).
 *   - 토스 뒤로가기(backEvent): 화면 가로채기 → 탭 뿌리면 미니앱 닫기 → 아니면 앱 안 뒤로.
 *   - 스크롤: 새 화면은 맨 위, 뒤로 돌아오면 보던 자리.
 */
import { graniteEvent, Screen } from '@apps-in-toss/web-framework';
import { useEffect, useLayoutEffect, useRef } from 'react';
import { Outlet, useLocation, useMatches, useNavigate, useNavigationType } from 'react-router';
import { selectedTabStore } from '../stores';
import type { AppTab } from '../stores/preferences';
import { PixelTabBar, type PixelTabItem } from '../ui/PixelTabBar';
import { runBackHandlers } from './backHandler';
import { TAB_ROOTS, useGoBack, type RouteName } from './routes';

/** 라우트마다 붙이는 표시 (router.tsx). */
export interface RouteHandle {
  name: RouteName;
  /** 이 화면이 속한 탭 */
  tab?: AppTab;
  /** 탭 뿌리 화면 — 여기서 토스 뒤로가기를 누르면 미니앱이 닫힌다 */
  tabRoot?: boolean;
  /** 탭바를 보일지 */
  showTabBar?: boolean;
}

/** ContentView.swift 의 탭 네 개 — 시안 그대로: 퀘스트·코스(나침반)·지도(접힌 지도)·프로필 */
const TAB_ITEMS: PixelTabItem<AppTab>[] = [
  { tab: 'home', title: '퀘스트', icon: 'quest' },
  { tab: 'course', title: '코스', icon: 'compass' },
  { tab: 'map', title: '지도', icon: 'map' },
  { tab: 'profile', title: '프로필', icon: 'person' },
];

export function AppShell() {
  const matches = useMatches();
  const handle = (matches[matches.length - 1]?.handle ?? { name: 'home' }) as RouteHandle;
  const location = useLocation();
  const navType = useNavigationType();
  const navigate = useNavigate();
  const goBack = useGoBack();
  const mainRef = useRef<HTMLElement>(null);

  // ── 마지막 탭에서 시작 (첫 진입이 `/` 일 때만) ──
  const restored = useRef(false);
  useEffect(() => {
    if (restored.current) return;
    restored.current = true;
    const idx = (window.history.state as { idx?: number } | null)?.idx ?? 0;
    const last = selectedTabStore.get();
    if (location.pathname === '/' && idx === 0 && last !== 'home') navigate(TAB_ROOTS[last], { replace: true });
    // 첫 마운트 한 번만.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── 탭별 마지막 경로 · 마지막 탭 저장 ──
  const lastPath = useRef<Partial<Record<AppTab, string>>>({});
  useEffect(() => {
    if (!handle.tab || !handle.showTabBar) return;
    lastPath.current[handle.tab] = location.pathname + location.search;
    if (selectedTabStore.get() !== handle.tab) selectedTabStore.set(handle.tab).catch(() => undefined);
  }, [handle.tab, handle.showTabBar, location.pathname, location.search]);

  const onSelectTab = (tab: AppTab) => {
    if (tab === handle.tab) return; // 이미 보고 있는 탭 — iOS 도 아무 일 없다
    navigate(lastPath.current[tab] ?? TAB_ROOTS[tab], { replace: true });
  };

  // ── 스크롤: 새 화면은 맨 위, 뒤로 돌아오면 보던 자리 ──
  const positions = useRef(new Map<string, number>());
  useLayoutEffect(() => {
    const el = mainRef.current;
    if (!el) return;
    el.scrollTop = navType === 'POP' ? (positions.current.get(location.key) ?? 0) : 0;
  }, [location.key, navType]);

  // ── 토스 뒤로가기 ──
  const latest = useRef({ handle, goBack });
  useLayoutEffect(() => {
    latest.current = { handle, goBack };
  });
  useEffect(() => {
    let unsubscribe: () => void = () => undefined;
    try {
      unsubscribe = graniteEvent.addEventListener('backEvent', {
        onEvent: () => {
          if (runBackHandlers()) return;
          const { handle: h, goBack: back } = latest.current;
          if (h.tabRoot) {
            // 최초 화면(탭 뿌리)에서 뒤로가기 → 미니앱 종료 (비게임 출시 체크리스트)
            Screen.close().catch(() => undefined);
            return;
          }
          back();
        },
        onError: (e) => console.warn('[backEvent]', e),
      });
    } catch (e) {
      console.warn('[backEvent] 구독 실패 — 토스 밖에서 실행 중', e);
    }
    return () => unsubscribe();
  }, []);

  return (
    <div className="px-app">
      <main
        ref={mainRef}
        className="px-app__main"
        onScroll={(e) => positions.current.set(location.key, e.currentTarget.scrollTop)}
      >
        <Outlet />
      </main>
      {handle.showTabBar && <PixelTabBar items={TAB_ITEMS} selection={handle.tab ?? null} onSelect={onSelectTab} />}
    </div>
  );
}
