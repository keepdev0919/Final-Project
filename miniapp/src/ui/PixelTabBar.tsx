/**
 * 시안 스타일 탭바 — PixelTabBar.swift 이식.
 *
 * 위 테두리 4px + 위쪽으로만 4px 그림자. 선택된 탭은 주색으로 채우고 2px 테두리·2px 그림자.
 * 하단 safe area(최소 34px)를 직접 더한다 — 없으면 선택 탭의 초록 상자가 홈 인디케이터
 * 자리까지 흘러내린다.
 *
 * 탭 목록·이동은 앱 셸(`src/app/AppShell.tsx`)이 정한다. 화면 담당은 이 부품을 직접 쓰지 않는다.
 */
import { Icon, type IconName } from './Icon';

export interface PixelTabItem<T extends string> {
  tab: T;
  title: string;
  icon: IconName;
}

export function PixelTabBar<T extends string>({
  items,
  selection,
  onSelect,
}: {
  items: PixelTabItem<T>[];
  selection: T | null;
  onSelect: (tab: T) => void;
}) {
  return (
    <nav className="px-tab-bar" role="tablist" aria-label="주요 메뉴">
      {items.map((item) => {
        const on = selection === item.tab;
        return (
          <button
            key={item.tab}
            type="button"
            role="tab"
            aria-selected={on}
            aria-label={item.title}
            className={`px-reset-button px-tab${on ? ' px-border px-shadow-small' : ''}`}
            onClick={() => onSelect(item.tab)}
          >
            <Icon name={item.icon} size={24} />
            <span className="px-t-label-small">{item.title}</span>
          </button>
        );
      })}
    </nav>
  );
}
