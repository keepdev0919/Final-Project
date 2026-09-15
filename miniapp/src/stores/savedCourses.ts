/**
 * 담아 둔 코스 — Models/SavedCourse.swift(SwiftData) + CoursePreviewViewModel 의 담기 규칙 이식.
 *
 * ## 신원은 `sourceCourseId` 다
 * 서버 `/course/detail` 은 부를 때마다 `id` 를 새 UUID 로 만든다. 그래서 「이미 담았나」를
 * `id` 로 물으면 **영원히 아니오**다 — 같은 코스가 목록에 계속 쌓였다(2026-09-09).
 * 진짜 코스 id 는 `sourceCourseId` 로 오고, 없을 때만 `id` 로 비교한다 → `identityKey`.
 *
 * ## 실패했는데 「저장됐어요」라고 말하지 않는다
 * `save()` 는 저장소 쓰기가 끝나야 풀리는 Promise 다. 실패하면 메모리에서도 도로 빼고 reject 한다.
 *
 * 로그인 없이 기기 안에만 남는다. 저장 키 `saved_courses_v1`.
 */
import type { Course, CoursePlace } from '../api/types';
import { createJsonStore, type JsonStore } from './jsonStore';
import type { KeyValueBackend } from './kv';

export const SAVED_COURSES_KEY = 'saved_courses_v1';

export interface SavedCourse {
  /** 담을 때 받은 상세의 id (UUID). 신원으로 쓰지 않는다. */
  id: string;
  /** 사용자가 바꿀 수 있다 (「이름 변경」). */
  title: string;
  durationDays: number;
  estimatedMinutes: number;
  /** epoch ms */
  savedAt: number;
  places: CoursePlace[];
  /** 진짜 코스 id. 없으면 null. */
  sourceCourseId: string | null;
}

/** 담아 둔 코스의 신원 — 라우트 `/profile/course/:savedId` 의 savedId 이기도 하다. */
export function savedCourseKey(sc: Pick<SavedCourse, 'id' | 'sourceCourseId'>): string {
  return sc.sourceCourseId ? sc.sourceCourseId : sc.id;
}

/** 서버 코스의 신원. `savedCourseKey` 와 같은 규칙. */
export function courseIdentityKey(course: Pick<Course, 'id' | 'sourceCourseId'>): string {
  return course.sourceCourseId ? course.sourceCourseId : course.id;
}

/** 담아 둔 코스를 코스 상세 화면이 받는 `Course` 모양으로. */
export function savedCourseToCourse(sc: SavedCourse): Course {
  return {
    id: sc.id,
    title: sc.title,
    durationDays: sc.durationDays,
    places: sc.places,
    estimatedMinutes: sc.estimatedMinutes,
    sourceCourseId: sc.sourceCourseId ?? '',
  };
}

function isSavedCourse(v: unknown): v is SavedCourse {
  if (typeof v !== 'object' || v === null) return false;
  const c = v as Record<string, unknown>;
  return (
    typeof c.id === 'string' &&
    typeof c.title === 'string' &&
    typeof c.durationDays === 'number' &&
    typeof c.estimatedMinutes === 'number' &&
    typeof c.savedAt === 'number' &&
    Array.isArray(c.places) &&
    (c.sourceCourseId === null || typeof c.sourceCourseId === 'string')
  );
}

function parseList(raw: unknown): SavedCourse[] | null {
  if (!Array.isArray(raw)) return null;
  // 코스 하나가 망가졌다고 나머지를 버리지 않는다 — 망가진 것만 뺀다.
  return raw.filter(isSavedCourse);
}

export interface SavedCourseStore {
  readonly raw: JsonStore<SavedCourse[]>;
  hydrate(): Promise<void>;
  /** 최근에 담은 것부터. */
  list(): SavedCourse[];
  get(key: string): SavedCourse | null;
  isSaved(course: Pick<Course, 'id' | 'sourceCourseId'>): boolean;
  /**
   * 담는다. 이미 담았으면 'already'(저장소를 다시 보고 판정한다 — 화면 상태만 믿지 않는다).
   * 쓰기에 실패하면 되돌리고 reject — 화면은 「담지 못했어요…」를 띄운다.
   */
  save(course: Course): Promise<'saved' | 'already'>;
  rename(key: string, title: string): Promise<void>;
  remove(key: string): Promise<void>;
  subscribe(listener: () => void): () => void;
  whenIdle(): Promise<void>;
}

export function createSavedCourseStore(
  backend: KeyValueBackend,
  opts: { now?: () => number } = {},
): SavedCourseStore {
  const now = opts.now ?? Date.now;
  const raw = createJsonStore<SavedCourse[]>({ backend, key: SAVED_COURSES_KEY, empty: () => [], parse: parseList });

  const find = (key: string) => raw.get().find((c) => savedCourseKey(c) === key) ?? null;

  async function commit(next: SavedCourse[], rollback: SavedCourse[]) {
    try {
      await raw.set(next);
    } catch (e) {
      raw.set(rollback).catch(() => undefined);
      throw e;
    }
  }

  return {
    raw,
    hydrate: () => raw.hydrate(),
    list: () => [...raw.get()].sort((a, b) => b.savedAt - a.savedAt),
    get: find,
    isSaved: (course) => find(courseIdentityKey(course)) !== null,
    async save(course) {
      if (find(courseIdentityKey(course))) return 'already';
      const before = raw.get();
      const saved: SavedCourse = {
        id: course.id,
        title: course.title,
        durationDays: course.durationDays,
        estimatedMinutes: course.estimatedMinutes,
        savedAt: now(),
        places: course.places,
        sourceCourseId: course.sourceCourseId ? course.sourceCourseId : null,
      };
      await commit([...before, saved], before);
      return 'saved';
    },
    async rename(key, title) {
      const trimmed = title.trim();
      const before = raw.get();
      if (!trimmed || !find(key)) return;
      await commit(
        before.map((c) => (savedCourseKey(c) === key ? { ...c, title: trimmed } : c)),
        before,
      );
    },
    async remove(key) {
      const before = raw.get();
      if (!find(key)) return;
      await commit(
        before.filter((c) => savedCourseKey(c) !== key),
        before,
      );
    },
    subscribe: (l) => raw.subscribe(l),
    whenIdle: () => raw.whenIdle(),
  };
}
