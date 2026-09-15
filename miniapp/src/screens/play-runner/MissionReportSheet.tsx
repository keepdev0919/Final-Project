/**
 * 「현장에서 찾을 수 없어요」 — Views/Components/MissionReportSheet.swift 이식.
 *
 * 콘텐츠가 현실과 어긋났을 때 알리는 곳. 제주 5곳을 직접 답사하지 않기로 했으므로(2026-09-02)
 * **이 신고 경로가 콘텐츠 QA 의 눈이다.**
 *
 * 못 보내도 잃지 않는다 — 서버(`POST /report/mission`)로 못 보내면 기기에 쌓아 두고 다음에
 * 다시 보낸다(공용 `missionReportQueue`, 러너가 열릴 때 flush). 사용자에게는 어느 쪽이든
 * 「기록했어요」라고 말한다. 화면은 보내기를 기다리지 않는다.
 *
 * 틀은 공용 `PixelSheet`(제목 · 닫기 ✕ · 하단 safe area). 닫히면 내용이 사라져 다음에 열면 새로 쓴다.
 */
import { useState } from 'react';
import type { MissionReportReason } from '../../api';
import { MISSION_REPORT_REASONS, missionReportQueue, newReportId } from '../../stores';
import { Icon, PixelButton, PixelColor, PixelFont, PixelSheet, PixelSpacing } from '../../ui';

/** 서버 한도 (backend/routers/report.py note ≤ 500자). 넘치면 400 이라 대기열에 영영 남는다. */
const NOTE_MAX = 500;

export function MissionReportSheet({
  open,
  playId,
  playTitle,
  missionId,
  missionTitle,
  onDone,
}: {
  open: boolean;
  playId: string;
  playTitle: string;
  missionId: string;
  missionTitle: string;
  onDone: () => void;
}) {
  return (
    <PixelSheet open={open} onClose={onDone} title="현장과 다른가요?" height="large">
      <ReportBody playId={playId} playTitle={playTitle} missionId={missionId} missionTitle={missionTitle} onDone={onDone} />
    </PixelSheet>
  );
}

function ReportBody({
  playId,
  playTitle,
  missionId,
  missionTitle,
  onDone,
}: {
  playId: string;
  playTitle: string;
  missionId: string;
  missionTitle: string;
  onDone: () => void;
}) {
  const [reason, setReason] = useState<MissionReportReason | null>(null);
  const [note, setNote] = useState('');
  const [sent, setSent] = useState(false);

  if (sent) {
    return (
      <div className="pr-report pr-report--sent">
        <Icon name="check" size={48} color={PixelColor.done} />
        <h3 style={{ ...PixelFont.sectionTitle, color: PixelColor.ink, margin: 0 }}>기록했어요</h3>
        <p style={{ ...PixelFont.body, color: PixelColor.inkWeak, textAlign: 'center', whiteSpace: 'pre-line', margin: 0 }}>
          {'이 미션을 다시 살펴보겠습니다.\n건너뛰고 계속 진행하셔도 됩니다.'}
        </p>
        <PixelButton title="닫기" kind="primary" onClick={onDone} />
      </div>
    );
  }

  return (
    <div className="pr-report">
      <h3 style={{ ...PixelFont.sectionTitle, color: PixelColor.ink, margin: 0 }}>{missionTitle}</h3>
      <p style={{ ...PixelFont.body, color: PixelColor.inkWeak, margin: 0 }}>무엇이 달랐나요?</p>

      <div className="pr-stack-s" role="radiogroup" aria-label="무엇이 달랐나요?">
        {MISSION_REPORT_REASONS.map((r) => {
          const on = reason === r.id;
          return (
            <button
              key={r.id}
              type="button"
              role="radio"
              aria-checked={on}
              className="px-reset-button pr-option px-border"
              style={{ background: on ? PixelColor.surfaceHigh : PixelColor.surface }}
              onClick={() => setReason(r.id)}
            >
              <span style={{ ...PixelFont.body, color: PixelColor.ink, flex: '1 1 auto' }}>{r.label}</span>
              {on && <Icon name="check" size={18} color={PixelColor.primary} />}
            </button>
          );
        })}
      </div>

      <label className="pr-stack-s" style={{ display: 'flex' }}>
        <span style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>더 알려주실 것이 있나요? (선택)</span>
        <span className="pr-field px-border" style={{ padding: PixelSpacing.m }}>
          <textarea
            className="pr-field__input pr-field__textarea"
            style={{ ...PixelFont.body, textAlign: 'left' }}
            rows={3}
            maxLength={NOTE_MAX}
            placeholder="예: 문이 닫혀 있어서 안 보였어요"
            value={note}
            onChange={(e) => {
              setNote(e.target.value);
              // Swift `lineLimit(3...5)` — 5줄까지 늘어나고 그 뒤로는 안에서 스크롤한다.
              const t = e.currentTarget;
              t.style.height = 'auto';
              const line = 16 * 1.3333;
              t.style.height = `${Math.min(Math.max(t.scrollHeight, line * 3), line * 5)}px`;
            }}
          />
        </span>
      </label>

      <PixelButton
        title="보내기"
        kind="primary"
        disabled={reason === null}
        style={{ opacity: reason === null ? 0.4 : 1 }}
        onClick={() => {
          if (!reason) return;
          // 화면은 기다리지 않는다. 보내는 동안 붙잡아두면 통신이 느린 현장에서 멈춘 것처럼 보인다.
          setSent(true);
          void missionReportQueue.submit({
            id: newReportId(),
            playId,
            playTitle,
            missionId,
            missionTitle,
            reason,
            note,
            reportedAt: Date.now(),
          });
        }}
      />

      <p style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak, margin: 0 }}>
        보내주신 내용은 콘텐츠를 고치는 데만 씁니다. 위치나 사진은 함께 보내지 않습니다.
      </p>
    </div>
  );
}
