# Stitch 프롬프트 — 지도 흐름

**쓰는 법:** 아래 **① 제약 블록**을 먼저 붙여넣고, 바로 이어서 **화면 하나**의 프롬프트를 붙인다.
화면마다 새 요청으로 나눈다 — 한 번에 여러 화면을 넣으면 흐려진다.

프롬프트를 **영어로 쓴 이유:** Stitch가 영어 지시를 더 정확히 따른다. 대신 **화면에 들어갈 글자는
한국어로 못 박아** 뒀다. 영문 폰트로 만들어 놓고 나중에 한글을 넣으면 디자인이 무너지기 때문이다
(2026-08-20에 실제로 겪음 — Space Grotesk는 한글을 지원하지 않는다).

---

## ① 제약 블록 (매번 앞에 붙인다)

```
DESIGN CONSTRAINTS — follow these exactly. Do not substitute your own choices.

PRODUCT
A location-based audio-guide app for Jeju Island, South Korea. Pixel-art game
aesthetic. Users walk to real places and listen to narration about what is
physically in front of them.

LANGUAGE
All visible text must be KOREAN. Do not write any UI label in English.
Use a Korean-capable font. Do NOT use Space Grotesk, Inter, or Work Sans —
they have no Korean glyphs. Assume a Korean pixel font (Galmuri) for UI chrome
and a Korean system sans for long body text.

COLOR — use only these. No gradients. No other colors.
  background  #F4EFE4   (light sand)
  surface     #FFFFFF
  ink         #1E1B18   (text + all borders)
  ink-weak    #6B635A   (secondary text)
  primary     #1E6F6B   (teal — primary action, "has audio" state)
  accent      #F2B233   (yellow — highlight, free badge)
  locked      #C9503C
  done        #4E8C3F
Dark mode equivalents:
  #14181A / #1E2427 / #EDE7DC / #9A9187 / #4FB3AD / #FFC759 / #E0705A / #6FAE5E
On accent/locked/done fills, text must be dark #1E1B18 — never light.

SHAPE
  border-radius: 0 everywhere. No exceptions. No rounded cards, no pills,
  no circular avatars.
  Borders: solid ink. 2px on buttons/badges/inputs, 3px on cards/sheets.
  Shadow: hard offset only — x+3 y+3, blur 0, color ink. Never a soft blur.
  Pressed state: shadow disappears, element shifts +3px down-right.
  All spacing is a multiple of 4 (4/8/12/16/24/32/48). Button height 48.

ICONS
  Draw icons as chunky pixel/dot shapes. Do NOT use Material Symbols,
  SF Symbols, Font Awesome, or any icon font.

PHOTOS
  Place thumbnails are REAL PHOTOGRAPHS, shown unfiltered inside a 3px pixel
  border frame. Never apply a pixel/8-bit filter to photos, and never replace
  a photo with AI-generated pixel-art scenery. The photo is how the user
  recognizes the real place.

DO NOT INVENT THESE — the product does not have them
  XP, levels, player stats, inventory, item collection grids, star ratings,
  review counts, "live purchase" tickers, leaderboards, streaks, currency.
  This is not an RPG dashboard. If a section feels empty, leave it empty.

BOTTOM TAB BAR — exactly 4 tabs, Korean labels, pixel icons
  홈 · 탐험 · 지도 · 내 것
```

---

## ② 화면 1 — 지도 (기본 상태)

```
SCREEN: Map tab, default state. Mobile portrait.

A full-bleed map of Jeju Island fills the screen behind the UI. The map itself
is a plain, low-contrast base map (not pixel art) so the pins read clearly.

189 place pins are scattered across the island, dense along the coast and
sparse inland. Pins come in TWO kinds and the difference must be obvious at a
glance without reading anything:

  HAS AUDIO (about 189 places) — larger pin, filled primary teal #1E6F6B,
    3px ink border, hard offset shadow. Add a small pixel headphone mark so it
    is distinguishable without relying on color alone.
  NO AUDIO — small, quiet dot in ink-weak #6B635A, no border, no shadow.

The user's own location is a separate marker, clearly not a place pin.

Overlay elements:
  - Top: a compact search field (placeholder: "장소 검색") and a filter chip
    row with 4 region chips: "제주시" "서귀포" "동부" "서부".
  - One more chip, toggled ON by default: "들을 수 있는 곳만"
  - Bottom: the 4-tab bar, 지도 selected.

No bottom sheet, no card. Nothing is selected yet.
Keep the map readable — chrome must not cover the island.
```

---

## ③ 화면 2 — 핀을 눌렀을 때 (미니 카드)

```
SCREEN: Map tab, one pin selected. Mobile portrait.

Same map. The map has zoomed in toward the selected pin, which is now
enlarged and visibly active (thicker border, larger hard shadow). Other pins
are dimmed but still visible.

A compact card slides up from the bottom, above the tab bar. It covers only
the lower third — the user must still see the map and the pin. The card:

  - 3px ink border, 0 radius, hard offset shadow, surface background.
  - Left: a REAL PHOTOGRAPH thumbnail of the place, square, inside a 3px
    pixel border frame. Not pixel-art. Not filtered.
  - Right of the photo, stacked:
      Place name, large:            "성산일출봉"
      One quiet line beneath:       "제주 서귀포시 성산읍"
      A small badge row:            "🎧 해설 3분 7초"  (pixel headphone, not an emoji font)
  - Full-width primary button at the bottom of the card:  "자세히 보기"
  - A small close affordance (pixel X) in the card's top-right.

IMPORTANT: tapping the pin must NOT navigate away. This card is a preview
step. Only the "자세히 보기" button leads to the place screen.

Produce a second variant of this card for a place with NO audio: the badge row
instead reads "해설 준비 중" in ink-weak, and the button reads "장소 정보".
```

---

## ④ 화면 3 — 장소 화면 (미니 카드에서 넘어간 뒤)

```
SCREEN: Place detail, arrived from the map card. Mobile portrait. Scrollable.

Top: a real photograph of the place, full width, inside a pixel border frame.
Beneath it, in this order:

  1. Place name (large) + address line (ink-weak).
  2. AUDIO PLAYER — the most prominent block on the screen:
       One large play button (pixel triangle), 48px tall, primary fill.
       A segmented progress bar — discrete blocks, not a smooth track.
       Time readout "0:00 / 3:07" in tabular numerals.
       Two small secondary buttons: "참고사진"  "대본 보기"
  3. SUBTITLE AREA — the narration text appears here as it is spoken,
     like a caption. Show it mid-sentence with a blinking cursor to convey
     that it types along with the voice. Use a readable Korean system sans
     here, NOT the pixel font — this paragraph is long-form reading.
     Sample text: "약 5천년 전, 지하에 있던 마그마가 물과 만나 격렬하게 터지면서"
  4. Collapsed info rows (pixel chevrons): "운영시간"  "입장료"  "주차"  "전화"
  5. A quiet attribution line at the very bottom: "출처: ⓒ한국관광공사"

The audio player and the subtitle are the point of this screen. Everything
else is secondary and visually quieter.
```

---

## 참고 — 실제 데이터

프롬프트에 쓴 값은 실제 우리 데이터다. Stitch가 그럴듯한 가짜를 만드는 대신 진짜를 쓰게 한다.

| 장소 | 해설 길이 |
|---|---|
| 성산일출봉 | 3분 7초 |
| 우도 | 3분 36초 |
| 섭지코지 | 2분 32초 |
| 천지연폭포 | 2분 56초 |
| 카멜리아힐 | 1분 34초 |

대본 보유 **189곳** · 전체 224곳 (대본 없는 35곳은 지도에 표시하지 않는다).

## 받은 결과를 저한테 줄 때

**스크린샷이 가장 좋습니다.** HTML도 주시면 여백·위계 수치를 읽는 데 씁니다.
다만 Stitch의 HTML은 웹이고 우리 앱은 SwiftUI라 **코드를 그대로 쓰지는 못합니다** — 설계도로 봅니다.
