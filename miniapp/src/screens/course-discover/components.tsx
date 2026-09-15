/**
 * 코스 탭 부품 — TasteDiscoveryView.swift 의 JejuOverworldPicker · RegionSpot,
 * CourseListView.swift 의 CourseCard, 그리고 당겨서 새로고침(`.refreshable`) 자리.
 */
import { useEffect, useState, type CSSProperties } from 'react';
import { courseListItemHeadline, courseListItemRegion, type CourseListItem } from '../../api';
import { regionColors, WHOLE_ISLAND_ID } from '../../lib/region';
import { Icon, images, PixelBob, PixelColor, PixelFont, PixelPlaceholderScene } from '../../ui';

// ═══════════════════════════════ 픽셀 제주 지도 권역 선택 ═══════════════════════════════

/** 그림 위에서 버튼이 앉는 자리. 가로·세로 **비율**이라 화면 크기가 달라져도 안 밀린다. */
interface RegionSpot {
  id: string;
  label: string;
  sublabel: string;
  x: number;
  y: number;
  /** 떠다니기 시작을 어긋나게 하는 시간(초) */
  bobDelay: number;
}

/**
 * 지형이 아니라 카드 틀에 맞춘 나침반 배치 (2026-09-10). 북·남은 가로 정중앙 위·아래,
 * 서·동은 세로 정중앙 왼·오른쪽. 「전역」만 우하단 바다 구석 — 남부와 같은 높이.
 * 「전역 / 제주 전체」는 네 권역과 줄 수를 맞추려는 두 줄이다.
 */
const REGION_SPOTS: readonly RegionSpot[] = [
  { id: '북부', label: '북부', sublabel: '제주시', x: 0.5, y: 0.2, bobDelay: 0.0 },
  { id: '동부', label: '동부', sublabel: '성산·구좌', x: 0.86, y: 0.5, bobDelay: 0.45 },
  { id: '서부', label: '서부', sublabel: '한림·애월', x: 0.14, y: 0.5, bobDelay: 0.9 },
  { id: '남부', label: '남부', sublabel: '서귀포', x: 0.5, y: 0.8, bobDelay: 1.35 },
  { id: WHOLE_ISLAND_ID, label: '전역', sublabel: '제주 전체', x: 0.86, y: 0.8, bobDelay: 1.8 },
];

/**
 * 그림 한 장 위에 권역 버튼을 얹은 지도 (JejuOverworldPicker).
 * 「고르는 화면은 픽셀」 — 실사 지도가 아니라 픽셀 그림이다.
 * 표식은 평소 흰 바탕, **고른 것만 그 권역의 색**이다. 「전역」도 같은 규칙.
 */
export function JejuOverworldPicker({ selected, onSelect }: { selected: string; onSelect: (region: string) => void }) {
  return (
    <div className="cd-overworld px-border-heavy">
      <img
        src={images.jejuOverworld}
        alt=""
        aria-hidden="true"
        className="cd-overworld__image px-pixelated"
        draggable={false}
      />
      {REGION_SPOTS.map((spot) => {
        const on = selected === spot.id;
        const c = regionColors(spot.id);
        return (
          <div key={spot.id} className="cd-spot" style={{ left: `${spot.x * 100}%`, top: `${spot.y * 100}%` }}>
            <PixelBob delay={spot.bobDelay} style={{ display: 'block', width: '100%' }}>
              <button
                type="button"
                className="px-reset-button cd-spot__button px-border px-shadow-small"
                style={{ background: on ? c.fill : PixelColor.surface }}
                aria-label={`${spot.label} ${spot.sublabel}`}
                aria-pressed={on}
                onClick={() => onSelect(spot.id)}
              >
                <span className="cd-spot__label" style={{ color: on ? c.on : PixelColor.ink }}>
                  {spot.label}
                </span>
                <span className="cd-spot__sublabel" style={{ color: on ? c.on : PixelColor.inkWeak }}>
                  {spot.sublabel}
                </span>
              </button>
            </PixelBob>
          </div>
        );
      })}
    </div>
  );
}

// ═══════════════════════════════ 코스 카드 ═══════════════════════════════

/**
 * 코스 한 장. 추천 결과 목록(순위 있음)과 코스 탭 첫 화면의
 * 「이런 코스는 어때요?」(순위 없음)가 같이 쓴다.
 */
export function CourseCard({
  course,
  rank,
  onTap,
}: {
  course: CourseListItem;
  /** 추천 결과에서의 순위. 둘러보기는 순위가 없다 — 무작위 코스에 1·2·3 을 붙이면 거짓말이 된다. */
  rank?: number;
  onTap: () => void;
}) {
  const region = courseListItemRegion(course);

  // 코스에서 보여줄 대표 장소 최대 3개 (day 1 우선)
  const day1 = course.places.filter((p) => p.day === 1);
  const pool = day1.length === 0 ? course.places : day1;
  const previewPlaceNames = pool.slice(0, 3).map((p) => p.name);

  return (
    <button type="button" className="px-reset-button cd-card px-border px-shadow-card" onClick={onTap}>
      <CourseCover thumbnail={course.thumbnail} region={region} />

      {/* 헤더: 순위(또는 권역) + 제목 */}
      <span className="cd-card__head">
        <LeadingBadge rank={rank} region={region} />
        <span className="cd-card__titles">
          {/* 제목에서 「서부 2일 · 」 접두사를 뗀다 — 권역은 배지가, 일수는 아래 줄이 이미 말한다 */}
          <span className="cd-card__title" style={PixelFont.label}>
            {course.title.length === 0 ? '이름 없는 코스' : courseListItemHeadline(course)}
          </span>
          {/* 곳수는 제목의 「외 N곳」이 이미 말한다. 여기서 또 세지 않는다. */}
          <span className="cd-card__days" style={PixelFont.labelSmall}>
            <Icon name="calendar" size={14} />
            {course.durationDays}일 일정
          </span>
        </span>
        <Icon name="forward" size={16} className="cd-card__chevron" />
      </span>

      {/* 대표 장소 칩 */}
      {previewPlaceNames.length > 0 && (
        <span className="cd-card__chips">
          {previewPlaceNames.map((name, i) => (
            <span key={`${i}-${name}`} className="cd-card__chip px-border" style={PixelFont.labelSmall}>
              {name}
            </span>
          ))}
          {course.places.length > previewPlaceNames.length && (
            <span className="cd-card__more" style={PixelFont.labelSmall}>
              +{course.places.length - previewPlaceNames.length}
            </span>
          )}
        </span>
      )}
    </button>
  );
}

/**
 * 카드 맨 위 사진 — **제목에 뜨는 그 장소**의 KTO 대표사진(서버가 고른다).
 * 사진이 없으면 권역색 판 위에 오름 풍경(PixelPlaceholderScene)을 깐다.
 * 「전체」는 권역색이 잉크라 판으로 깔면 검은 덩어리가 된다 — 가라앉은 면 색을 쓴다.
 * 추천 목록으로 넘어오기 전에 받아 둔 사진은 브라우저 캐시에서 곧바로 그려진다.
 */
function CourseCover({ thumbnail, region }: { thumbnail: string | null; region: string }) {
  const [failed, setFailed] = useState(false);
  const fill = region === WHOLE_ISLAND_ID ? PixelColor.surfaceVariant : regionColors(region).fill;
  useEffect(() => setFailed(false), [thumbnail]);

  return (
    <span className="cd-card__cover px-border" style={{ background: fill }} aria-hidden="true">
      {thumbnail && !failed ? (
        <img
          src={thumbnail}
          alt=""
          className="cd-card__cover-img"
          draggable={false}
          referrerPolicy="no-referrer"
          onError={() => setFailed(true)}
        />
      ) : (
        <PixelPlaceholderScene />
      )}
    </span>
  );
}

/**
 * 카드 왼쪽 배지. 화면에 따라 뜻이 다르다.
 *   추천 결과 목록   1·2·3   순위 — 파랑 (결과는 파랑, 실행만 초록)
 *   둘러보기 목록    서부    권역 — 권역색
 * 순위든 권역이든 **같은 높이**(28)다.
 */
function LeadingBadge({ rank, region }: { rank?: number; region: string }) {
  let text: string;
  let fill: string;
  let fillOpacity = 1;
  let on: string;
  if (rank !== undefined) {
    text = String(rank);
    fill = PixelColor.secondary;
    fillOpacity = rank === 1 ? 1 : rank === 2 ? 0.75 : 0.55;
    on = rank === 1 ? PixelColor.onSecondary : PixelColor.ink;
  } else {
    const c = regionColors(region);
    text = region;
    fill = c.fill;
    on = c.on;
  }
  const fillStyle: CSSProperties = { background: fill, opacity: fillOpacity };
  return (
    <span className="cd-card__badge" style={{ color: on }}>
      <span className="cd-card__badge-fill" style={fillStyle} aria-hidden="true" />
      <span className="cd-card__badge-text">{text}</span>
    </span>
  );
}

