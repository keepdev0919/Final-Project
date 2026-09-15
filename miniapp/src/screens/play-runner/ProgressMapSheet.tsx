/**
 * 러너 안에서 보는 진행 지도 — PlayRunnerView.swift 의 `ProgressMapSheet` 이식.
 *
 * ⚠️ **지금은 아무 데서도 열지 않는다** (Swift 와 같다). 2026-09-11 에 HUD 오른쪽 칸이 소리
 * 스위치가 되면서 내려갔고, Swift 도 「다른 자리에 다시 붙일 수 있다」며 부품만 남겨 두었다.
 * 다시 붙일 때: `<ProgressMapSheet open play clearedPointIds={clearedPointIds(play, progress)}
 * isFinished={progress.finalCleared} onClose/>`.
 *
 * PLAY 상세의 경로 안내와 같은 `PlayRouteMap`·`RouteListRow` 를 쓴다.
 */
import type { Play } from '../../api';
import { PixelSheet, PixelSpacing, PlayRouteMap, RouteListRow } from '../../ui';

export function ProgressMapSheet({
  open,
  play,
  clearedPointIds,
  isFinished,
  onClose,
}: {
  open: boolean;
  play: Play;
  clearedPointIds: Set<string>;
  isFinished: boolean;
  onClose: () => void;
}) {
  return (
    <PixelSheet open={open} onClose={onClose} title="진행 지도" height="large">
      <div style={{ display: 'flex', flexDirection: 'column', gap: PixelSpacing.m }}>
        <div className="px-border" style={{ height: 220 }}>
          <PlayRouteMap play={play} height={220} />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: PixelSpacing.s }}>
          {/* 시작은 러너에 들어온 시점에 이미 지난 일이라 항상 완료로 본다. */}
          <RouteListRow marker="START" text={play.startName} kind="terminal" done />
          {play.points.map((point, i) => (
            <RouteListRow key={point.id} marker={String(i + 1)} text={point.title} kind="step" done={clearedPointIds.has(point.id)} />
          ))}
          <RouteListRow marker="FINISH" text={play.finishName} kind="terminal" done={isFinished} />
        </div>
      </div>
    </PixelSheet>
  );
}
