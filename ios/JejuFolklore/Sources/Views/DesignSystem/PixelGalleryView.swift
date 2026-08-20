import SwiftUI

/// 픽셀 부품을 한 화면에 모아 눈으로 확인하는 개발용 화면.
/// 시뮬레이터에서 `-showPixelGallery YES`로 켠다.
struct PixelGalleryView: View {
    /// KTO 관광사진 (섭지코지). 컨셉의 절반이 실사 사진이라 자리표시로는 인상이 안 나온다.
    private let photo = URL(string: "http://tong.visitkorea.or.kr/cms/resource/83/2513483_image2_1.jpg")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {

                // ── 히어로: 이중 테두리 + 스티커 배지 ──
                heroBox

                // ── 루트 카드 ──
                VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                    PixelSectionHeader(title: "루트 카드", icon: .map)
                    routeCard
                }

                // ── 지도 미니 카드 ──
                VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                    PixelSectionHeader(title: "지도 미니 카드", icon: .mapPin,
                                       accent: PixelColor.primary)
                    miniCard
                }

                // ── 막대 두 종류 ──
                VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                    PixelSectionHeader(title: "막대 두 종류", icon: .check)
                    VStack(alignment: .leading, spacing: PixelSpacing.s) {
                        Text("정도 — 막대 안에 숫자")
                            .font(PixelFont.labelSmall).foregroundStyle(PixelColor.inkWeak)
                        PixelMeter(value: 0.6, fill: PixelColor.primary, caption: "3 / 5곳 들음")
                        Text("셀 수 있는 것 — 이야기 5개 중 3개")
                            .font(PixelFont.labelSmall).foregroundStyle(PixelColor.inkWeak)
                        PixelProgressBar(total: 5, filled: 3)
                    }
                }

                // ── 버튼·배지 ──
                VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                    PixelSectionHeader(title: "버튼과 배지", icon: .play)
                    PixelButton(title: "루트 선택", style: .primary) {}
                    PixelButton(title: "미리 받아두기", style: .accent, leadingIcon: .download) {}
                    PixelButton(title: "장소 정보", style: .plain) {}
                    HStack(spacing: PixelSpacing.s) {
                        PixelBadge(text: "해설 3분", kind: .audio)
                        PixelBadge(text: "지금 여기예요", kind: .here)
                    }
                    HStack(spacing: PixelSpacing.s) {
                        PixelBadge(text: "들었어요", kind: .heard)
                        PixelBadge(text: "잠김", kind: .locked)
                    }
                }
            }
            .padding(.horizontal, PixelSpacing.screenMargin)
            .padding(.vertical, PixelSpacing.xxl)
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationTitle("부품")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 히어로 (이중 테두리 — 화면에서 하나만)

    private var heroBox: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            Text("성산일출봉")
                .font(PixelFont.screenTitle)
                .foregroundStyle(PixelColor.primary)
            Text("동트기 전 분화구를 오르며 듣는 이야기.")
                .font(PixelFont.bodyLarge)
                .foregroundStyle(PixelColor.inkWeak)
            HStack(spacing: PixelSpacing.s) {
                PixelChip(text: "제주 동부", fill: PixelColor.ink, label: PixelColor.background)
                PixelChip(text: "걷기", fill: PixelColor.surface)
                PixelChip(text: "2-3시간", icon: .play, fill: PixelColor.accent,
                          label: PixelColor.inkFixedDark)
            }
        }
        .padding(PixelSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelColor.surface)
        .pixelDoubleBorder()
        .pixelShadow(PixelSpacing.shadowStrong)
        .overlay(alignment: .topTrailing) {
            PixelStickerBadge(text: "인기")
                .offset(x: PixelSpacing.s, y: -PixelSpacing.m)
        }
    }

    // MARK: - 루트 카드

    private var routeCard: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.m) {
                photoFrame(height: 150)
                Text("해안 올레길")
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)
                Text("남부 해안을 따라 걷는 길. 현무암 절벽과 바닷바람.")
                    .font(PixelFont.body)
                    .foregroundStyle(PixelColor.inkWeak)

                HStack {
                    Text("난이도 보통").font(PixelFont.label).foregroundStyle(PixelColor.ink)
                    Spacer()
                    Text("하루 24km").font(PixelFont.label).foregroundStyle(PixelColor.inkWeak)
                }
                PixelMeter(value: 0.5, fill: PixelColor.accent, height: 20)

                HStack(spacing: PixelSpacing.xs) {
                    PixelIcon(.play, size: 16, color: PixelColor.inkWeak)
                    Text("해설 5곳 · 약 4시간")
                        .font(PixelFont.label).foregroundStyle(PixelColor.inkWeak)
                }
                PixelButton(title: "루트 선택", style: .primary) {}
            }
            .padding(PixelSpacing.cardPadding)
        }
    }

    // MARK: - 미니 카드

    private var miniCard: some View {
        PixelCard {
            HStack(spacing: PixelSpacing.m) {
                AsyncImage(url: photo) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { PixelColor.primary }
                }
                .frame(width: 76, height: 76)
                .clipped()
                .pixelBorder()

                VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                    Text("섭지코지").font(PixelFont.sectionTitle).foregroundStyle(PixelColor.ink)
                    Text("서귀포시 성산읍").font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                    PixelBadge(text: "해설 2분 32초", kind: .audio)
                }
                Spacer(minLength: 0)
            }
            .padding(PixelSpacing.cardPadding)
        }
    }

    // MARK: - 실사 사진 프레임

    @ViewBuilder
    private func photoFrame(height: CGFloat) -> some View {
        AsyncImage(url: photo) { phase in
            if case .success(let img) = phase { img.resizable().scaledToFill() }
            else { ZStack { PixelColor.primary
                            PixelIcon(.photo, size: 32, color: PixelColor.surface) } }
        }
        .frame(height: height)
        .clipped()
        .pixelBorder()
    }
}
