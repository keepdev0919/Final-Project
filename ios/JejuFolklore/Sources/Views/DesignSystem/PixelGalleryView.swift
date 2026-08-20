import SwiftUI

/// 픽셀 부품을 한 화면에 모아 눈으로 확인하는 화면. 개발용이다.
///
/// 시뮬레이터에서 실행 인자로 켠다: `-showPixelGallery YES`
/// 사용자에게 보이는 경로에는 붙이지 않는다.
struct PixelGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelSpacing.xl) {

                section("루트 카드") {
                    PixelCard {
                        VStack(alignment: .leading, spacing: PixelSpacing.m) {
                            ZStack {
                                PixelColor.primary
                                PixelIcon(.mapPin, size: 40, color: PixelColor.surface)
                            }
                            .frame(height: 120)
                            .clipped()
                            .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThick)
                            .overlay(alignment: .topTrailing) {
                                PixelBadge(text: "인기", kind: .free)
                                    .padding(PixelSpacing.s)
                            }

                            Text("해안 올레길")
                                .pixelFont(PixelFont.cardTitle)
                                .foregroundStyle(PixelColor.ink)

                            Text("남부 해안을 따라 걷는 길. 현무암 절벽과 바닷바람.")
                                .font(PixelFont.longform(14))
                                .foregroundStyle(PixelColor.inkWeak)

                            VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                                HStack {
                                    Text("난이도 보통")
                                        .pixelFont(PixelFont.badge)
                                        .foregroundStyle(PixelColor.ink)
                                    Spacer()
                                    Text("하루 24km")
                                        .pixelFont(PixelFont.badge)
                                        .foregroundStyle(PixelColor.inkWeak)
                                }
                                PixelMeter(value: 0.5, fill: PixelColor.accent)
                            }

                            HStack(spacing: PixelSpacing.s) {
                                PixelIcon(.play, size: 16, color: PixelColor.inkWeak)
                                Text("해설 5곳 · 약 4시간")
                                    .pixelFont(PixelFont.badge)
                                    .foregroundStyle(PixelColor.inkWeak)
                            }

                            PixelButton(title: "루트 선택", style: .primary) {}
                        }
                        .padding(PixelSpacing.cardPadding)
                    }
                }

                section("지도 미니 카드 — 오디 있는 곳") {
                    PixelCard {
                        HStack(spacing: PixelSpacing.m) {
                            ZStack {
                                PixelColor.primary
                                PixelIcon(.photo, size: 28, color: PixelColor.surface)
                            }
                            .frame(width: 84, height: 84)
                            .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThick)

                            VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                                Text("성산일출봉")
                                    .pixelFont(PixelFont.cardTitle)
                                    .foregroundStyle(PixelColor.ink)
                                Text("서귀포시 성산읍")
                                    .pixelFont(PixelFont.badge)
                                    .foregroundStyle(PixelColor.inkWeak)
                                PixelBadge(text: "해설 3분 7초", kind: .audio)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(PixelSpacing.cardPadding)
                    }
                }

                section("두 종류의 막대") {
                    VStack(alignment: .leading, spacing: PixelSpacing.m) {
                        Text("셀 수 있는 것 — 이야기 5개 중 3개")
                            .pixelFont(PixelFont.badge).foregroundStyle(PixelColor.inkWeak)
                        PixelProgressBar(total: 5, filled: 3)
                        Text("정도 — 난이도")
                            .pixelFont(PixelFont.badge).foregroundStyle(PixelColor.inkWeak)
                        PixelMeter(value: 0.8, fill: PixelColor.locked)
                    }
                }

                section("버튼") {
                    VStack(spacing: PixelSpacing.m) {
                        PixelButton(title: "자세히 보기", style: .primary) {}
                        PixelButton(title: "미리 받아두기", style: .accent, leadingIcon: .download) {}
                        PixelButton(title: "장소 정보", style: .plain) {}
                    }
                }

                section("배지") {
                    VStack(alignment: .leading, spacing: PixelSpacing.s) {
                        HStack(spacing: PixelSpacing.s) {
                            PixelBadge(text: "앞부분 무료", kind: .free)
                            PixelBadge(text: "지금 여기예요", kind: .here)
                        }
                        HStack(spacing: PixelSpacing.s) {
                            PixelBadge(text: "해설 3분", kind: .audio)
                            PixelBadge(text: "들었어요", kind: .heard)
                            PixelBadge(text: "잠김", kind: .locked)
                        }
                    }
                }
            }
            .padding(PixelSpacing.screenMargin)
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationTitle("픽셀 부품")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            Text(title)
                .pixelFont(PixelFont.screenTitle)
                .foregroundStyle(PixelColor.ink)
            content()
        }
    }
}
