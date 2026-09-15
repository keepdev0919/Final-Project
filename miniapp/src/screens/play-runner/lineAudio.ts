/**
 * 곱딱이 대사 음성 재생 — Services/StoryAudioPlayer.swift (+ AudioPlayer.swift) 이식.
 *
 * **곱딱이가 말하는 모든 말을 읽는다** (2026-09-11). 단계가 바뀌어 대사가 나오면 자동으로
 * 재생되고, 상단 HUD 의 스피커로 끄고 켠다. 끈 상태는 기기에 남아 다음 PLAY 에도 이어진다
 * (`play.voiceMuted`, stores 의 voiceMutedStore).
 *
 * 서버 `/tts/line` 이 대사 열쇠(`point:…` `mission:…:0` `story:…`)로 **우리 원고에서** 문장을 찾아
 * Typecast 로 읽은 mp3 를 준다. 클라이언트는 문장을 보내지 않는다.
 *
 * ## 웹에서 다른 점
 * - **자동재생 제한**: `apps-in-toss.config.ts` 의 `webView.mediaPlaybackRequiresUserAction: false` 로
 *   Swift 처럼 탭 없이 읽는다. 그 설정이 안 먹는 환경(일반 브라우저 등)에 대비해 `<audio>` 하나를 계속
 *   다시 쓴다 — 한 번 탭으로 재생된 요소는 그 뒤 주소를 바꿔도 재생된다. 첫 줄이 막히면(`blocked`)
 *   상태를 `failed` 로 두고(자막은 그대로 나간다), 다음 탭이 **대사를 바꾸지 않았을 때만**
 *   `unlockWithGesture()` 가 그 줄을 다시 튼다(대사를 바꾼 탭은 새 줄을 틀면서 이미 풀었다).
 * - **백그라운드**: 앱이 내려가면(visibilitychange → hidden) 소리를 멈춘다. 돌아와도 자동으로
 *   다시 틀지 않는다 — 자막은 그대로 있고, 스피커를 껐다 켜면 지금 줄을 다시 읽는다.
 * - **미리 받기**: **앞으로 나올 두 줄만** fetch 로 받아 blob URL 로 들고 있다. 지나간 줄의 소리는
 *   풀어 준다(Swift 는 디스크 임시 파일이지만 웹은 WebView 메모리다 — 한 판 31줄 ≈ 9.5MB).
 *   음소거 중에는 받지 않는다. 받는 중인 줄을 재생하게 되면 그 결과를 기다려 쓴다(같은 mp3 를 두 번
 *   받지 않는다). 실패해도 조용히 넘어간다 — 재생 때 서버에서 바로 흘려 듣는 길이 그대로 있다.
 *
 * ## 소리가 안 나도 진행은 막지 않는다
 * 음성이 실패하면 자막은 그대로 있고 상태만 `failed` 가 된다.
 */
import { useSyncExternalStore } from 'react';
import { ttsLineUrl } from '../../api';
import { voiceMutedStore } from '../../stores';

export type LineAudioState = 'idle' | 'loading' | 'playing' | 'failed';

export interface LineAudioSnapshot {
  state: LineAudioState;
  /** 지금 재생 중인 대사 열쇠. */
  currentLine: string | null;
  /** 마지막 재생이 자동재생 제한으로 막혔다 (사용자 탭이 필요하다). */
  blocked: boolean;
}

let snap: LineAudioSnapshot = { state: 'idle', currentLine: null, blocked: false };
const listeners = new Set<() => void>();
const set = (patch: Partial<LineAudioSnapshot>) => {
  snap = { ...snap, ...patch };
  listeners.forEach((l) => l());
};

let el: HTMLAudioElement | null = null;
/** 한 번이라도 실제로 소리가 났는가 (= 이 요소는 이제 탭 없이도 재생된다). */
let unlocked = false;
/** 재생 요청마다 올린다. 늦게 도착한 옛 요청의 결과를 버린다. */
let generation = 0;

/** 미리 받은 음성: 열쇠 → blob URL. **앞으로 나올 줄만** 둔다. PLAY 가 바뀌면 비운다. */
const ready = new Map<string, string>();
/** 받는 중인 음성: 열쇠 → 받은 소리(실패하면 null). */
const inflight = new Map<string, Promise<Blob | null>>();
/** 지금 미리 받아 두려는 줄. 받기가 끝났을 때 여기 없으면(이미 지나갔으면) 버린다. */
let wanted = new Set<string>();
let prefetchPlayId: string | null = null;
/** 지금 `<audio>` 가 쓰는 blob URL. 멈출 때 푼다. */
let currentBlobUrl: string | null = null;

function element(): HTMLAudioElement | null {
  if (el) return el;
  if (typeof Audio === 'undefined') return null;
  el = new Audio();
  el.preload = 'auto';
  el.addEventListener('playing', () => {
    if (snap.currentLine === null) return;
    unlocked = true;
    set({ state: 'playing', blocked: false });
  });
  el.addEventListener('error', () => {
    if (snap.currentLine === null) return; // stop() 이 주소를 비울 때 나는 error 는 무시
    set({ state: 'failed' });
  });
  el.addEventListener('ended', () => stop());
  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') stop();
    });
  }
  return el;
}

function resetForPlay(playId: string) {
  if (prefetchPlayId === playId) return;
  ready.forEach((url) => URL.revokeObjectURL(url));
  ready.clear();
  inflight.clear();
  wanted = new Set();
  prefetchPlayId = playId;
}

/** 미리 받은 소리를 꺼내 쓴다 (꺼낸 뒤로는 재생이 끝날 때 stop() 이 푼다). */
function takeReady(line: string): string | null {
  const url = ready.get(line);
  if (url === undefined) return null;
  ready.delete(line);
  return url;
}

export function isMuted(): boolean {
  return voiceMutedStore.get();
}

/**
 * 대사 한 줄을 읽는다. 음소거 중이면 아무것도 하지 않는다.
 * 같은 줄을 이미 읽고 있으면 다시 시작하지 않는다 — 다시 그려질 때마다 처음부터 들리면 안 된다.
 */
export function play(playId: string, line: string): void {
  if (isMuted()) return;
  if (snap.currentLine === line && (snap.state === 'playing' || snap.state === 'loading')) return;
  const audio = element();
  // 막혔던 같은 줄을 다시 틀 때(unlockWithGesture)는 이미 받아 둔 소리를 그대로 다시 쓴다.
  let reuse: string | null = null;
  if (snap.currentLine === line) {
    reuse = currentBlobUrl;
    currentBlobUrl = null; // stop() 이 풀지 않게
  }
  stop();
  if (!audio) {
    if (reuse) URL.revokeObjectURL(reuse);
    set({ currentLine: line, state: 'failed' });
    return;
  }
  resetForPlay(playId);
  const g = ++generation;
  set({ currentLine: line, state: 'loading', blocked: false });
  const own = reuse ?? takeReady(line);
  if (own) {
    start(audio, own, true, g);
    return;
  }
  const pending = inflight.get(line);
  // 받는 중이면 그 결과를 기다린다. 단, 아직 한 번도 소리가 나지 않은 요소는 탭 안에서 곧바로
  // play() 해야 하므로(자동재생 제한) 기다리지 않고 서버에서 흘려 듣는다.
  if (pending && unlocked) {
    void pending.then((blob) => {
      if (g !== generation) return; // 기다리는 사이 다른 줄로 넘어갔다
      if (blob) start(audio, URL.createObjectURL(blob), true, g);
      else start(audio, ttsLineUrl(playId, line), false, g);
    });
    return;
  }
  start(audio, ttsLineUrl(playId, line), false, g);
}

function start(audio: HTMLAudioElement, src: string, isBlob: boolean, g: number) {
  if (isBlob) currentBlobUrl = src;
  audio.src = src;
  let p: Promise<void> | undefined;
  try {
    p = audio.play();
  } catch (e) {
    fail(g, e);
    return;
  }
  p?.catch((e: unknown) => fail(g, e));
}

function fail(g: number, e: unknown) {
  if (g !== generation || snap.currentLine === null) return;
  const blocked = e instanceof DOMException && e.name === 'NotAllowedError';
  // AbortError 는 다음 줄로 넘어가며 앞 줄을 끊은 것이다 — 그 경우 generation 이 이미 바뀌었다.
  set({ state: 'failed', blocked });
}

/**
 * 사용자가 화면을 탭했을 때 부른다. 자동재생 제한으로 막혀 있던 줄이 있으면 **탭 안에서** 다시 튼다.
 * 한 번 소리가 난 뒤로는 아무 일도 하지 않는다.
 *
 * 탭 처리가 **끝난 뒤**(버블 단계)에 불러야 한다. 그 탭이 대사를 바꿨으면 새 줄을 트는 play() 가
 * 이미 `blocked` 를 걷었으므로 여기서는 아무것도 하지 않는다 — 옛 줄을 틀었다가 곧바로 끊지 않는다.
 */
export function unlockWithGesture(playId: string, line: string | null): void {
  if (unlocked || !snap.blocked || !line || isMuted()) return;
  play(playId, line);
}

/**
 * 앞으로 나올 대사(`lines`)를 미리 받아 둔다. **그 밖의 줄은 풀어 준다** — 지나간 줄·건너뛴 줄의
 * 소리가 PLAY 가 끝날 때까지 메모리에 쌓이지 않게. 음소거 중에는 받지 않는다(소리를 끈 사람의
 * 데이터를 쓰지 않는다 — 다시 켜면 지금 줄은 서버에서 바로 흘려 듣는다).
 */
export function prefetchUpcoming(playId: string, lines: string[]): void {
  resetForPlay(playId);
  wanted = new Set(lines);
  for (const [line, url] of ready) {
    if (wanted.has(line)) continue;
    URL.revokeObjectURL(url);
    ready.delete(line);
  }
  if (isMuted()) return;
  for (const line of lines) {
    if (ready.has(line) || inflight.has(line)) continue;
    const p: Promise<Blob | null> = fetch(ttsLineUrl(playId, line))
      .then((res) => (res.ok ? res.blob() : null))
      .then((blob) => (blob && blob.size > 0 ? blob : null))
      .catch(() => null);
    inflight.set(line, p);
    void p.then((blob) => {
      if (inflight.get(line) === p) inflight.delete(line);
      if (!blob || prefetchPlayId !== playId || !wanted.has(line) || ready.has(line)) return;
      ready.set(line, URL.createObjectURL(blob));
    });
  }
}

export function stop(): void {
  generation += 1;
  if (el) {
    el.pause();
    if (el.getAttribute('src') !== null) {
      el.removeAttribute('src');
      el.load();
    }
  }
  if (currentBlobUrl) {
    URL.revokeObjectURL(currentBlobUrl);
    currentBlobUrl = null;
  }
  if (snap.state !== 'idle' || snap.currentLine !== null) set({ state: 'idle', currentLine: null });
}

/** 스피커 끄기·켜기. 기기에 남는다. 끄면 바로 멈춘다. */
export function setMuted(muted: boolean): void {
  voiceMutedStore.set(muted).catch(() => undefined);
  if (muted) stop();
}

function subscribe(l: () => void) {
  listeners.add(l);
  return () => {
    listeners.delete(l);
  };
}

/** 재생 상태 훅. */
export function useLineAudio(): LineAudioSnapshot {
  return useSyncExternalStore(subscribe, () => snap);
}

/** 음소거 상태 훅 (voiceMutedStore). */
export function useMuted(): boolean {
  return useSyncExternalStore(voiceMutedStore.subscribe, voiceMutedStore.get);
}
