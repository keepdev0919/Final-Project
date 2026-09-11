# 한국관광공사(KTO) API 레퍼런스

> 실제 호출 테스트 기준: 2026-04-08  
> Base URL: `https://apis.data.go.kr/B551011`  
> 공통 파라미터: `serviceKey`, `MobileOS=ETC`, `MobileApp=JejuFolklore`, `_type=json`  
> 제주도 지역코드: `areaCode=39`

---

## 1. 지역 관광지 목록 조회

**엔드포인트:** `GET /KorService2/areaBasedList2`

**한 줄 설명:** "제주도에 있는 관광지 목록을 페이지 단위로 가져온다"

**주요 파라미터:**

| 파라미터 | 값 예시 | 설명 |
|---------|--------|------|
| `areaCode` | `39` | 지역코드 (39 = 제주도) |
| `contentTypeId` | `12` | 콘텐츠 유형 (12=관광지, 39=식당, 32=숙박) |
| `numOfRows` | `10` | 한 번에 가져올 개수 |
| `pageNo` | `1` | 페이지 번호 |
| `arrange` | `A` | 정렬 (A=제목순, C=수정일순, D=생성일순) |

**응답에서 쓸 수 있는 필드:**

| 필드 | 예시 값 | 설명 |
|------|--------|------|
| `contentid` | `"1884191"` | 관광지 고유 ID (다른 API 호출 시 필요) |
| `title` | `"가마오름"` | 관광지 이름 |
| `addr1` | `"제주특별자치도 제주시 한경면 청수리"` | 주소 |
| `mapx` | `126.2466` | 경도 |
| `mapy` | `33.3057` | 위도 |
| `firstimage` | `"http://tong.visitkorea..."` | 대표 사진 URL |

**주의사항:**
- `contentid`는 다른 API(상세정보, 사진 등)를 호출할 때 키처럼 쓰임
- 우리 `data/places.json`에는 `contentid`가 없어서 Place ↔ KTO 연결은 좌표·이름 검색으로 한다 (`backend/routers/place.py`)

---

## 2. 관광지 상세정보 조회

**엔드포인트:** `GET /KorService2/detailCommon2`

**한 줄 설명:** "contentId 하나로 그 관광지의 상세 설명, 주소, 사진, 홈페이지를 가져온다"

**주요 파라미터:**

| 파라미터 | 값 예시 | 설명 |
|---------|--------|------|
| `contentId` | `"1884191"` | 관광지 고유 ID (필수) |

> ⚠️ `defaultYN=Y`, `addrinfoYN=Y` 같은 Y/N 파라미터 넣으면 오류 남. `contentId`만 넣을 것.

**응답에서 쓸 수 있는 필드:**

| 필드 | 예시 값 | 설명 |
|------|--------|------|
| `title` | `"가마오름"` | 관광지 이름 |
| `overview` | `"가마오름은 제주시..."` | 관광지 소개글 (수백 자 한국어) |
| `addr1` | `"제주시 한경면..."` | 주소 |
| `mapx` / `mapy` | `126.24 / 33.30` | 좌표 |
| `firstimage` | `"http://tong..."` | 대표 사진 |
| `homepage` | `"<a href=...>"` | 홈페이지 (HTML 형태로 옴) |
| `tel` | `"064-xxx-xxxx"` | 전화번호 |

**에이전트 활용:** 코스 장소의 설명글이 필요할 때 호출. `overview` 필드가 핵심.

---

## 3. GPS 기반 주변 관광지 조회 ⭐ (가장 유용)

**엔드포인트:** `GET /KorService2/locationBasedList2`

**한 줄 설명:** "위도·경도와 반경을 주면 그 근처 관광지를 거리순으로 가져온다"

**주요 파라미터:**

| 파라미터 | 값 예시 | 설명 |
|---------|--------|------|
| `mapX` | `126.5292` | 기준점 경도 |
| `mapY` | `33.3617` | 기준점 위도 |
| `radius` | `3000` | 반경 (미터 단위) |
| `contentTypeId` | `12` | 유형 필터 (생략 시 전체) |

**응답에서 쓸 수 있는 필드:**

| 필드 | 예시 값 | 설명 |
|------|--------|------|
| `title` | `"성산일출봉"` | 관광지 이름 |
| `dist` | `"827.22"` | 기준점으로부터 거리 (미터) |
| `mapx` / `mapy` | 좌표 | 위치 |
| `contentid` | `"126508"` | 고유 ID |

**활용:** PLAY 장소 GPS → 반경 N km → 주변 관광지 목록. 현재 `enrich_with_visitjeju`가 하는 역할을 이 API로 대체 가능.

---

## 4. 연관 관광지 정보

**엔드포인트:** `GET /TarRlteTarService1/areaBasedList1`

**한 줄 설명:** "지역·연월 기준으로 함께 많이 방문되는 연관 관광지 쌍을 가져온다"

**주요 파라미터:**

| 파라미터 | 값 예시 | 설명 |
|---------|--------|------|
| `areaCd` | `39` | 지역코드 |
| `signguCd` | `1` | 시군구 코드 (필수, 빈값 불가) |
| `baseYm` | `202503` | 기준 연월 (YYYYMM) |

> ⚠️ `signguCd` 필수값. 빈값 넣으면 오류. 숫자값 필요.  
> ⚠️ 실제 테스트 결과 제주도 데이터가 아직 적재 안 된 상태 (totalCount: 0). 현재 사용 불가.

**현재 상태:** 데이터 없음. 나중에 재시도 필요.

---

## 5. 관광지 집중률 예측

**엔드포인트:** `GET /TatsCntrRateService/tatsCntrRateList`

**한 줄 설명:** "날짜·지역별로 관광 혼잡도를 예측해서 가져온다"

**주요 파라미터:**

| 파라미터 | 값 예시 | 설명 |
|---------|--------|------|
| `areaCd` | `39` | 지역코드 |
| `signguCd` | `1` | 시군구 코드 |
| `baseYmd` | `20260401` | 기준 날짜 (YYYYMMDD) |

> ⚠️ 현재 서버 측 HTTP 500 오류. 서비스 자체 운영 중단 또는 별도 승인 필요한 상태로 추정. 사용 불가.

---

## 6. 관광사진 조회

**엔드포인트:** `GET /KorService2/detailImage2`

**한 줄 설명:** "contentId로 해당 관광지의 사진 여러 장을 가져온다"

**주요 파라미터:**

| 파라미터 | 값 예시 | 설명 |
|---------|--------|------|
| `contentId` | `"1884191"` | 관광지 고유 ID (필수) |
| `imageYN` | `Y` | 이미지 포함 여부 |
| `numOfRows` | `5` | 가져올 사진 수 |

> ⚠️ `subImageYN=Y` 파라미터 넣으면 오류. `imageYN=Y`만 사용.

**응답에서 쓸 수 있는 필드:**

| 필드 | 예시 값 | 설명 |
|------|--------|------|
| `originimgurl` | `"http://tong.visitkorea..."` | 원본 사진 URL |
| `smallimageurl` | `"http://tong.visitkorea..."` | 썸네일 URL |
| `imgname` | `"가마오름_e (2)"` | 사진 설명 |
| `cpyrhtDivCd` | `"Type3"` | 저작권 유형 |

**에이전트 활용:** 코스 결과 화면에서 장소 사진 보여줄 때.

---

## 7. 오디오 가이드 (오디 Odii) — ✅ 정상 동작 (2026-08-14 정정)

> **⚠️ 이전 기록("모든 파라미터 조합에서 500, 사용 불가")은 틀렸다.**
> **엔드포인트를 잘못 짚었다.** `GuideService`가 아니라 **`Odii`** 다.
> 활용매뉴얼 13번 문서에서 확인하고 실호출로 검증했다.

**서비스 URL:** `http://apis.data.go.kr/B551011/Odii/`

**⚠️ `langCode`가 필수다.** 빠뜨리면 `resultCode 11 NO_MANDATORY_REQUEST_PARAMETERS_ERROR1(langCode)`.

| 오퍼레이션 | 설명 |
|---|---|
| `themeBasedList` | 관광지 기본 정보 목록 |
| `themeLocationBasedList` | 관광지 위치기반 목록 |
| `themeSearchList` | 관광지 키워드 검색 |
| `storyBasedList` | 이야기 기본 정보 목록 |
| **`storyLocationBasedList`** | **이야기 위치기반 목록** ← GPS 도착 시 사용 |
| `storySearchList` | 이야기 키워드 검색 |
| `themeBasedSyncList` · `storyBasedSyncList` | 동기화용 |

**응답 필드:** `tid, tlid, stid, stlid, title, audioTitle, script, audioUrl, imageUrl, mapX, mapY, playTime, langCode, createdtime, modifiedtime`

**실측 데이터 규모 (2026-08-14)**

| 범위 | 한국어 | 영어 |
|---|---|---|
| 전국 (`storyBasedList`) | 6,538건 | 4,538건 |
| 제주 반경 20km | 149건 | 130건 |
| 성산일출봉 반경 3km | **2건** | — |

**⚠️ 알아둘 것 세 가지**

1. **장소당 이야기 1개다.** 성산 반경 3km에 2건뿐이고(일반 해설 + 초등 교과연계), 지점별로 쪼개져 있지 않다. "성산 안의 관찰 지점 5개"는 여전히 우리가 나눠야 한다.
2. **`audioUrl`이 비어 있는 건이 있다.** 대본(`script`)은 있지만 음성 파일이 없는 경우가 섞여 있다. TTS로 대체하면 "오디 음성을 트는 것"이 아니라 "오디 대본을 우리가 읽는 것"이 되므로 저작권 판단이 달라진다.
3. **공지의 "관광지오디오 69,585건"과 다르다.** 그 숫자는 다국어·테마 포함 합계로 보인다. 한국어 이야기 실측은 6,538건.

**응답 형태가 두 가지다.** 같은 오퍼레이션이 `{"response":{"body":{"items":{"item":[...]}}}}` 로도, `{"items":[...], "totalCount":N}` 로도 온다. 파싱할 때 둘 다 처리해야 한다.

**호출 예시**
```
http://apis.data.go.kr/B551011/Odii/storyLocationBasedList
  ?serviceKey=<KEY>&MobileOS=IOS&MobileApp=<앱명>&_type=json
  &langCode=ko&mapX=126.9415&mapY=33.4581&radius=3000&numOfRows=20&pageNo=1
```

---

## 현재 사용 가능 여부 요약

| API | 사용 가능 | 에이전트 활용도 |
|-----|---------|--------------|
| 지역 관광지 목록 (areaBasedList2) | ✅ | 중간 — contentId 수집용 |
| 관광지 상세정보 (detailCommon2) | ✅ | 높음 — overview(설명글) |
| **GPS 기반 주변 조회 (locationBasedList2)** | ✅ | **매우 높음** — PLAY 장소 근처 탐색 |
| 연관 관광지 (TarRlteTarService1) | ❌ 데이터 없음 | — |
| 집중률 예측 (TatsCntrRateService) | ❌ 500 오류 | — |
| 관광사진 (detailImage2) | ✅ | 중간 — 코스 화면 사진 |
| **오디오 가이드 (Odii)** | ✅ | **매우 높음** — 대본·좌표·영어까지 |

**핵심 결론 (2026-08-14 갱신):** `locationBasedList2` + **`Odii/storyLocationBasedList`** 둘 다 쓸 수 있다.  
PLAY 장소 GPS → 반경 지정 → 주변 관광지 목록. 현재 course_places DB 조회를 이걸로 보완 가능.
