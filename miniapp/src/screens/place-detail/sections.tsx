/**
 * 장소 상세 「장소 정보」 탭의 두 구역 — 원본: PlaceInfoSections.swift (2026-09-10 조익준님 결정).
 *
 *   이용 정보  → 시안 A 「칩과 카드」: 한 마디 정보는 칩으로 한 줄에, 운영시간·입장료처럼
 *                긴 것만 카드로.
 *   무장애 정보 → 시안 C 「현장 대시보드」: 있음·가능은 아이콘 타일로, 설명 문장은
 *                읽는 글꼴로 상자 하나에.
 *   두 구역의 제목·밑줄은 잉크, 아이콘만 파랑.
 *
 * 무엇을 칩·카드·타일로 가를지는 infoText.ts 에 있다.
 */
import type { PlaceInfoRow } from '../../api';
import { Icon, PixelChip, PixelColor, PixelFont, PixelSectionHeader } from '../../ui';
import {
  isAsideItem,
  parsePlaceInfoText,
  priceTableOf,
  splitAccessibility,
  splitUsage,
  usageCardIcon,
  type AccessNote,
  type AccessTile,
  type InfoGroup,
  type PriceTable,
} from './infoText';

// ═══════════════════════════════ 이용 정보 (시안 A) ═══════════════════════════════

export function PlaceUsageSection({ rows }: { rows: PlaceInfoRow[] }) {
  const { chips, cards } = splitUsage(rows);
  return (
    <section className="plc-section">
      <PixelSectionHeader title="이용 정보" icon="book" iconColor={PixelColor.secondary} />
      {chips.length > 0 && (
        // PixelWrap — 왼쪽부터 채우고 넘치면 다음 줄로.
        <div className="plc-wrap">
          {chips.map((chip, i) => (
            <PixelChip key={`${chip.text}-${i}`} text={chip.text} icon={chip.icon} />
          ))}
        </div>
      )}
      {cards.map((row, i) => (
        <UsageCard key={`${row.label}-${i}`} row={row} />
      ))}
    </section>
  );
}

function UsageCard({ row }: { row: PlaceInfoRow }) {
  const text = parsePlaceInfoText(row.value);
  const table = priceTableOf(text);
  return (
    <div className="plc-usage-card px-border px-shadow-card">
      <div className="plc-usage-card__head">
        <Icon name={usageCardIcon(row.label)} size={18} color={PixelColor.inkWeak} />
        <span style={{ ...PixelFont.label, color: PixelColor.inkWeak }}>{row.label}</span>
      </div>
      {table ? (
        <PriceTableView table={table} />
      ) : (
        text.groups.map((group, index) => <GroupBlock key={index} group={group} isFirst={index === 0} />)
      )}
      {text.footnotes.map((note, i) => (
        <p key={i} className="plc-p" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
          {note}
        </p>
      ))}
    </div>
  );
}

/**
 * `[하절기/간절기(3월~11월)]` 머리는 노란(첫 묶음)·옅은 칩으로, 항목은 그 아래.
 * 「입장 마감 17:30」·「마지막 주문 22:00」 같은 곁말은 작게.
 */
function GroupBlock({ group, isFirst }: { group: InfoGroup; isFirst: boolean }) {
  return (
    <div className="plc-group">
      {group.header !== null && (
        <span
          className="plc-group__header px-border"
          style={{ ...PixelFont.labelSmall, color: PixelColor.ink, background: isFirst ? PixelColor.accent : PixelColor.surfaceLow }}
        >
          {group.header}
        </span>
      )}
      {group.items.map((item, i) => {
        const aside = isAsideItem(item);
        return (
          <p
            key={i}
            className="plc-p"
            style={aside ? { ...PixelFont.labelSmall, color: PixelColor.inkWeak } : { ...PixelFont.body, color: PixelColor.ink }}
          >
            {item}
          </p>
        );
      })}
    </div>
  );
}

/** 구분 | 개인 | 단체 표. 첫 값 열은 잉크, 나머지는 옅게 — 대개 첫 열이 「내가 낼 값」이다. */
function PriceTableView({ table }: { table: PriceTable }) {
  return (
    <div className="plc-price">
      <div className="plc-price__head">
        <span className="plc-price__name" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
          원
        </span>
        {table.columns.map((column, i) => (
          <span key={i} className="plc-price__col plc-clamp2" style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>
            {column}
          </span>
        ))}
      </div>
      {table.rows.map((row, index) => (
        <div key={index} className={`plc-price__row${index < table.rows.length - 1 ? ' plc-price__row--rule' : ''}`}>
          <span className="plc-price__name" style={{ ...PixelFont.label, color: PixelColor.ink }}>
            {row.name}
          </span>
          {row.prices.map((price, column) => (
            <span
              key={column}
              className="plc-price__col"
              style={{ ...PixelFont.body, color: column === 0 ? PixelColor.ink : PixelColor.inkWeak }}
            >
              {price}
            </span>
          ))}
        </div>
      ))}
    </div>
  );
}

// ═══════════════════════════════ 무장애 정보 (시안 C) ═══════════════════════════════

export function PlaceAccessibilitySection({ rows }: { rows: PlaceInfoRow[] }) {
  const { tiles, notes } = splitAccessibility(rows);
  return (
    <section className="plc-section">
      <PixelSectionHeader title="무장애 정보" icon="wheelchair" iconColor={PixelColor.secondary} />
      {tiles.length > 0 && (
        <div className="plc-tiles">
          {tiles.map((tile, i) => (
            <TileView key={`${tile.label}-${i}`} tile={tile} />
          ))}
        </div>
      )}
      {notes.length > 0 && (
        <div className="plc-notes px-border">
          {notes.map((note, i) => (
            <NoteRow key={`${note.label}-${i}`} note={note} />
          ))}
        </div>
      )}
    </section>
  );
}

function TileView({ tile }: { tile: AccessTile }) {
  return (
    <div className="plc-tile px-border px-shadow-small">
      <Icon name={tile.icon} size={26} color={PixelColor.ink} />
      <span className="plc-clamp2" style={{ ...PixelFont.labelSmall, color: PixelColor.ink, textAlign: 'center' }}>
        {tile.label}
      </span>
    </div>
  );
}

function NoteRow({ note }: { note: AccessNote }) {
  return (
    <div className="plc-note">
      <Icon
        name={note.warns ? 'warn' : 'wheelchair'}
        size={20}
        color={note.warns ? PixelColor.error : PixelColor.primary}
      />
      <div className="plc-note__text">
        <span style={{ ...PixelFont.labelSmall, color: PixelColor.inkWeak }}>{note.label}</span>
        <p
          className="plc-p plc-pre"
          style={{ ...PixelFont.reading, color: PixelColor.ink, lineHeight: 'calc(14px * var(--px-line) + 3px)' }}
        >
          {note.text}
        </p>
      </div>
    </div>
  );
}
