/**
 * 프로필 탭 — 원본: Views/ProfileTabView.swift + Views/MyCourseListView.swift (MyCourseListView · SavedCourseRow)
 * 라우트: `/profile` (탭 뿌리, 탭바 보임)
 *
 * 로그인 기능은 없다(2026-09-09 제거). 이 탭에 있는 것은 두 가지뿐이다.
 *   1. 「내 코스」 — 기기에 담아 둔 코스 목록. 누르면 코스 상세(담기 대신 이름 변경·빼기)로 간다.
 *   2. 「개인정보 처리방침」 — 앱 안에서 닿을 수 있어야 하는 법적 고지. 제목 없는 조용한 한 줄.
 *
 * iOS 는 담아 둔 코스를 시트(SavedCourseDetailView)로 띄웠지만, 웹은 라우트
 * `/profile/course/:savedId` 로 넘어간다 — 상세·이름 변경 시트·삭제 확인은 course-preview(mode="saved") 몫.
 */
import type { MouseEvent } from 'react';
import { PRIVACY_POLICY_URL } from '../../api';
import { useAppNavigation } from '../../app/routes';
import { openExternalURL } from '../../lib/external';
import { savedCourseKey, useSavedCourses, type SavedCourse } from '../../stores';
import { Icon, PixelColor, PixelSectionHeader, PixelTopBar } from '../../ui';
import './profile.css';

export function ProfileScreen() {
  // Swift: Link(destination: privacyPolicyURL) — 기기 브라우저에서 연다(미니앱 안에 띄우지 않는다).
  const openPrivacyPolicy = (e: MouseEvent<HTMLAnchorElement>) => {
    e.preventDefault();
    void openExternalURL(PRIVACY_POLICY_URL);
  };

  return (
    <div className="px-screen">
      <div className="profile-top">
        <PixelTopBar title="프로필" />
      </div>

      <div className="profile-body">
        <section className="profile-section" aria-label="내 코스">
          <PixelSectionHeader title="내 코스" icon="map" accent={PixelColor.secondary} />
          <MyCourseList />
        </section>

        {/*
          「정보」 섹션은 걷어냈다(2026-09-10). 「출처: ⓒ한국관광공사」는 관광정보가 실제로 쓰이는
          장소 상세 화면으로 옮겼다. 개인정보 처리방침 링크만 남긴다 — 앱 안에서 닿을 수 있어야 한다.
        */}
        <a
          className="profile-privacy px-t-label-small"
          href={PRIVACY_POLICY_URL}
          onClick={openPrivacyPolicy}
          rel="noopener noreferrer"
        >
          개인정보 처리방침
        </a>
      </div>
    </div>
  );
}

/** 담아 둔 코스 목록 (MyCourseListView). 최근에 담은 것부터. 기기 안에만 남는다 — 로그인 없이도. */
function MyCourseList() {
  const courses = useSavedCourses();
  const nav = useAppNavigation();

  if (courses.length === 0) {
    return (
      <div className="profile-empty">
        <Icon name="map" size={32} color={PixelColor.inkWeak} />
        <p className="profile-empty__title px-t-body" style={{ color: PixelColor.ink }}>
          담아 둔 코스가 없어요
        </p>
        <p className="profile-empty__message px-t-label-small" style={{ color: PixelColor.inkWeak }}>
          코스 탭에서 마음에 드는 코스를 담아보세요
        </p>
      </div>
    );
  }

  return (
    <ul className="profile-course-list">
      {courses.map((course) => {
        const key = savedCourseKey(course);
        return (
          <li key={key}>
            <button
              type="button"
              className="profile-course-card px-reset-button px-border px-shadow-card"
              onClick={() => nav.toSavedCourse(key)}
            >
              <SavedCourseRow course={course} />
            </button>
          </li>
        );
      })}
    </ul>
  );
}

/** 코스 한 줄 (SavedCourseRow): 이름 + 「N일」·「N개 장소」. */
function SavedCourseRow({ course }: { course: SavedCourse }) {
  return (
    <span className="profile-course-row">
      <span className="profile-course-row__title px-t-body">{course.title}</span>
      <span className="profile-course-row__meta px-t-label-small">
        <span className="profile-course-row__label">
          <Icon name="calendar" size={16} />
          <span>{course.durationDays}일</span>
        </span>
        <span className="profile-course-row__label">
          <Icon name="mapPin" size={16} />
          <span>{course.places.length}개 장소</span>
        </span>
      </span>
    </span>
  );
}
