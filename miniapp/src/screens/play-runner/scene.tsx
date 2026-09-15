/**
 * 현장 진행 화면의 게임 장면 부품 — Views/DesignSystem/PixelScene.swift 이식.
 *
 * 카드·버튼·칩(공용 ui)과 쓰이는 곳이 다르다: 화면을 꽉 채운 픽셀 배경, 그 위에 떠 있는 HUD,
 * 아래에서 올라오는 대화상자. (PixelPlaceholderScene 은 공용 ui 에 있다.)
 *
 * 옮기지 않은 것: `PixelSoundButton` — Swift 에서도 쓰는 곳이 없다(2026-09-11 소리 스위치가 HUD 로 올라감).
 */
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Icon, PixelBlink, PixelColor, PixelFont, coverFor, images, type IconName } from '../../ui';

const cx = (...names: (string | false | null | undefined)[]) => names.filter(Boolean).join(' ');

// ═══════════════════════════════ 장면 배경 ═══════════════════════════════

/**
 * 화면을 꽉 채우는 픽셀 배경 + 아래로 갈수록 어두워지는 겹.
 * 가진 그림이 가로형(성읍 커버 512×382)이라 세로 화면에서는 가운데만 보이고 도트가 굵어진다 —
 * 픽셀아트라 보간을 끈다(흐려지지 않게). 그림이 없는 장소는 가라앉은 면만 깐다.
 */
export function PixelSceneBackground({ placeKey }: { placeKey: string | null }) {
  const src = coverFor(placeKey);
  return (
    <div className="pr-bg" aria-hidden="true">
      {src && <img src={src} alt="" className="pr-bg__img px-pixelated" />}
      <div className="pr-bg__shade" />
    </div>
  );
}

// ═══════════════════════════════ HUD ═══════════════════════════════

/**
 * 배경 위 정사각 픽셀 버튼. 보이는 면은 36×36, 누르는 자리는 44×44 (앱인토스 터치 타깃).
 * 누르면 2px 그림자 속으로 가라앉는다 (PixelPressStyle(offset: 2)).
 */
export function PixelHudButton({ glyph, label, onPress }: { glyph: IconName; label: string; onPress: () => void }) {
  return (
    <button type="button" className="px-reset-button pr-hud-btn" aria-label={label} onClick={onPress}>
      <span className="pr-hud-btn__face px-border">
        <Icon name={glyph} size={20} color={PixelColor.ink} />
      </span>
    </button>
  );
}

/**
 * 배경 위 진행도 칩 — 「생활기록 ▓▓▒▒▒▒ 2/6」. 상단 가운데.
 * 이번 PLAY 에서 실제로 모으는 것을 센다 — XP 나 점수 같은 범용 숫자를 쓰지 않는다.
 */
export function PixelHudProgress({ label, total, done }: { label: string; total: number; done: number }) {
  return (
    <div className="pr-hud-progress px-border px-shadow-small" role="img" aria-label={`${label} ${total}개 중 ${done}개`}>
      <span style={{ ...PixelFont.labelSmall, color: PixelColor.ink }}>{label}</span>
      <span className="pr-hud-progress__cells">
        {Array.from({ length: Math.max(total, 1) }, (_, i) => (
          <span key={i} style={{ background: i < done ? PixelColor.primary : PixelColor.surfaceVariant }} />
        ))}
      </span>
      <span style={{ ...PixelFont.labelSmall, color: PixelColor.primary }}>
        {done}/{total}
      </span>
    </div>
  );
}

// ═══════════════════════════════ 대화상자 ═══════════════════════════════

/** RPG 대화상자. 4px 테두리 + 4px 그림자. `showsNext` 면 오른쪽 아래 ▼ 가 깜빡인다. */
export function PixelDialogueBox({ showsNext = true, children }: { showsNext?: boolean; children: ReactNode }) {
  return (
    <div className="pr-dialogue px-border-heavy px-shadow-card">
      {children}
      {showsNext && (
        <span className="pr-dialogue__next">
          <PixelBlink>
            <Icon name="caret" size={16} color={PixelColor.ink} />
          </PixelBlink>
        </span>
      )}
    </div>
  );
}

// ═══════════════════════════════ 화자 ═══════════════════════════════

/** 대화상자 왼쪽의 64×64 초상화 — **곱딱이** (앱 아이콘의 픽셀 감귤). */
export function PixelPortrait({ size = 64 }: { size?: number }) {
  return (
    <span className="pr-portrait px-border" style={{ width: size, height: size }} aria-hidden="true">
      <img src={images.gamgyul} alt="" className="px-pixelated" />
    </span>
  );
}

// ═══════════════════════════════ 타이핑 효과 ═══════════════════════════════

/** 글자 단위로 자른다 (조합형 이모지·한글이 반쯤 찍히지 않게). */
function splitGraphemes(text: string): string[] {
  const Seg = (Intl as unknown as { Segmenter?: new (l?: string, o?: { granularity: string }) => { segment(s: string): Iterable<{ segment: string }> } }).Segmenter;
  if (Seg) return Array.from(new Seg('ko', { granularity: 'grapheme' }).segment(text), (s) => s.segment);
  return Array.from(text);
}

function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
}

/**
 * 글자가 **한 글자씩** 나타난다 (1초에 26자). 누르면 **즉시 전부** 나타난다.
 * 자리는 처음부터 다 잡아 둔다 — 글자가 늘면서 상자가 커지면 아래 버튼이 흔들린다.
 * 「동작 줄이기」 사용자에게는 처음부터 다 보인다.
 *
 * `ready` 가 거짓이면 기다린다 — 곱딱이 **목소리가 시작될 때** 글자도 시작한다.
 * 줄이 바뀌면 부모가 key 로 새로 만든다.
 */
export function PixelTypewriter({
  text,
  ready,
  onFinished,
  charsPerSecond = 26,
}: {
  text: string;
  ready: boolean;
  onFinished: () => void;
  charsPerSecond?: number;
}) {
  const chars = useMemo(() => splitGraphemes(text), [text]);
  const [shown, setShown] = useState(0);
  /** 「동작 줄이기」면 글자를 찍지 않고 한 번에 보여준다. */
  const [instant] = useState(prefersReducedMotion);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  /** 눌러서 다 본 줄은 소리가 늦게 와도 다시 찍지 않는다. */
  const skipped = useRef(false);
  const finishedCb = useRef(onFinished);
  useEffect(() => {
    finishedCb.current = onFinished;
  });

  const stopTimer = () => {
    if (timer.current !== null) clearInterval(timer.current);
    timer.current = null;
  };

  useEffect(() => {
    if (!ready || skipped.current) return;
    if (instant || chars.length === 0) {
      finishedCb.current();
      return;
    }
    let i = 0;
    timer.current = setInterval(
      () => {
        i += 1;
        setShown(i);
        if (i >= chars.length) {
          stopTimer();
          finishedCb.current();
        }
      },
      1000 / Math.max(charsPerSecond, 1),
    );
    return stopTimer;
  }, [ready, chars, charsPerSecond, instant]);

  const finish = () => {
    stopTimer();
    skipped.current = true;
    setShown(chars.length);
    finishedCb.current();
  };

  return (
    <div className="pr-typewriter" onClick={finish}>
      <span className="pr-typewriter__ghost" aria-hidden="true">
        {text}
      </span>
      <span className="pr-typewriter__shown" aria-hidden="true">
        {instant && ready ? text : chars.slice(0, shown).join('')}
      </span>
      <span className="pr-visually-hidden">{text}</span>
    </div>
  );
}

// ═══════════════════════════════ 장면 위 버튼 · 배지 ═══════════════════════════════

/**
 * 장면 아래 버튼 — 시안 headline-md 24. 가득 = 주색, 아니면 가라앉은 면.
 * 단계마다 하나만 필요하면 한 칸이 폭을 다 쓴다.
 */
export function SceneButton({ title, filled, onPress }: { title: ReactNode; filled: boolean; onPress: () => void }) {
  return (
    <button
      type="button"
      className="pr-scene-btn px-border px-press"
      style={{
        background: filled ? PixelColor.primary : PixelColor.surfaceMid,
        color: filled ? PixelColor.onPrimary : PixelColor.ink,
      }}
      onClick={onPress}
    >
      <span className="pr-scene-btn__label">{title}</span>
    </button>
  );
}

/** 「NEW DISCOVERY」「FINAL」「CLEAR」 배지 — 자기 색이 채워져 있어 그림 위에 그냥 둬도 읽힌다. */
export function SceneBadge({ text, fill, label }: { text: string; fill: string; label: string }) {
  return (
    <span className={cx('pr-badge px-border px-shadow-small')} style={{ ...PixelFont.labelSmall, background: fill, color: label }}>
      {text}
    </span>
  );
}

/**
 * 정보판 — 대화창과 **일부러 다르게** 한다. 테두리가 얇고(2px), 바탕이 가라앉았다.
 * 글자가 있는 것은 반드시 상자에 담는다 — 배경 그림 위에 그냥 얹으면 돌담에서 사라진다.
 */
export function InfoFrame({ children }: { children: ReactNode }) {
  return <div className="pr-info px-border px-shadow-card">{children}</div>;
}
