/**
 * 코스 탭 — 원본: Views/CourseHubView.swift → TasteDiscoveryView.swift → CourseListView.swift
 *   (+ ViewModels/CourseRecommendViewModel.swift, Views/SharedComponents.swift 의 LoadingOverlay)
 *
 * 라우트
 *   `/course`                       CourseDiscoverScreen  (탭 뿌리, 탭바 보임) — TasteDiscoveryView
 *   `/course/list?region=&days=`    CourseListScreen      (탭바 보임)          — CourseListView
 * 코스를 고르면 CourseAPI.detail() 로 받은 뒤 nav.toCoursePreview(course).
 *
 * 코스 탭의 색 쓰임 (2026-09-09 결정)
 *     고르는 것 (기간)        금색   지도의 초록·파랑과 겹치지 않아 확실히 떠오른다
 *     결과 (코스 카드)        파랑   내가 고른 것이 아니라 받아 본 것
 *     실행 (코스 찾기)        초록   앱의 브랜드색. 진짜 행동에만 남긴다
 *     권역                   권역마다 제 색 (동부 주황 · 서부 보라 · 북부 파랑 · 남부 청록 · 전체 잉크)
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { CourseAPI, type CourseListItem } from '../../api';
import { useAppNavigation, useCourseListParams } from '../../app/routes';
import { fetchResource, invalidateResource, useResource } from '../../lib/resource';
import { preloadImages, sleep } from '../../lib/preloadImages';
import {
  Icon,
  images,
  LoadingOverlay,
  PixelBob,
  PixelColor,
  PixelDialog,
  PixelFont,
  PixelIntroCard,
  PixelSectionHeader,
  PixelSpacing,
  PixelStyledButton,
  PullToRefreshIndicator,
  usePullToRefresh,
} from '../../ui';
import { CourseCard, JejuOverworldPicker } from './components';
import './course-discover.css';

// ═══════════════════════════════ 문구 · 규칙 ═══════════════════════════════

/** Swift `LoadingStep` 값 그대로 */
const LOADING_SEARCHING = '최적의 코스 찾는 중 ..';
const LOADING_GENERATING = '코스 준비 중...';

/**
 * 라벨은 「N박M일」 — 데이터는 여행 일수라 1 = 당일치기. 「3박4일」은 4를 보낸다.
 * 마지막 「3박4일 이상」만 4일 이상을 다 담는다 (백엔드 OPEN_ENDED_FROM).
 */
const DURATION_OPTIONS: readonly { days: number; label: string }[] = [
  { days: 1, label: '당일치기' },
  { days: 2, label: '1박2일' },
  { days: 3, label: '2박3일' },
  { days: 4, label: '3박4일 이상' },
];

/**
 * 코스 찾기의 시간 규칙
 *     0 ───────── 1.5초 ───── 2초
 *     │  로딩 화면은 무조건 여기까지
 *     │             │  사진이 아직이면 여기까지만 더 기다린다
 *     └ 목록 받기 + 사진 미리 받기
 *
 * iOS 는 3초/5초다(2026-09-10 조익준님 결정 — 너무 빨리 넘어가 찾아본 느낌이 없고,
 * 넘어간 뒤 사진이 늦게 채워져 화면이 한 번 더 움직였다). 앱인토스는 비게임 출시
 * 가이드의 「인터랙션 반응 2초 이상 지연 금지」 때문에 1.5초/2초로 줄였다
 * (2026-09-15 조익준님 결정). 대가: 느린 망에서는 사진 없이 넘어간 뒤 채워질 수 있다.
 */
const MINIMUM_LOADING_MS = 1500;
const COVER_DEADLINE_MS = 2000;

const courseListKey = (region: string, days: number) => `courseList:${region}:${days}`;

/**
 * 목록 받기 + 카드 사진 미리 받기 + 최소 로딩 시간. 실패는 **기다리지 않고** 바로 던진다 —
 * 못 가져왔다는 말을 늦게 하는 것은 그냥 더 느린 실패다.
 */
async function searchCourses(region: string, days: number): Promise<CourseListItem[]> {
  const startedAt = Date.now();
  const items = await CourseAPI.list(region, days);
  const thumbs = items.map((i) => i.thumbnail).filter((t): t is string => !!t);
  await preloadImages(thumbs, startedAt + COVER_DEADLINE_MS);
  await sleep(MINIMUM_LOADING_MS - (Date.now() - startedAt));
  return items;
}

function errorText(e: unknown): string {
  return e instanceof Error && e.message ? e.message : '다시 시도해주세요.';
}

/**
 * 고른 권역·기간. iOS 는 코스 탭 화면을 살려 둬서 탭을 오가도 고른 것이 남는다.
 * 웹은 화면이 다시 마운트되므로 모듈에 들고 있는다 (앱을 다시 켜면 비워진다 — iOS 와 같다).
 */
const selection: { region: string; days: number | null } = { region: '', days: null };

/**
 * 카드를 눌러 코스 상세를 받고 넘어간다 (vm.fetchDetail). 받는 동안 「코스 준비 중...」 오버레이.
 * 실패하면 「코스를 가져오지 못했어요」.
 */
function useOpenCourse() {
  const nav = useAppNavigation();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const mounted = useRef(false);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  const open = useCallback(
    async (courseId: string) => {
      setError(null);
      setLoading(true);
      try {
        const course = await fetchResource(`course:${courseId}`, () => CourseAPI.detail(courseId));
        if (!mounted.current) return; // 받는 사이 화면을 떠났다 — 끌고 가지 않는다
        setLoading(false);
        nav.toCoursePreview(course);
      } catch (e) {
        if (!mounted.current) return;
        setLoading(false);
        setError(errorText(e));
      }
    },
    [nav],
  );

  return { open, loading, error, clearError: () => setError(null) };
}

// ═══════════════════════════════ 코스 찾기 첫 화면 (TasteDiscoveryView) ═══════════════════════════════

/**
 * 코스 탭 — 여행 전에 「어디 갈까」를 푸는 화면 하나.
 * 상단바를 두지 않는다 — 무슨 화면인지는 아래 제목(인트로 카드)이 말한다.
 */
export function CourseDiscoverScreen() {
  const nav = useAppNavigation();
  const rootRef = useRef<HTMLDivElement>(null);
  const [selectedRegion, setSelectedRegion] = useState(selection.region);
  const [selectedDays, setSelectedDays] = useState<number | null>(selection.days);
  const detail = useOpenCourse();

  // 「이런 코스는 어때요?」 — 권역·기간과 무관하게 서버가 무작위로 주는 목록.
  // 실패해도 경고창을 띄우지 않는다 — 곁다리 목록이 길을 막으면 안 된다. 받아 둔 것이 있으면 그대로 둔다.
  const featured = useResource('featured', () => CourseAPI.featured(5));
  const featuredList = featured.data ?? [];
  const isLoadingFeatured = featured.loading || (featured.data === undefined && !featured.error);
  const reloadFeatured = featured.reload;

  // `.task { if vm.featured.isEmpty { await vm.loadFeatured() } }` — 돌아왔는데 비어 있으면 다시 부른다.
  useEffect(() => {
    if (featured.data !== undefined && featured.data.length === 0 && !featured.loading) void reloadFeatured();
    // 나타날 때 한 번만.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 당겨서 새로고침 = 둘러보기 목록 갈아 끼우기
  const ptr = usePullToRefresh(rootRef, reloadFeatured);

  const selectRegion = (region: string) => {
    selection.region = region;
    setSelectedRegion(region);
  };
  const selectDays = (days: number) => {
    selection.days = days;
    setSelectedDays(days);
  };

  // 권역·기간이 **둘 다** 채워져야 켜진다. 고르는 일과 떠나는 일을 갈라놓는다.
  const ready = selectedRegion.length > 0 && selectedDays !== null;
  // 꺼져 있을 때는 **무엇이 비었는지** 말한다.
  const buttonTitle =
    selectedRegion.length === 0 && selectedDays === null
      ? '권역과 기간을 골라주세요'
      : selectedRegion.length === 0
        ? '권역을 골라주세요'
        : selectedDays === null
          ? '기간을 골라주세요'
          : '코스 찾기';

  const startSearch = () => {
    if (!ready || selectedDays === null) return;
    // iOS 는 「코스 찾기」를 누를 때마다 새로 찾는다 — 전에 찾은 같은 조건의 결과를 비운다.
    invalidateResource(courseListKey(selectedRegion, selectedDays));
    nav.toCourseList(selectedRegion, selectedDays);
  };

  return (
    <div className="px-screen cd-screen" ref={rootRef}>
      <PullToRefreshIndicator {...ptr} />

      <div className="cd-discover">
        {/* ── 머리말 ── */}
        <PixelIntroCard
          icon="walk"
          iconColor={PixelColor.accent}
          title={
            <>
              어느 쪽으로 <span style={{ color: PixelColor.accent }}>떠날까요</span>
            </>
          }
          message={
            <>
              제주 여행자들이 <b style={{ fontWeight: 700, color: PixelColor.accent }}>직접 짠</b>
              <br />
              코스{'\u00A0'}
              <b style={{ fontWeight: 700, color: PixelColor.accent }}>6천여{'\u00A0'}건</b>에서 길을 찾아드려요
            </>
          }
        />

        {/* ── 권역 · 기간 선택 ── */}
        <section className="cd-section">
          <PixelSectionHeader
            title="권역 · 기간 선택"
            icon="compass"
            iconColor={PixelColor.accent}
            underline={PixelSpacing.borderHeavy}
          />

          <JejuOverworldPicker selected={selectedRegion} onSelect={selectRegion} />

          {/* 기간 칩 2×2 */}
          <div className="cd-durations">
            {DURATION_OPTIONS.map((option) => {
              const on = selectedDays === option.days;
              return (
                <button
                  key={option.days}
                  type="button"
                  className={`px-reset-button cd-duration ${on ? 'px-border-heavy px-shadow-card' : 'px-border px-shadow-small'}`}
                  style={{
                    background: on ? PixelColor.accent : PixelColor.surface,
                    color: on ? PixelColor.onAccent : PixelColor.ink,
                  }}
                  aria-pressed={on}
                  onClick={() => selectDays(option.days)}
                >
                  {option.label}
                </button>
              );
            })}
          </div>

          {/* 코스 찾기 — 꺼져 있을 때는 흰 면 + 회색 테두리, 그림자 없음. 흐리게 덮지 않는다. */}
          <button
            type="button"
            className={`px-reset-button cd-search px-border ${ready ? 'px-shadow-card' : ''}`}
            style={{
              background: ready ? PixelColor.primary : PixelColor.surface,
              color: ready ? PixelColor.onPrimary : PixelColor.inkWeak,
              ['--px-border-color' as string]: ready ? PixelColor.ink : PixelColor.outlineVariant,
            }}
            aria-disabled={!ready}
            onClick={startSearch}
          >
            {buttonTitle}
          </button>
        </section>

        {/* ── 이런 코스는 어때요? ── */}
        <section className="cd-section">
          <PixelSectionHeader
            title="이런 코스는 어때요?"
            icon="star"
            iconColor={PixelColor.secondary}
            underline={PixelSpacing.borderHeavy}
            trailing={
              <button
                type="button"
                className="px-reset-button cd-refresh"
                disabled={isLoadingFeatured}
                onClick={() => void reloadFeatured()}
              >
                <span className="cd-refresh__box px-border px-shadow-small">
                  <Icon name="refresh" size={14} />
                  다른 코스
                </span>
              </button>
            }
          />

          {featuredList.length === 0 ? (
            <p className="cd-featured-empty" style={PixelFont.body}>
              {isLoadingFeatured ? '코스를 가져오는 중이에요' : '코스를 가져오지 못했어요. 당겨서 새로고침해 주세요.'}
            </p>
          ) : (
            <div className="cd-cards" style={{ opacity: isLoadingFeatured ? 0.5 : 1 }}>
              {featuredList.map((course) => (
                <CourseCard key={course.id} course={course} onTap={() => void detail.open(course.id)} />
              ))}
            </div>
          )}
        </section>
      </div>

      {detail.loading && <LoadingOverlay text={LOADING_GENERATING} />}
      <PixelDialog
        open={detail.error !== null}
        title="코스를 가져오지 못했어요"
        message={detail.error ?? '다시 시도해주세요.'}
        actions={[{ label: '확인', role: 'cancel' }]}
        onClose={detail.clearError}
      />
    </div>
  );
}

// ═══════════════════════════════ 추천 결과 목록 (CourseListView) ═══════════════════════════════

/**
 * 권역·기간으로 찾은 코스 목록. 뒤로가기 버튼을 그리지 않는다(토스 네비게이션 바가 준다) —
 * 화면 제목은 「추천 TOP N」이 한다.
 */
export function CourseListScreen() {
  const nav = useAppNavigation();
  const params = useCourseListParams();
  const key = params ? courseListKey(params.region, params.days) : null;
  const list = useResource(key, () => (params ? searchCourses(params.region, params.days) : Promise.resolve([])));
  const detail = useOpenCourse();

  // 목록 실패 경고창을 「확인」으로 닫으면 그 실패는 다시 띄우지 않는다 (vm.errorMessage = nil).
  const [dismissedError, setDismissedError] = useState<unknown>(null);
  const listError = list.error && list.error !== dismissedError ? list.error : null;
  // 처음 그리는 순간(요청이 붙기 전)도 로딩으로 본다 — 빈 목록이 한 번 번쩍이지 않게.
  const isLoadingList = key !== null && (list.loading || (list.data === undefined && !list.error));
  const errorMessage = detail.error ?? (listError ? errorText(listError) : null);
  const courses = list.data ?? [];

  let content;
  if (isLoadingList) {
    content = <LoadingView />;
  } else if (errorMessage !== null && !detail.loading) {
    content = (
      <div className="cd-state">
        <div className="cd-state__box">
          <Icon name="warn" size={48} color={PixelColor.locked} />
          <p style={{ ...PixelFont.body, color: PixelColor.inkWeak }}>{errorMessage}</p>
          <PixelStyledButton
            kind="primary"
            onClick={() => {
              detail.clearError();
              void list.reload();
            }}
          >
            다시 시도
          </PixelStyledButton>
        </div>
      </div>
    );
  } else if (courses.length === 0) {
    content = (
      <div className="cd-state">
        <div className="cd-state__box">
          <p style={{ ...PixelFont.body, color: PixelColor.inkWeak }}>추천 코스가 없어요.</p>
          <PixelStyledButton kind="primary" onClick={() => nav.back()}>
            처음으로
          </PixelStyledButton>
        </div>
      </div>
    );
  } else {
    content = (
      <>
        <div className="cd-list-header">
          {/* 숫자는 **실제로 온 개수**다. 모자란 날 「TOP 5」라고 적으면 화면이 거짓말을 한다. */}
          <h1 className="cd-list-header__title" style={PixelFont.sectionTitle}>
            추천 TOP {courses.length}
          </h1>
          <p className="cd-list-header__subtitle" style={PixelFont.body}>
            마음에 드는 코스를 골라보세요
          </p>
        </div>
        <div className="cd-list">
          {courses.map((course, index) => (
            <CourseCard key={course.id} course={course} rank={index + 1} onTap={() => void detail.open(course.id)} />
          ))}
        </div>
      </>
    );
  }

  return (
    <div className="px-screen">
      {content}

      {detail.loading && <LoadingOverlay text={LOADING_GENERATING} />}
      <PixelDialog
        open={errorMessage !== null && !isLoadingList}
        title="코스를 가져오지 못했어요"
        message={errorMessage ?? '다시 시도해주세요.'}
        actions={[{ label: '확인', role: 'cancel' }]}
        onClose={() => {
          if (detail.error !== null) detail.clearError();
          else setDismissedError(list.error);
        }}
      />
    </div>
  );
}

/**
 * 코스를 찾는 동안 뜨는 화면. **곱딱이가 떠 있고 아래에 한 줄.**
 * 그림은 곱딱이(64px)를 정확히 2배(128)로 — 정수 배수라 도트가 갈리지 않는다.
 * 로딩 시간을 가만히 있는 그림으로 채우면 멈춘 화면으로 읽혀 통통 떠다니게 한다.
 */
function LoadingView() {
  return (
    <div className="cd-state" role="status" aria-label={LOADING_SEARCHING}>
      <div className="cd-loading" aria-hidden="true">
        <PixelBob>
          <img src={images.gamgyul} alt="" className="cd-loading__image px-pixelated" draggable={false} />
        </PixelBob>
        <span style={{ ...PixelFont.label, color: PixelColor.inkWeak }}>{LOADING_SEARCHING}</span>
      </div>
    </div>
  );
}
