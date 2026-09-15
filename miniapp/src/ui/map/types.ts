/**
 * 공용 지도 부품의 **계약**. 구현(`MapView.tsx`)을 갈아 끼워도 이 모양은 그대로 둔다.
 *
 * iOS 는 지도 네 곳이 서로 다른 부품을 썼다. 웹은 전부 MapView 하나로 그린다.
 *
 *   지도 탭        PlayPinMap (Google)        픽셀 핀(활성/준비 중/선택) · 핀 클릭 · 권역 맞추기
 *   코스 상세      MapWithPolyline (MapKit)   번호 사각형 · 점선 경로 · 그날 장소에 맞추기(최소 800m)
 *   PLAY 경로      PlayRouteMap (MapKit)      번호 사각형 + 지점 이름(caption) · **선 없음** (검증된 보행 경로가 없다)
 *   장소 상세      GoogleMapPreview           장소 핀(kind 'place') 하나 · 줌 15 · 손으로 못 움직임
 */
import type { CSSProperties } from 'react';
import type { LatLng, LatLngBounds } from '../../lib/region';

export type { LatLng, LatLngBounds };

export type MapMarker =
  | {
      id: string;
      position: LatLng;
      /** 아래로 뾰족한 8×8 도트 핀 (지도 탭). 활성 = 초록 채움 + 가운데 점, 준비 중 = 속이 빈 핀. */
      kind: 'pin';
      status: 'active' | 'preparing';
      /** 선택되면 금색으로 칠하고 한 칸 커진다. */
      selected?: boolean;
      title?: string;
    }
  | {
      id: string;
      position: LatLng;
      /** 번호 사각형 (주색 채움 · 흰 글자 · 2px 잉크 테두리). 좌표가 사각형 한가운데. */
      kind: 'number';
      label: string;
      /** 한 변 px. 코스 28 (기본) · PLAY 경로 26 */
      size?: number;
      /** 글자 — 코스는 labelSmall(12, 기본), PLAY 경로는 label(14) */
      font?: 'label' | 'labelSmall';
      /**
       * 번호 사각형 **아래에 보이는** 이름 (MapKit `Annotation(title, coordinate:)` 의 제목 자리).
       * PLAY 경로 지도가 Point 이름을 붙인다. 비우면 번호만 보인다.
       */
      caption?: string;
      title?: string;
    }
  | {
      id: string;
      position: LatLng;
      /**
       * 장소 하나를 가리키는 **단순 핀** (장소 상세 미리보기 — GoogleMapPreview 의
       * `GMSMarker.markerImage(with: PixelColor.primary)`). 픽셀 핀과 달리 「플레이 가능」 무늬가 없다.
       */
      kind: 'place';
      title?: string;
    };

/** 사용자가 옮겨 둔 지도 위치 (onCameraChange). 되돌릴 때 `{ kind: 'center', ...view }` 로 넘긴다. */
export interface MapViewState {
  center: LatLng;
  zoom: number;
}

export interface MapPolyline {
  id: string;
  path: LatLng[];
  /** CSS 색. 기본 주색(초록). */
  color?: string;
  /** 선 두께 px. 기본 3.5 */
  width?: number;
  /** SVG dasharray. 코스 경로는 '8 5' */
  dashArray?: string;
  /** 기본 0.85 */
  opacity?: number;
}

export type MapCamera =
  | { kind: 'center'; center: LatLng; zoom: number }
  | {
      kind: 'bounds';
      bounds: LatLngBounds;
      /** 가장자리 여백 px. 숫자 하나 또는 { top, right, bottom, left } */
      padding?: number | { top: number; right: number; bottom: number; left: number };
      /** 사각형이 이보다 좁으면 가운데를 두고 넓힌다 (m). 점 하나일 때 최대 확대로 붙지 않게. */
      minSpanMeters?: number;
      /** 이보다 더 확대하지 않는다 */
      maxZoom?: number;
    };

export interface MapViewProps {
  markers?: MapMarker[];
  polylines?: MapPolyline[];
  /** 처음 보여줄 곳. */
  camera: MapCamera;
  /**
   * 카메라를 **다시 맞출 신호**. 이 값이 바뀔 때만 `camera` 를 다시 적용한다 —
   * 매번 적용하면 사용자가 손으로 옮긴 지도가 튕겨 돌아간다(Swift 도 그렇게 막았다).
   * 예: 지도 탭은 권역 칩 id, 코스 상세는 선택한 Day.
   * 비우면 처음 한 번만 적용한다.
   */
  cameraKey?: string;
  /** 카메라를 옮길 때 움직임을 줄지 (지도 탭 권역 전환 = true). 기본 false */
  animateCamera?: boolean;
  /** 사용자 현재 위치 (파란 점). null/undefined 면 안 그린다. ⚠️ 이 좌표를 서버로 보내지 말 것. */
  userLocation?: LatLng | null;
  /** false 면 끌기·확대가 꺼진 미리보기 (장소 상세). 기본 true */
  interactive?: boolean;
  onMarkerClick?: (id: string) => void;
  /** 핀이 아닌 바탕을 눌렀을 때 (지도 탭: 선택 해제) */
  onMapClick?: () => void;
  /**
   * 지도가 멈출 때마다(끌기·확대·카메라 맞추기가 끝난 뒤) 지금 위치를 알려 준다.
   * 화면이 다시 마운트돼도 보던 자리로 돌아오게 할 때 쓴다 (지도 탭 — iOS 는 탭 화면을 살려 둔다).
   */
  onCameraChange?: (view: MapViewState) => void;
  /** 높이. 부모가 정하면 비워도 된다(기본 100%). */
  height?: number | string;
  className?: string;
  style?: CSSProperties;
  /** 스크린리더용 이름 */
  ariaLabel?: string;
}
