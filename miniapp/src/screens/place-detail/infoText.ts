/**
 * 장소 상세 「장소 정보」 탭의 순수 로직 — 원본: PlaceInfoSections.swift + PlaceDetailView.swift 의
 * usageRows · sourceLines · hasKTOData.
 *
 * 화면 모양(React)은 sections.tsx, 여기엔 **무엇을 칩·카드·타일·설명으로 가를지**만 둔다.
 * Swift 의 판단 순서·문구·길이 기준을 그대로 옮겼다. 길이는 Swift `String.count`(글자 수)와
 * 맞추려고 UTF-16 길이가 아니라 코드포인트 수로 센다.
 */
import type { IconName } from '../../ui';
import type { PlaceDetail, PlaceInfoRow, PlaceNearby } from '../../api';
import { hasIntroduction } from '../../api';

/** Swift `String.count` 에 가깝게 — 한글·영문은 한 글자 = 1. */
const charCount = (s: string) => Array.from(s).length;

/** Swift `trimmingCharacters(in: .whitespaces)` — 줄바꿈은 건드리지 않고 공백·탭만. */
const trimSpaces = (s: string) => s.replace(/^[ \t 　]+|[ \t 　]+$/g, '');

// ═══════════════════════════════ KTO 원문 파서 ═══════════════════════════════

export interface InfoGroup {
  header: string | null;
  items: string[];
}

export interface PriceTable {
  columns: string[];
  rows: { name: string; prices: string[] }[];
}

export interface PlaceInfoText {
  groups: InfoGroup[];
  footnotes: string[];
}

/**
 * KTO 이용정보 한 칸의 값을 `[머리]` · `- 항목` · `※ 각주` 로 나눈다.
 *
 *     [개인]
 *     - 성인 12,000원
 *     [단체(30명 이상)]
 *     - 성인 10,000원
 *     ※ 자세한 입장료는 공식 홈페이지 참조
 */
export function parsePlaceInfoText(raw: string): PlaceInfoText {
  const groups: InfoGroup[] = [];
  const notes: string[] = [];
  for (const piece of raw.split('\n')) {
    const line = trimSpaces(piece);
    if (line.length === 0) continue;
    if (line.startsWith('[') && line.endsWith(']') && charCount(line) > 2) {
      groups.push({ header: line.slice(1, -1), items: [] });
    } else if (line.startsWith('※') || line.startsWith('*')) {
      notes.push(trimSpaces(Array.from(line).slice(1).join('')));
    } else {
      let item = line;
      if (item.startsWith('-')) item = trimSpaces(item.slice(1));
      if (groups.length === 0) groups.push({ header: null, items: [] });
      groups[groups.length - 1].items.push(item);
    }
  }
  return { groups, footnotes: notes };
}

/** 「청소년/경로/군인 10,000원」 → { name: 청소년/경로/군인, price: 10,000 } */
function splitPrice(text: string): { name: string; price: string } | null {
  const m = /^(.+?)\s+([\d,]+)\s*원$/u.exec(text);
  if (!m) return null;
  return { name: m[1], price: m[2] };
}

/**
 * 묶음마다 같은 이름의 항목이 「이름 금액원」 꼴이면 표로 그릴 수 있다.
 * 카멜리아힐처럼 `[개인]`·`[단체]` 가 같은 구분(성인·청소년·어린이)을 갖는 경우다.
 */
export function priceTableOf(text: PlaceInfoText): PriceTable | null {
  const { groups } = text;
  if (groups.length < 2 || !groups.every((g) => g.header !== null && g.items.length > 0)) return null;
  const parsed: { name: string; price: string }[][] = [];
  for (const group of groups) {
    const rows: { name: string; price: string }[] = [];
    for (const item of group.items) {
      const split = splitPrice(item);
      if (!split) return null;
      rows.push(split);
    }
    parsed.push(rows);
  }
  const names = parsed[0].map((r) => r.name);
  const sameNames = (rows: { name: string }[]) =>
    rows.length === names.length && rows.every((r, i) => r.name === names[i]);
  if (!parsed.every(sameNames)) return null;
  return {
    columns: groups.map((g) => g.header as string),
    rows: names.map((name, index) => ({ name, prices: parsed.map((rows) => rows[index].price) })),
  };
}

// ═══════════════════════════════ 이용 정보 (시안 A) ═══════════════════════════════

export interface UsageChip {
  text: string;
  icon: IconName;
}

function isShort(text: string, max: number): boolean {
  return !text.includes('\n') && charCount(text) <= max;
}

/**
 * **한 마디로 끝나는 것은 칩, 나머지는 카드.** (PlaceUsageSection.split)
 *
 * 주차는 「주차: 가능」과 「주차요금: 무료」가 따로 두 줄이던 것을 「주차 무료」 한
 * 칩으로 합친다. 「화장실: 있음」은 「화장실」로, 「휴무일: 연중무휴」는 「연중무휴」로 —
 * 이름표와 값이 같은 말을 두 번 하지 않게.
 */
export function splitUsage(rows: PlaceInfoRow[]): { chips: UsageChip[]; cards: PlaceInfoRow[] } {
  const chips: UsageChip[] = [];
  const cards: PlaceInfoRow[] = [];
  const byLabel = new Map<string, string>();
  for (const r of rows) if (!byLabel.has(r.label)) byLabel.set(r.label, r.value);
  const consumed = new Set<string>();

  for (const row of rows) {
    if (consumed.has(row.label)) continue;
    const value = row.value;
    const oneLine = !value.includes('\n');

    if (row.label === '주차') {
      consumed.add('주차');
      const fee = byLabel.get('주차요금');
      // 「가능 (약 대형 60대, 소형 75대)」 처럼 대수·조건이 붙은 값은 칩으로
      // 접지 않는다 — 렌터카 여행자가 현장에서 제일 먼저 찾는 정보다.
      const bare = oneLine && (value === '가능' || value === '있음');
      if (oneLine && isShort(value, 6) && (value.includes('불가') || value.includes('없음'))) {
        chips.push({ text: '주차 불가', icon: 'car' });
      } else if (bare && fee !== undefined && isShort(fee, 6)) {
        consumed.add('주차요금');
        chips.push({ text: `주차 ${fee}`, icon: 'car' });
      } else if (bare) {
        chips.push({ text: '주차 가능', icon: 'car' });
      } else {
        cards.push(row);
      }
      continue;
    }

    if (!oneLine) {
      cards.push(row);
      continue;
    }
    if (row.label === '휴무일' && isShort(value, 10)) {
      chips.push({ text: value.includes('무휴') ? value : `휴무 ${value}`, icon: 'dayOpen' });
    } else if (row.label === '운영시간' && isShort(value, 14)) {
      chips.push({ text: value, icon: 'clock' });
    } else if (row.label === '화장실' && isShort(value, 6)) {
      chips.push({ text: value === '있음' ? '화장실' : `화장실 ${value}`, icon: 'wc' });
    } else if (row.label === '입장료' && isShort(value, 8)) {
      chips.push({ text: value === '무료' ? '입장료 무료' : `입장료 ${value}`, icon: 'ticket' });
    } else if (row.label === '주차요금' && isShort(value, 6)) {
      chips.push({ text: `주차 ${value}`, icon: 'car' });
    } else if (charCount(row.label + value) <= 12) {
      chips.push({ text: `${row.label} ${value}`, icon: 'info' });
    } else {
      cards.push(row);
    }
  }
  return { chips, cards };
}

export function usageCardIcon(label: string): IconName {
  switch (label) {
    case '운영시간':
      return 'clock';
    case '휴무일':
      return 'dayOpen';
    case '입장료':
      return 'ticket';
    case '주차':
    case '주차요금':
      return 'car';
    case '화장실':
      return 'wc';
    default:
      return 'info';
  }
}

/** 「입장 마감 17:30」·「마지막 주문 22:00」 같은 곁말은 작게. */
export function isAsideItem(item: string): boolean {
  return item.includes('마감') || item.includes('마지막 주문') || item.includes('준비시간');
}

/**
 * 이용팁(운영시간·휴무일·입장료·주차)과 반복정보(화장실·주차요금·해설 안내)를
 * **한 목록**으로 합친다. 같은 것을 두 군데서 말하지 않도록, 이용팁에 입장료가
 * 있으면 반복정보의 입장료는 뺀다. KTO 반복정보는 같은 이름표를 두 번 주기도 해서
 * 이름표당 하나만 둔다. (PlaceDetailView.usageRows)
 */
export function usageRows(detail: PlaceDetail): PlaceInfoRow[] {
  const rows: PlaceInfoRow[] = [
    { label: '운영시간', value: detail.openTime },
    { label: '휴무일', value: detail.restDate },
    { label: '입장료', value: detail.useFee },
    { label: '주차', value: detail.parking },
  ].filter((r) => r.value.length > 0);
  const taken = new Set(rows.map((r) => r.label));
  for (const row of detail.info) {
    if (taken.has(row.label)) continue;
    taken.add(row.label);
    rows.push(row);
  }
  return rows;
}

// ═══════════════════════════════ 무장애 정보 (시안 C) ═══════════════════════════════

export interface AccessTile {
  label: string;
  icon: IconName;
}

export interface AccessNote {
  label: string;
  text: string;
  warns: boolean;
}

// 「휠체어 접근 불가능」은 `가능` 으로 끝나고, 「가능하나 계단 있음」은 `가능` 으로
// 시작한다. 부정어가 하나라도 있으면 타일이 아니라 설명이다 — 무장애 정보는
// 틀리면 없느니만 못하다.
const NEGATIVES = ['주의', '없음', '불가', '어려', '제한', '하나', '지만'];

const warns = (text: string) => NEGATIVES.some((n) => text.includes(n));

/** 값이 「있다」는 뜻이면 남는 꼬리를 돌려준다(없으면 빈 문자열). 아니면 null. */
export function availabilityRemainder(value: string): string | null {
  if (NEGATIVES.some((n) => value.includes(n))) return null;
  const leads = ['대여가능', '대여 가능', '이용가능', '이용 가능', '있음', '가능'];
  for (const lead of leads) {
    if (!value.startsWith(lead)) continue;
    let rest = trimSpaces(value.slice(lead.length));
    if (rest.startsWith('(') && rest.endsWith(')')) rest = rest.slice(1, -1);
    return rest;
  }
  // 「장애인 주차장 있음」·「기저귀교환대 있음」·「주출입구는 턱이 없어 휠체어 접근 가능함」
  const tails = ['있음', '가능함', '가능'];
  if (charCount(value) <= 14 && tails.some((t) => value.endsWith(t))) return '';
  return null;
}

export function accessibilityIcon(label: string): IconName {
  switch (label) {
    case '장애인 주차':
      return 'parkingSign';
    case '장애인 화장실':
      return 'wheelchairForward';
    case '휠체어 대여':
      return 'wheelchair';
    case '유모차 대여':
    case '유아 편의':
      return 'stroller';
    case '수유실':
      return 'nursing';
    case '대중교통':
      return 'bus';
    case '엘리베이터':
      return 'up';
    case '점자블록':
    case '점자 안내물':
    case '시각장애 편의':
      return 'eye';
    case '음성 안내':
      return 'sound';
    case '수어·영상 안내':
    case '청각장애 편의':
      return 'hearing';
    case '안내 인력':
      return 'person';
    case '안내견 동반':
    case '접근로':
      return 'walk';
    case '출입구':
      return 'gate';
    case '매표소':
      return 'ticket';
    default:
      return 'check';
  }
}

/**
 * **「있음·가능」으로 끝나는 짧은 값은 타일, 문장은 설명 상자.** (PlaceAccessibilitySection.split)
 *
 * 「장애인 주차 / 장애인 주차장 있음」은 타일 「장애인 주차」 하나로 접힌다.
 * 「대여가능(1대/관리사무소)」처럼 꼬리가 붙으면 타일을 두고 꼬리는 상자에 적는다.
 * 「주의」·「없음」·「불가」가 든 문장은 경고색으로.
 */
export function splitAccessibility(rows: PlaceInfoRow[]): { tiles: AccessTile[]; notes: AccessNote[] } {
  const tiles: AccessTile[] = [];
  const notes: AccessNote[] = [];
  for (const row of rows) {
    const value = trimSpaces(row.value);
    const remainder = availabilityRemainder(value);
    if (remainder !== null) {
      tiles.push({ label: row.label, icon: accessibilityIcon(row.label) });
      if (remainder.length > 0) notes.push({ label: row.label, text: remainder, warns: warns(remainder) });
    } else {
      notes.push({ label: row.label, text: value, warns: warns(value) });
    }
  }
  return { tiles, notes };
}

// ═══════════════════════════════ 출처 ═══════════════════════════════

export const KTO_ATTRIBUTION = '관광정보 출처: ⓒ한국관광공사';

/**
 * KTO 에서 받은 것이 하나라도 있는가. 하나도 없으면 출처를 적을 이유가 없다 —
 * 지도와 주소는 우리 좌표에서 나온 것이다.
 */
export function hasKTOData(d: PlaceDetail): boolean {
  return (
    hasIntroduction(d) ||
    d.address.length > 0 ||
    d.tel.length > 0 ||
    d.openTime.length > 0 ||
    d.restDate.length > 0 ||
    d.useFee.length > 0 ||
    d.parking.length > 0 ||
    d.info.length > 0 ||
    d.accessibility.length > 0
  );
}

/** 장소 정보 탭의 출처 — 이용 정보·무장애 정보·주변 시설이 실제로 쓴 것만 한 구역에. */
export function sourceLines(detail: PlaceDetail, nearby: PlaceNearby | undefined): string[] {
  const lines: string[] = [];
  if (hasKTOData(detail)) lines.push(KTO_ATTRIBUTION);
  if (nearby && nearby.toilets.length > 0) lines.push('화장실 출처: 제주특별자치도 제주시');
  if (nearby && nearby.busStops.length > 0) lines.push('정류장 출처: 국토교통부(TAGO)');
  return lines;
}
