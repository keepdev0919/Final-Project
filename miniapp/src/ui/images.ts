/**
 * 번들 이미지. Swift 가 이름으로 부르던 에셋 → import 경로.
 *
 *   Swift                                  웹
 *   UIImage(named: "gamgyul")              images.gamgyul            (64×64 픽셀 감귤 「곱딱이」)
 *   Image("jeju-overworld")                images.jejuOverworld      (1500×1000 픽셀 제주 지도, 코스 탭)
 *   Image("placeholder-scene")             images.placeholderScene   (사진 없을 때 기본 그림)
 *   UIImage(named: play.placeKey)          coverFor(placeKey)        (Resources/Covers/<placeKey>.png)
 *
 * ⚠️ 셋 다 픽셀아트다 — `<img className="px-pixelated">` 로 그린다(보간 끄기).
 *    KTO 실사 사진(서버 URL)에는 px-pixelated 를 쓰지 않는다.
 */
import gamgyul from '../assets/images/gamgyul.png';
import jejuOverworld from '../assets/images/jeju-overworld.png';
import placeholderScene from '../assets/images/placeholder-scene.jpg';
import coverJejuStonePark from '../assets/images/covers/jeju-stone-park.png';
import coverSeongeupFolkVillage from '../assets/images/covers/seongeup-folk-village.png';
import coverSuwolbong from '../assets/images/covers/suwolbong.png';

export const images = {
  gamgyul,
  jejuOverworld,
  placeholderScene,
} as const;

/** 픽셀 커버. 키는 서버의 `place_key` 다. */
const COVERS: Record<string, string> = {
  'jeju-stone-park': coverJejuStonePark,
  'seongeup-folk-village': coverSeongeupFolkVillage,
  suwolbong: coverSuwolbong,
};

/**
 * 장소의 픽셀 커버. 번들에 없으면 null — 그때는 KTO 사진(thumbnail)으로,
 * 그것도 없으면 `PixelPlaceholderScene` 으로 떨어진다 (Swift QuestCoverImage 와 같은 순서).
 */
export function coverFor(placeKey: string | null | undefined): string | null {
  if (!placeKey) return null;
  return COVERS[placeKey] ?? null;
}
