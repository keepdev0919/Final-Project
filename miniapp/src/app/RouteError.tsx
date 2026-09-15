/**
 * 라우트에서 예외가 났을 때 — 막다른 화면이 되지 않게 「처음으로」를 둔다.
 *
 * 「처음으로」는 라우터 이동이다(`window.location` 을 건드리지 않는다). 페이지를 통째로 다시 불러오면
 * 저장소를 다시 올리는 동안 흰 화면이 되고, 출시 가이드가 금지 예시로 드는 패턴과도 같다.
 * 위치가 바뀌면 라우터의 오류 경계가 풀려 홈이 다시 그려진다.
 */
import { useRouteError } from 'react-router';
import { useAppNavigation } from './routes';
import { Icon } from '../ui/Icon';
import { PixelButton } from '../ui/PixelComponents';
import { PixelColor, PixelFont } from '../ui/tokens';

export function RouteError() {
  const error = useRouteError();
  const nav = useAppNavigation();
  console.error(error);
  return (
    <div className="px-screen" style={{ alignItems: 'center', justifyContent: 'center', gap: 16, padding: 40 }}>
      <Icon name="warn" size={40} color={PixelColor.locked} />
      <p style={{ ...PixelFont.body, color: PixelColor.inkWeak, margin: 0, textAlign: 'center' }}>화면을 여는 중에 문제가 생겼어요.</p>
      <div style={{ width: '100%', maxWidth: 240 }}>
        <PixelButton title="처음으로" onClick={() => nav.toTab('home')} />
      </div>
    </div>
  );
}
