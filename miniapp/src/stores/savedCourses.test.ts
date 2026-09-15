/**
 * 담아 둔 코스.
 *
 * 왜 이 테스트가 있나 — 서버는 코스 상세를 줄 때마다 `id` 를 새 UUID 로 만든다. `id` 로
 * 「이미 담았나」를 물으면 같은 코스가 목록에 계속 쌓인다(2026-09-09 실제로 겪음).
 * 그리고 실패했는데 「저장됐어요」라고 말하면 안 된다.
 */
import { describe, expect, it } from 'vitest';
import type { Course } from '../api/types';
import { createMemoryBackend } from './kv';
import { courseIdentityKey, createSavedCourseStore, savedCourseKey, savedCourseToCourse } from './savedCourses';

const course = (over: Partial<Course> = {}): Course => ({
  id: 'uuid-1',
  title: '동부 2일 · 성산일출봉 외 6곳',
  durationDays: 2,
  places: [{ name: '성산일출봉', lat: 33.46, lng: 126.94, day: 1, startTime: null }],
  estimatedMinutes: 420,
  sourceCourseId: 'C-100',
  ...over,
});

describe('담아 둔 코스', () => {
  it('같은 코스를 다른 UUID 로 다시 열어 담아도 한 번만 담긴다 (신원 = sourceCourseId)', async () => {
    const store = createSavedCourseStore(createMemoryBackend());
    await store.hydrate();
    expect(await store.save(course({ id: 'uuid-1' }))).toBe('saved');
    expect(await store.save(course({ id: 'uuid-2' }))).toBe('already');
    expect(store.list()).toHaveLength(1);
    expect(store.isSaved(course({ id: 'uuid-3' }))).toBe(true);
  });

  it('sourceCourseId 가 없는 옛 코스는 id 로 비교한다', () => {
    expect(courseIdentityKey(course({ sourceCourseId: '' }))).toBe('uuid-1');
    expect(savedCourseKey({ id: 'x', sourceCourseId: null })).toBe('x');
  });

  it('앱을 다시 켜도 남아 있고, 최근에 담은 것부터 보인다', async () => {
    const backend = createMemoryBackend();
    let t = 1;
    const store = createSavedCourseStore(backend, { now: () => t });
    await store.hydrate();
    await store.save(course({ sourceCourseId: 'A' }));
    t = 2;
    await store.save(course({ sourceCourseId: 'B' }));

    const again = createSavedCourseStore(backend);
    await again.hydrate();
    expect(again.list().map(savedCourseKey)).toEqual(['B', 'A']);
  });

  it('쓰기에 실패하면 담기지 않은 상태로 되돌리고 실패를 알린다', async () => {
    const backend = createMemoryBackend();
    const store = createSavedCourseStore(backend);
    await store.hydrate();
    backend.failNextWrite();
    await expect(store.save(course())).rejects.toThrow();
    await store.whenIdle();
    expect(store.list()).toHaveLength(0);
    expect(store.isSaved(course())).toBe(false);
  });

  it('이름 변경·삭제가 저장된다', async () => {
    const backend = createMemoryBackend();
    const store = createSavedCourseStore(backend);
    await store.hydrate();
    await store.save(course());
    await store.rename('C-100', '  우리 가족 동쪽 여행  ');
    expect(store.get('C-100')?.title).toBe('우리 가족 동쪽 여행');
    await store.rename('C-100', '   '); // 빈 이름은 무시
    expect(store.get('C-100')?.title).toBe('우리 가족 동쪽 여행');

    const again = createSavedCourseStore(backend);
    await again.hydrate();
    expect(again.get('C-100')?.title).toBe('우리 가족 동쪽 여행');
    await again.remove('C-100');
    expect(again.list()).toHaveLength(0);
  });

  it('담아 둔 코스를 코스 상세가 받는 Course 모양으로 되돌린다', async () => {
    const store = createSavedCourseStore(createMemoryBackend());
    await store.hydrate();
    await store.save(course());
    const c = savedCourseToCourse(store.get('C-100')!);
    expect(c).toMatchObject({ id: 'uuid-1', sourceCourseId: 'C-100', durationDays: 2, estimatedMinutes: 420 });
    expect(c.places).toHaveLength(1);
  });
});
