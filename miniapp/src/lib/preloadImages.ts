/**
 * 이미지를 미리 받아 둔다 — CourseListView.swift 의 CourseCoverStore.warm(_:until:) 자리.
 *
 * 코스 찾기 규칙(2026-09-10): 로딩 화면은 최소 3초, 카드 사진은 5초까지만 기다린다.
 *   await preloadImages(urls, startedAt + 5000);
 * 받은 것은 브라우저 캐시에 남아 카드가 사진까지 완성된 채로 나타난다.
 */
const loaded = new Set<string>();

function loadOne(url: string): Promise<void> {
  if (loaded.has(url)) return Promise.resolve();
  return new Promise<void>((resolve) => {
    const img = new Image();
    // 화면의 <img referrerPolicy="no-referrer"> 와 같은 요청이어야 캐시를 그대로 쓴다 (iOS 도 Referer 를 안 보낸다).
    img.referrerPolicy = 'no-referrer';
    img.onload = () => {
      loaded.add(url);
      resolve();
    };
    img.onerror = () => resolve();
    img.src = url;
  });
}

/** 모두 받거나 `deadline`(epoch ms)이 지나면 풀린다. 실패해도 reject 하지 않는다. */
export async function preloadImages(urls: string[], deadline: number): Promise<void> {
  const left = deadline - Date.now();
  if (urls.length === 0 || left <= 0) return;
  await Promise.race([
    Promise.all(urls.map(loadOne)),
    new Promise<void>((r) => setTimeout(r, left)),
  ]);
}

/** 이미 받아 둔 이미지인가 (받아 둔 것은 바로 그리고, 아니면 로딩 자리를 깐다). */
export function isImagePreloaded(url: string): boolean {
  return loaded.has(url);
}

/** `ms` 만큼 기다린다 (최소 로딩 시간 채우기). */
export function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, Math.max(0, ms)));
}
