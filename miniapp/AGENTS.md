<!-- ait:design-guide v1 -->
앱인토스 미니앱 프로젝트다. 하드 규칙 위반은 `/ait:design`이 자동으로 고친다.

하드 규칙:
- 텍스트 11px 이하 금지, 본문은 15px 이상
- 모든 이모지는 Tossface로 렌더(폰트 스택 배선 또는 `.tf`)
- 한글은 `word-break: keep-all`
- 터치 타깃 44px 이상
- 하단 CTA는 safe area 34px
- 광고가 첫 화면 콘텐츠(ATF)를 가리지 않음
- 다크패턴(가짜 버튼·막다른 화면) 금지
- 꺾쇠·화살표는 텍스트 글리프 대신 SVG(currentColor)
- 상단 네비는 직접 그리지 않음(플랫폼 자동 배치)
- font-weight는 400~700만 사용

토큰 사용:
- 텍스트 색: `--color-text-strong/default/subtle/hint/disabled/inverse`
- 배경 색: `--color-bg`, `--color-bg-canvas`
- 상태 색: `--color-danger`/`--color-success`/`--color-warning`
- 브랜드 색: `--brand-primary`(중립 기본값, 바꿔도 됨)
- 타이포: `--font-size-*`/`--font-weight-*` 6단계(display~caption)
- 간격: `--space-1`~`--space-6`(4/8/12/16/24/32px)
- 오버레이: `--dim`(#000 대신)
- 인라인 style 객체에서도 `var()`가 그대로 동작한다

아이콘: React는 `src/components/icons.tsx` 6종.
아이콘: vanilla는 `src/assets/icons/*.svg` 6종.

전문(3층 전체 규칙): `docs/design-guide.md`.
판단이 애매하면 화면을 그리기 전에 먼저 읽는다.

다음 단계:
`/ait:design`   말로: "화면이 좀 구려 보여. 예쁘게 고쳐줘."
`/ait:design`   말로: "등록용 로고랑 스크린샷 만들어줘"
<!-- /ait:design-guide -->

## 프로젝트 구조

놀멍봅서 iOS 앱(`../ios/JejuFolklore/Sources`)을 옮긴 앱인토스 미니앱이다. **기능·문구·흐름·색·크기는 Swift 가 정본**이다.
위 하드 규칙과 Swift 값이 부딪히면 하드 규칙을 따른다.

| 폴더 | 역할 | 원본 Swift |
|---|---|---|
| `src/app/` | 라우터·앱 셸(탭바·토스 뒤로가기)·**라우트 계약 `routes.ts`** | `ContentView.swift` |
| `src/screens/<화면>/index.tsx` | 화면 8개 (home · play-detail · play-runner · place-detail · course-discover · course-preview · map-tab · profile) | `Views/*View.swift` |
| `src/ui/` | 픽셀 디자인 시스템 부품·토큰(`tokens.ts`)·아이콘(`Icon`, Material Icons 윤곽 SVG)·이미지(`images.ts`) | `Views/DesignSystem/*` |
| `src/ui/map/` | 공용 지도 `MapView` · PLAY 경로 지도 | `PlayPinMap` · `MapWithPolyline` · `PlayRouteMap` · `GoogleMapPreview` |
| `src/styles/pixel.css` | 픽셀 토큰(`--px-*`)·글꼴(갈무리11)·부품 CSS | `PixelColor`·`PixelFont`·`PixelSpacing` |
| `src/api/` | 서버 타입·fetch·파생값(정답 판정 등). 응답 키는 camelCase 로 바뀌어 온다 | `Models/*` · `Services/*API.swift` |
| `src/stores/` | 기기 저장(앱인토스 Storage SDK): PLAY 진행·담은 코스·신고 대기열·설정 | `PlayProgressStore` · `SavedCourse` |
| `src/lib/` | 위치 훅·거리·외부 링크·권역·응답 캐시 | `LocationService` · `JejuRegion` |

- **지도는 임시 구현이다.** `src/ui/map/MapView.tsx` 가 Leaflet + OpenStreetMap 타일로 그린다. 앱인토스 웹 지도 허용 여부가 정해지면 이 파일 하나만 바꾼다(`types.ts` 계약 유지).
- 화면 이동은 `useAppNavigation()`(src/app/routes.ts)만 쓴다. URL 을 직접 조립하지 않는다.
- 뒤로가기 버튼을 화면에 그리지 않는다(Swift `pixelFloatingBack` 은 옮기지 않음) — 토스 네비게이션 바가 준다.
- 테스트: `npm test` (vitest — 저장·복원, 정답 판정, 키 변환).

### 서버 — 앱스토어용과 앱인토스용이 따로 떠 있다

| Railway 환경 | 주소 | 누가 부르나 |
|---|---|---|
| `production` | nolmeongbopseo-production.up.railway.app | 앱스토어 iOS 1.0 (2) — GitHub `main` 브랜치에서 자동 배포 |
| `apps-in-toss` | nolmeongbopseo-apps-in-toss.up.railway.app | 이 미니앱 (`src/api/config.ts`) |

- 둘 다 같은 `../backend/` 코드다. 출시본 iOS 코드는 git 태그 `ios-1.0-build2` 에 있다.
- 배포는 GitHub push 로 자동이다 (2026-09-15~): `miniapp` 브랜치 → apps-in-toss, `main` → production.
  서버 테스트(파이썬 3.12)가 통과해야 배포되고, 서버에 들어가는 파일이 바뀐 커밋만 배포된다.
  **서버 코드를 `main` 에 합치면 앱스토어 앱의 서버가 바뀐다.** `railway up` 은 쓰지 않는다.
