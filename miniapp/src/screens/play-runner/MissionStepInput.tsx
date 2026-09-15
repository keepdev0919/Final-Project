/**
 * Mission Step 하나의 입력 — Views/Components/MissionStepInput.swift 이식.
 *
 * **Challenge Pattern 과 Input 은 다른 축이다** (`콘텐츠.md` §10). 화면을 정하는 것은
 * `inputType` 하나뿐이라 이 부품 하나가 여섯 가지 입력을 전부 처리한다.
 *
 *     CONFIRM      [찾았어요] — 누르면 통과. 다음 Step 이 진짜 검증을 한다
 *     CHOICE       보기 선택 (글자 · 그림)
 *     DIRECTION    왼쪽 / 오른쪽
 *     NUMBER       개수
 *     SHORT_TEXT   현판·각인처럼 짧고 명확한 답
 *     MATCH_ORDER  짝 맞추기 또는 순서 세우기
 *
 * 맞는지 판정은 부모가 한다 (`onSubmit`).
 */
import { useRef, useState } from 'react';
import type { MissionAnswer, MissionStep } from '../../api';
import { Icon, PixelButton, PixelColor, PixelFont } from '../../ui';

type Submit = (answer: MissionAnswer) => void;

export function MissionStepInput({ step, onSubmit }: { step: MissionStep; onSubmit: Submit }) {
  switch (step.inputType) {
    case 'CONFIRM':
      return <PixelButton title="찾았어요" kind="primary" onClick={() => onSubmit(null)} />;
    case 'CHOICE':
      return <ChoiceInput step={step} onSubmit={onSubmit} />;
    case 'DIRECTION':
      return <DirectionInput onSubmit={onSubmit} />;
    case 'NUMBER':
      return <NumberInput onSubmit={onSubmit} />;
    case 'SHORT_TEXT':
      return <ShortTextInput onSubmit={onSubmit} />;
    case 'MATCH_ORDER':
      return <MatchOrderInput step={step} onSubmit={onSubmit} />;
    default:
      return null;
  }
}

// ═══════════════════════════════ CHOICE ═══════════════════════════════

/**
 * 보기 선택. 현실을 보고 온 사용자가 답을 내는 자리다.
 * 그림 보기는 실사 사진이라 보간을 끄지 않는다(px-pixelated 금지).
 */
function ChoiceInput({ step, onSubmit }: { step: MissionStep; onSubmit: Submit }) {
  const [picked, setPicked] = useState<string | null>(null);
  const hasImages = step.options.some((o) => o.image != null);
  return (
    <div className="pr-stack-m">
      {step.options.map((option) => {
        const selected = picked === option.id;
        return (
          <button
            key={option.id}
            type="button"
            className="px-reset-button pr-option px-border"
            aria-pressed={selected}
            style={{ background: selected ? PixelColor.surfaceHigh : PixelColor.surface }}
            onClick={() => {
              setPicked(option.id);
              onSubmit(option.id);
            }}
          >
            {hasImages && option.image && (
              <span className="pr-option__image px-border">
                <OptionImage src={option.image} />
              </span>
            )}
            <span style={{ ...PixelFont.body, color: PixelColor.ink, flex: '1 1 auto', minWidth: 0 }}>{option.label}</span>
          </button>
        );
      })}
    </div>
  );
}

/** AsyncImage — 불러오기 전·실패하면 가라앉은 면만 남는다. */
function OptionImage({ src }: { src: string }) {
  const [ok, setOk] = useState(false);
  return <img src={src} alt="" loading="lazy" style={{ opacity: ok ? 1 : 0 }} onLoad={() => setOk(true)} onError={() => setOk(false)} />;
}

// ═══════════════════════════════ DIRECTION ═══════════════════════════════

/**
 * 왼쪽 / 오른쪽. 위·아래는 콘텐츠에 아직 없어 두 개만 띄운다.
 * Swift 는 「← 왼쪽」「오른쪽 →」 글자 화살표 — 앱인토스 규칙대로 화살표는 SVG 로 그린다.
 */
function DirectionInput({ onSubmit }: { onSubmit: Submit }) {
  return (
    <div className="pr-direction">
      <button type="button" className="px-reset-button pr-direction__btn px-border" onClick={() => onSubmit('LEFT')}>
        <Icon name="back" size={20} color={PixelColor.ink} />
        <span>왼쪽</span>
      </button>
      <button type="button" className="px-reset-button pr-direction__btn px-border" onClick={() => onSubmit('RIGHT')}>
        <span>오른쪽</span>
        <Icon name="forward" size={20} color={PixelColor.ink} />
      </button>
    </div>
  );
}

// ═══════════════════════════════ NUMBER ═══════════════════════════════

function NumberInput({ onSubmit }: { onSubmit: Submit }) {
  const [text, setText] = useState('');
  const ref = useRef<HTMLInputElement>(null);
  const submit = () => {
    const t = text.trim();
    // Swift `Int(text.trimmingCharacters(in: .whitespaces))` — 정수가 아니면 아무 일도 없다.
    if (!/^[+-]?\d+$/.test(t)) return;
    ref.current?.blur();
    onSubmit(Number.parseInt(t, 10));
  };
  return (
    <div className="pr-stack-m">
      <span className="pr-field px-border">
        <input
          ref={ref}
          className="pr-field__input"
          style={{ ...PixelFont.screenTitle }}
          inputMode="numeric"
          pattern="[0-9]*"
          placeholder="숫자"
          aria-label="숫자"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') submit();
          }}
        />
      </span>
      <PixelButton title="확인" kind="primary" onClick={submit} />
    </div>
  );
}

// ═══════════════════════════════ SHORT_TEXT ═══════════════════════════════

/**
 * 현판·각인처럼 짧고 명확한 답. **허용 답안이 여러 개**라 표기가 조금 달라도 통과한다
 * (공용 `isCorrect` — 공백·대소문자 무시).
 */
function ShortTextInput({ onSubmit }: { onSubmit: Submit }) {
  const [text, setText] = useState('');
  const ref = useRef<HTMLInputElement>(null);
  const submit = () => {
    const t = text.trim();
    if (!t) return;
    ref.current?.blur();
    onSubmit(t);
  };
  return (
    <div className="pr-stack-m">
      <span className="pr-field px-border">
        <input
          ref={ref}
          className="pr-field__input"
          style={{ ...PixelFont.bodyLarge }}
          placeholder="본 대로 적어주세요"
          aria-label="본 대로 적어주세요"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') submit();
          }}
        />
      </span>
      <PixelButton title="확인" kind="primary" onClick={submit} />
    </div>
  );
}

// ═══════════════════════════════ MATCH_ORDER ═══════════════════════════════

/**
 * 짝 맞추기(왼쪽↔오른쪽) 또는 순서 세우기. 성읍 FINAL 이 이걸 쓴다 — **직접 발견한 것**을 이어 붙인다.
 * 드래그를 쓰지 않는다. 현장에서 한 손으로, 장갑을 끼고도 눌러야 한다.
 */
function MatchOrderInput({ step, onSubmit }: { step: MissionStep; onSubmit: Submit }) {
  const [selectedLeft, setSelectedLeft] = useState<string | null>(null);
  const [pairs, setPairs] = useState<Record<string, string>>({}); // leftId → rightId
  const [order, setOrder] = useState<string[]>([]); // 순서 세우기용

  const isMatching = step.matchTargets.length > 0;
  const ready = isMatching ? Object.keys(pairs).length === step.options.length : order.length === step.options.length;

  return (
    <div className="pr-stack-l">
      {isMatching ? (
        <div className="pr-match">
          <div className="pr-stack-s">
            {step.options.map((o) => {
              const rid = pairs[o.id];
              return (
                <OrderChip
                  key={o.id}
                  label={o.label}
                  selected={selectedLeft === o.id}
                  done={rid !== undefined}
                  trailing={rid !== undefined ? (step.matchTargets.find((t) => t.id === rid)?.label ?? null) : null}
                  onPress={() => setSelectedLeft((cur) => (cur === o.id ? null : o.id))}
                />
              );
            })}
          </div>
          <div className="pr-stack-s">
            {step.matchTargets.map((t) => (
              <OrderChip
                key={t.id}
                label={t.label}
                selected={false}
                done={Object.values(pairs).includes(t.id)}
                trailing={null}
                onPress={() => {
                  if (!selectedLeft) return;
                  // 같은 오른쪽을 두 번 쓰지 않게, 먼저 쓰던 짝을 푼다.
                  const next = Object.fromEntries(Object.entries(pairs).filter(([, v]) => v !== t.id));
                  next[selectedLeft] = t.id;
                  setPairs(next);
                  setSelectedLeft(null);
                }}
              />
            ))}
          </div>
        </div>
      ) : (
        <div className="pr-stack-s">
          {step.options.map((o) => {
            const idx = order.indexOf(o.id);
            return (
              <OrderChip
                key={o.id}
                label={o.label}
                selected={false}
                done={idx >= 0}
                trailing={idx >= 0 ? String(idx + 1) : null}
                onPress={() => setOrder((cur) => (cur.includes(o.id) ? cur.filter((x) => x !== o.id) : [...cur, o.id]))}
              />
            );
          })}
        </div>
      )}

      <PixelButton
        title="확인"
        kind="primary"
        disabled={!ready}
        style={{ opacity: ready ? 1 : 0.4 }}
        onClick={() => {
          if (!ready) return;
          onSubmit(isMatching ? Object.entries(pairs).map(([l, r]) => `${l}>${r}`) : order);
        }}
      />
    </div>
  );
}

function OrderChip({
  label,
  selected,
  done,
  trailing,
  onPress,
}: {
  label: string;
  selected: boolean;
  done: boolean;
  trailing: string | null;
  onPress: () => void;
}) {
  return (
    <button
      type="button"
      className="px-reset-button pr-chip-btn px-border"
      aria-pressed={selected}
      style={{ background: done ? PixelColor.done : selected ? PixelColor.surfaceHigh : PixelColor.surface }}
      onClick={onPress}
    >
      <span style={{ ...PixelFont.body, color: done ? PixelColor.onDone : PixelColor.ink, minWidth: 0 }}>{label}</span>
      {trailing && <span style={{ ...PixelFont.labelSmall, color: done ? PixelColor.onDone : PixelColor.inkWeak }}>{trailing}</span>}
    </button>
  );
}
