/**
 * 토스 뒤로가기(네비게이션 바 ← · 안드로이드 뒤로가기)를 화면이 가로채는 장치.
 *
 * 앱 셸이 `graniteEvent('backEvent')` 를 구독한다. 이벤트가 오면
 *   1) 가장 나중에 등록된 **켜진** 가로채기가 있으면 그것만 부른다 (시트 닫기·나가기 확인창 등)
 *   2) 없고 지금이 탭 뿌리 화면이면 미니앱을 닫는다 (`Screen.close()` — 출시 검수 항목)
 *   3) 아니면 앱 안 뒤로가기 (`useGoBack`)
 *
 * 쓰는 법 (러너의 「나가기」 확인창):
 *   const [askQuit, setAskQuit] = useState(false);
 *   useBackHandler(() => setAskQuit(true));          // 뒤로가기 → 확인창
 *   useBackHandler(askQuit ? () => setAskQuit(false) : null);  // 확인창이 떠 있으면 → 닫기
 *
 * ⚠️ 이건 **토스 뒤로가기 버튼**만 가로챈다. 개발용 브라우저의 뒤로가기(popstate)는 막지 못한다 —
 *    그것까지 막아야 하면 react-router 의 `useBlocker` 를 함께 쓴다.
 */
import { useEffect, useRef } from 'react';

type Entry = { id: number; run: () => void };
const stack: Entry[] = [];
let seq = 0;

/** 앱 셸이 부른다. 가로챈 화면이 있으면 true. */
export function runBackHandlers(): boolean {
  const top = stack[stack.length - 1];
  if (!top) return false;
  top.run();
  return true;
}

/** handler 가 null/false 면 등록하지 않는다. 화면이 사라지면 자동으로 빠진다. */
export function useBackHandler(handler: (() => void) | null | false | undefined): void {
  const ref = useRef(handler);
  useEffect(() => {
    ref.current = handler;
  });
  const active = !!handler;
  useEffect(() => {
    if (!active) return;
    const entry: Entry = { id: ++seq, run: () => ref.current && ref.current() };
    stack.push(entry);
    return () => {
      const i = stack.findIndex((e) => e.id === entry.id);
      if (i >= 0) stack.splice(i, 1);
    };
  }, [active]);
}
