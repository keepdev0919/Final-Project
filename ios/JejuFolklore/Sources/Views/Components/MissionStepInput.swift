import SwiftUI

/// Mission Step 하나의 입력 화면.
///
/// **Challenge Pattern 과 Input 은 다른 축이다** (`콘텐츠.md` §10).
/// 현실에서 하는 행동(FIND·COMPARE·INFER…)은 콘텐츠 메타데이터이고,
/// 화면을 정하는 것은 `inputType` 하나뿐이다. 그래서 이 뷰 하나가
/// 여섯 가지 입력을 전부 처리한다.
///
///     CONFIRM      [찾았어요] — 누르면 통과. 다음 Step 이 진짜 검증을 한다
///     CHOICE       보기 선택 (글자 · 그림)
///     DIRECTION    ← 왼쪽 / 오른쪽 →
///     NUMBER       개수
///     SHORT_TEXT   현판·각인처럼 짧고 명확한 답
///     MATCH_ORDER  짝 맞추기 또는 순서 세우기
struct MissionStepInput: View {
    let step: MissionStep
    /// 사용자가 답을 냈다. 맞는지 판정은 부모가 한다.
    let onSubmit: (MissionAnswer) -> Void

    var body: some View {
        switch step.inputType {
        case .confirm:    ConfirmInput(onSubmit: onSubmit)
        case .choice:     ChoiceInput(step: step, onSubmit: onSubmit)
        case .direction:  DirectionInput(onSubmit: onSubmit)
        case .number:     NumberInput(onSubmit: onSubmit)
        case .shortText:  ShortTextInput(onSubmit: onSubmit)
        case .matchOrder: MatchOrderInput(step: step, onSubmit: onSubmit)
        }
    }
}

// MARK: - CONFIRM

private struct ConfirmInput: View {
    let onSubmit: (MissionAnswer) -> Void
    var body: some View {
        PixelButton(title: "찾았어요", style: .primary) { onSubmit(.none) }
    }
}

// MARK: - CHOICE

/// 보기 선택. **설명을 읽고 바로 답할 수 있는 객관식은 콘텐츠 단계에서 걸러진다**
/// (`콘텐츠.md` §10). 여기서는 현실을 보고 온 사용자가 답을 내는 자리다.
private struct ChoiceInput: View {
    let step: MissionStep
    let onSubmit: (MissionAnswer) -> Void
    @State private var picked: String?

    private var hasImages: Bool { step.options.contains { $0.image != nil } }

    var body: some View {
        VStack(spacing: PixelSpacing.m) {
            ForEach(step.options) { option in
                Button {
                    picked = option.id
                    onSubmit(.text(option.id))
                } label: {
                    HStack(alignment: .center, spacing: PixelSpacing.m) {
                        if hasImages, let img = option.image, let url = URL(string: img) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let i): i.resizable().scaledToFit()
                                default: PixelColor.surfaceHigh
                                }
                            }
                            .frame(width: 64, height: 64)
                            .pixelBorder()
                        }
                        Text(option.label)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(PixelSpacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(picked == option.id ? PixelColor.surfaceHigh : PixelColor.surface)
                    .pixelBorder()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked == option.id ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - DIRECTION

/// 왼쪽 / 오른쪽. 위·아래는 콘텐츠에 아직 없어 두 개만 띄운다.
///
/// ⚠️ 방향 문제는 **자료마다 좌·우 설명이 엇갈릴 수 있다.** 성읍 M05 가 그래서
/// 방향 정답을 쓰지 않기로 했다(정본 §M05). 쓸 때는 현장에서 기준이 분명한지 본다.
private struct DirectionInput: View {
    let onSubmit: (MissionAnswer) -> Void

    var body: some View {
        HStack(spacing: PixelSpacing.m) {
            button("← 왼쪽", "LEFT")
            button("오른쪽 →", "RIGHT")
        }
    }

    private func button(_ label: String, _ value: String) -> some View {
        Button { onSubmit(.text(value)) } label: {
            Text(label)
                .font(PixelFont.bodyLarge)
                .foregroundStyle(PixelColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PixelSpacing.xl)
                .background(PixelColor.surface)
                .pixelBorder()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NUMBER

private struct NumberInput: View {
    let onSubmit: (MissionAnswer) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: PixelSpacing.m) {
            TextField("숫자", text: $text)
                .keyboardType(.numberPad)
                .focused($focused)
                .font(PixelFont.screenTitle)
                .multilineTextAlignment(.center)
                .padding(PixelSpacing.l)
                .background(PixelColor.surface)
                .pixelBorder()
            PixelButton(title: "확인", style: .primary) {
                guard let n = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
                focused = false
                onSubmit(.number(n))
            }
        }
    }
}

// MARK: - SHORT_TEXT

/// 현판·각인처럼 짧고 명확한 답. **허용 답안이 여러 개**라 표기가 조금 달라도 통과한다
/// (`MissionStep.isCorrect` 참조) — 표기 차이로 정답을 못 맞히는 일이 제일 흔하다.
private struct ShortTextInput: View {
    let onSubmit: (MissionAnswer) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: PixelSpacing.m) {
            TextField("본 대로 적어주세요", text: $text)
                .focused($focused)
                .font(PixelFont.bodyLarge)
                .multilineTextAlignment(.center)
                .padding(PixelSpacing.l)
                .background(PixelColor.surface)
                .pixelBorder()
            PixelButton(title: "확인", style: .primary) {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                focused = false
                onSubmit(.text(t))
            }
        }
    }
}

// MARK: - MATCH_ORDER

/// 짝 맞추기(왼쪽↔오른쪽) 또는 순서 세우기.
///
/// 성읍 FINAL 이 이걸 쓴다 — 정주석→경계, 물팡→물처럼 **직접 발견한 것**을
/// 이어 붙인다. 새 지식을 묻지 않는다(정본 §12).
///
/// 드래그를 쓰지 않는다. 현장에서 한 손으로, 장갑을 끼고도 눌러야 한다.
/// 왼쪽을 누르고 오른쪽을 누르면 짝이 된다.
private struct MatchOrderInput: View {
    let step: MissionStep
    let onSubmit: (MissionAnswer) -> Void

    @State private var selectedLeft: String?
    @State private var pairs: [String: String] = [:]   // leftId → rightId
    @State private var order: [String] = []            // 순서 세우기용

    private var isMatching: Bool { !step.matchTargets.isEmpty }

    var body: some View {
        VStack(spacing: PixelSpacing.l) {
            if isMatching { matchBody } else { orderBody }

            PixelButton(title: "확인", style: .primary) {
                if isMatching {
                    onSubmit(.list(pairs.map { "\($0.key)>\($0.value)" }))
                } else {
                    onSubmit(.list(order))
                }
            }
            .disabled(isMatching ? pairs.count != step.options.count
                                 : order.count != step.options.count)
            .opacity(readyToSubmit ? 1 : 0.4)
        }
    }

    private var readyToSubmit: Bool {
        isMatching ? pairs.count == step.options.count : order.count == step.options.count
    }

    // 짝 맞추기 — 왼쪽 고르고 오른쪽 고르기
    private var matchBody: some View {
        HStack(alignment: .top, spacing: PixelSpacing.m) {
            VStack(spacing: PixelSpacing.s) {
                ForEach(step.options) { o in
                    chip(o.label,
                         selected: selectedLeft == o.id,
                         done: pairs[o.id] != nil,
                         trailing: pairs[o.id].flatMap { rid in
                             step.matchTargets.first { $0.id == rid }?.label
                         }) {
                        selectedLeft = (selectedLeft == o.id) ? nil : o.id
                    }
                }
            }
            VStack(spacing: PixelSpacing.s) {
                ForEach(step.matchTargets) { t in
                    chip(t.label,
                         selected: false,
                         done: pairs.values.contains(t.id),
                         trailing: nil) {
                        guard let left = selectedLeft else { return }
                        // 같은 오른쪽을 두 번 쓰지 않게, 먼저 쓰던 짝을 푼다.
                        pairs = pairs.filter { $0.value != t.id }
                        pairs[left] = t.id
                        selectedLeft = nil
                    }
                }
            }
        }
    }

    // 순서 세우기 — 누른 차례가 곧 순서
    private var orderBody: some View {
        VStack(spacing: PixelSpacing.s) {
            ForEach(step.options) { o in
                let idx = order.firstIndex(of: o.id)
                chip(o.label,
                     selected: false,
                     done: idx != nil,
                     trailing: idx.map { "\($0 + 1)" }) {
                    if let i = idx { order.remove(at: i) } else { order.append(o.id) }
                }
            }
        }
    }

    private func chip(_ label: String, selected: Bool, done: Bool,
                      trailing: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PixelSpacing.xs) {
                Text(label)
                    .font(PixelFont.body)
                    .foregroundStyle(done ? PixelColor.onDone : PixelColor.ink)
                    .multilineTextAlignment(.leading)
                if let trailing {
                    Text(trailing)
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(done ? PixelColor.onDone : PixelColor.inkWeak)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PixelSpacing.m)
            .padding(.vertical, PixelSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(done ? PixelColor.done
                             : (selected ? PixelColor.surfaceHigh : PixelColor.surface))
            .pixelBorder()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
