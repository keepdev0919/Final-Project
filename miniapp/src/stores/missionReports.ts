/**
 * 미션 신고 대기열 — MissionReportSheet.swift 의 MissionReport · MissionReportStore 이식.
 *
 * 신고를 서버로 보내고, **못 보낸 것은 기기에 쌓아 다음에 다시 보낸다.**
 * 보낸 것은 서버에 있으므로 기기에 남기지 않는다. 러너가 열릴 때 `flush()` 한다.
 * 저장 키 `mission_reports_pending_v1`.
 */
import type { MissionReportReason } from '../api/types';
import { createJsonStore } from './jsonStore';
import type { KeyValueBackend } from './kv';

export const MISSION_REPORTS_KEY = 'mission_reports_pending_v1';

/** 신고 사유 — 화면 보기 순서와 문구. 서버 ALLOWED_REASONS 와 같다. */
export const MISSION_REPORT_REASONS: readonly { id: MissionReportReason; label: string }[] = [
  { id: 'notVisible', label: '대상이 보이지 않아요' },
  { id: 'blocked', label: '공사·통제 중이에요' },
  { id: 'mismatch', label: '설명과 실제 장소가 달라요' },
  { id: 'other', label: '기타' },
];

export interface MissionReport {
  id: string;
  playId: string;
  playTitle: string;
  missionId: string;
  missionTitle: string;
  reason: MissionReportReason;
  /** 자유 입력. 서버 한도 500자 — 넘치면 서버가 400 을 준다. */
  note: string;
  /** epoch ms */
  reportedAt: number;
}

/** 보내기 성공이면 true. 앱에서는 ReportAPI.mission 을 감싼 함수를 넣는다. */
export type SendReport = (r: MissionReport) => Promise<boolean>;

function isReport(v: unknown): v is MissionReport {
  if (typeof v !== 'object' || v === null) return false;
  const r = v as Record<string, unknown>;
  return typeof r.id === 'string' && typeof r.playId === 'string' && typeof r.reason === 'string';
}

export function createMissionReportQueue(backend: KeyValueBackend, send: SendReport) {
  const raw = createJsonStore<MissionReport[]>({
    backend,
    key: MISSION_REPORTS_KEY,
    empty: () => [],
    parse: (v) => (Array.isArray(v) ? v.filter(isReport) : null),
  });

  return {
    raw,
    hydrate: () => raw.hydrate(),
    pending: () => raw.get(),
    /** 보낸다. 실패하면 쌓아둔다. */
    async submit(report: MissionReport): Promise<'sent' | 'queued'> {
      if (await send(report)) return 'sent';
      await raw.set([...raw.get(), report]).catch(() => undefined);
      return 'queued';
    },
    /** 쌓인 것을 다시 보낸다. */
    async flush(): Promise<void> {
      const pending = raw.get();
      if (pending.length === 0) return;
      const left: MissionReport[] = [];
      for (const r of pending) if (!(await send(r))) left.push(r);
      await raw.set(left).catch(() => undefined);
    },
    whenIdle: () => raw.whenIdle(),
  };
}

/** 신고 id (클라이언트 쪽 식별용 — 서버는 자기 id 를 따로 만든다). */
export function newReportId(): string {
  return typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `r-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}
