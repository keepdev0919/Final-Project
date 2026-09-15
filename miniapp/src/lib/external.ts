/**
 * 외부 링크 열기 — 앱인토스 SDK `Device.openURL` (docs: /documentation/common/screen/open-url).
 *
 * 기기의 기본 브라우저나 연결된 앱에서 연다. **미니앱 안에서 iframe·리다이렉트로 띄우지 않는다.**
 *
 * ⚠️ 앱인토스 서비스 오픈 정책 2-2: 외부 링크는 허용된 경우에만 쓴다.
 *    허용 — 법률상 고지(개인정보 처리방침), 단순 정보 확인용 타사 사이트(지도 길찾기) 등.
 *    금지 — 주요 기능·흐름이 외부 링크에 의존하는 구조, 앱 설치 유도.
 */
import { Device } from '@apps-in-toss/web-framework';

/** URL 을 밖에서 연다. SDK 가 없는 환경(일반 브라우저)이면 새 창으로. 실패해도 예외를 던지지 않는다. */
export async function openExternalURL(url: string): Promise<void> {
  try {
    await Device.openURL(url);
  } catch {
    try {
      window.open(url, '_blank', 'noopener,noreferrer');
    } catch {
      /* 열 수 없는 환경 — 조용히 넘어간다 */
    }
  }
}

/**
 * 구글 지도 길찾기 웹 주소 (PlaceDetailView.openInMaps 의 2순위 경로).
 * iOS 는 구글맵 앱(comgooglemaps://)을 먼저 시도하지만 웹에서는 설치 여부를 알 수 없어 웹 주소만 쓴다.
 * 관광지 자체는 차(driving), 주변 시설은 걸어서(walking).
 */
export function googleMapsDirectionsURL(lat: number, lng: number, mode: 'driving' | 'walking'): string {
  return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=${mode}`;
}
