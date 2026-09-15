import SwiftUI
import UIKit

/// 아이콘. **시안이 쓰는 Material Icons 를 그대로 쓴다.**
///
/// 2026-09-03: 8×8 도트를 손으로 찍어 그리던 것을 걷어냈다.
///
/// 시안 HTML 은 `Material Symbols Outlined` 를 `FILL 1` 로 불러온다. 그걸
/// 「픽셀 앱이니까」 하고 8×8 격자로 옮겨 그렸더니 **알아볼 수 없는 그림**이 됐다 —
/// 별이 십자가 되고, 지도가 하트가 되고, 느낌표가 그냥 사각형이 됐다.
/// 8×8 로는 시계도 걷는 사람도 표현되지 않는다.
///
/// 채움(FILL 1) 스타일이 필요해서 **클래식 `MaterialIcons-Regular.ttf`** 를 쓴다.
/// 이 폰트는 원래부터 채움이고, 시안이 쓰는 글리프 이름이 그대로 있다.
/// (Flutter 가 기본 내장하는 것과 같은 폰트다.)
///
/// 이름에 `Pixel` 이 남은 것은 디자인 시스템 이름 규칙(`PixelColor`·`PixelFont`·
/// `PixelSpacing`)을 따르기 위해서다. 픽셀아트 정체성은 **커버 그림과 두꺼운
/// 테두리**가 만든다 — 아이콘이 아니다.
struct PixelIcon: View {
    enum Glyph {
        case play, pause, next, photo, lock, check, mapPin, download, home, map, person, back
        case forward, up, down, close, calendar, clock, warn, refresh, shuffle
        case share, edit, more, target, book, headphone
        /// 장소 화면의 이용팁 줄(운영시간·입장료·주차·전화)과 받아쓰기 버튼
        case coin, car, phone, stop, mic
        /// 세계관 라벨 6종
        case volcano, wave, drop, tree, house, gate
        /// 시안 추가 — 난이도 별, 퀘스트 탭, 안내 느낌표, 걷는 거리
        case star, quest, bang, walk, compass
        /// 현장 진행 화면 — 소리 켜기·끄기, 다음 표시
        case sound, soundOff, caret
        /// 장소 정보 — 이용 정보 칩(휴무·화장실·입장료)과 무장애 타일
        case wc, ticket, dayOpen, info, snow, parkingSign
        case wheelchair, wheelchairForward, stroller, nursing, bus, hearing, eye

        /// Material Icons 글리프. 주석은 원래 아이콘 이름이다.
        var codepoint: String {
            switch self {
            case .play:      return "\u{e037}"  // play_arrow
            case .pause:     return "\u{e034}"  // pause
            case .next:      return "\u{e044}"  // skip_next
            case .photo:     return "\u{e3f4}"  // image
            case .lock:      return "\u{e897}"  // lock
            case .check:     return "\u{e5ca}"  // check
            case .mapPin:    return "\u{e55f}"  // place
            case .download:  return "\u{e2c4}"  // file_download
            case .home:      return "\u{e88a}"  // home
            case .map:       return "\u{e55b}"  // map
            case .person:    return "\u{e7fd}"  // person
            case .back:      return "\u{e5c4}"  // arrow_back
            case .forward:   return "\u{e5c8}"  // arrow_forward
            case .up:        return "\u{e316}"  // keyboard_arrow_up
            case .down:      return "\u{e313}"  // keyboard_arrow_down
            case .close:     return "\u{e5cd}"  // close
            case .calendar:  return "\u{e935}"  // calendar_today
            case .clock:     return "\u{e8b5}"  // schedule
            case .warn:      return "\u{e002}"  // warning
            case .refresh:   return "\u{e5d5}"  // refresh
            case .shuffle:   return "\u{e043}"  // shuffle
            case .share:     return "\u{e80d}"  // share
            case .edit:      return "\u{e3c9}"  // edit
            case .more:      return "\u{e5d3}"  // more_horiz
            case .target:    return "\u{e55c}"  // my_location
            case .book:      return "\u{ea19}"  // menu_book
            case .headphone: return "\u{f01f}"  // headphones
            case .coin:      return "\u{ef63}"  // payments
            case .car:       return "\u{e531}"  // directions_car
            case .phone:     return "\u{e0cd}"  // phone
            case .stop:      return "\u{e047}"  // stop
            case .mic:       return "\u{e029}"  // mic
            case .volcano:   return "\u{e3f7}"  // landscape
            case .wave:      return "\u{e176}"  // waves
            case .drop:      return "\u{e798}"  // water_drop
            case .tree:      return "\u{ea63}"  // park
            case .house:     return "\u{ea44}"  // house
            case .gate:      return "\u{eb4f}"  // meeting_room
            case .star:      return "\u{e838}"  // star
            case .quest:     return "\u{ea28}"  // sports_esports
            case .bang:      return "\u{e645}"  // priority_high
            case .walk:      return "\u{e536}"  // directions_walk
            case .compass:   return "\u{e87a}"  // explore
            case .sound:     return "\u{e050}"  // volume_up
            case .soundOff:  return "\u{e04f}"  // volume_off
            case .caret:     return "\u{e5c5}"  // arrow_drop_down
            case .wc:        return "\u{e63d}"  // wc
            case .ticket:    return "\u{e638}"  // confirmation_number
            case .dayOpen:   return "\u{e614}"  // event_available
            case .info:      return "\u{e88e}"  // info
            case .snow:      return "\u{eb3b}"  // ac_unit
            case .parkingSign: return "\u{e54f}" // local_parking
            case .wheelchair: return "\u{e914}" // accessible
            case .wheelchairForward: return "\u{e934}" // accessible_forward
            case .stroller:  return "\u{eb41}"  // child_friendly
            case .nursing:   return "\u{f19b}"  // baby_changing_station
            case .bus:       return "\u{e530}"  // directions_bus
            case .hearing:   return "\u{e023}"  // hearing
            case .eye:       return "\u{e8f4}"  // visibility
            }
        }
    }

    /// 번들에 등록된 패밀리 이름. `Info.plist` 의 `UIAppFonts` 와 짝이다.
    static let fontName = "Material Icons"

    let glyph: Glyph
    var size: CGFloat
    /// nil 이면 바깥에서 준 `.foregroundColor`·`.foregroundStyle` 을 따른다.
    ///
    /// ⚠️ 기본값을 잉크로 **고정하지 않는다.** 고정하면 바깥의 `.foregroundColor(...)` 가
    /// 조용히 무시된다 — 2026-08-20 리뷰에서 이 때문에 19곳이 잘못된 색으로 그려지고
    /// 있었다.
    var color: Color?

    init(_ glyph: Glyph, size: CGFloat = 24, color: Color? = nil) {
        self.glyph = glyph
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(verbatim: glyph.codepoint)
            // `fixedSize:` 라 손글씨 크기 설정을 따라 커지지 않는다. 아이콘은 자리가
            // 정해져 있어서 커지면 글자와 어긋난다.
            .font(.custom(Self.fontName, fixedSize: size))
            .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension PixelIcon {
    /// `Image` 만 받는 자리에 쓰는 UIImage 렌더링.
    ///
    /// ⚠️ SwiftUI `tabItem` 은 임의 View 를 **조용히 무시하고** Image 만 그린다.
    /// `PixelIcon` 을 그대로 넘기면 아이콘 없이 글자만 나온다(2026-08-14 확인).
    /// 템플릿 모드로 돌려주므로 탭바가 선택/비선택 색을 알아서 입힌다.
    static func uiImage(_ glyph: Glyph, size: CGFloat = 24) -> UIImage {
        let font = UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        let text = glyph.codepoint as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let box = CGSize(width: size, height: size)

        let renderer = UIGraphicsImageRenderer(size: box)
        let image = renderer.image { _ in
            let drawn = text.size(withAttributes: attrs)
            // 글리프는 em 상자 안에 그려진다 — 상자 한가운데 놓는다.
            text.draw(at: CGPoint(x: (box.width - drawn.width) / 2,
                                  y: (box.height - drawn.height) / 2),
                      withAttributes: attrs)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

#Preview {
    let all: [PixelIcon.Glyph] = [
        .play, .pause, .next, .photo, .lock, .check, .mapPin, .download,
        .home, .map, .person, .back, .forward, .up, .down, .close,
        .calendar, .clock, .warn, .refresh, .shuffle, .share, .edit, .more,
        .target, .book, .headphone, .coin, .car, .phone, .stop, .mic,
        .volcano, .wave, .drop, .tree, .house, .gate, .star, .quest, .bang, .walk, .compass,
        .sound, .soundOff, .caret,
    ]
    return ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(), count: 6), spacing: PixelSpacing.l) {
            ForEach(Array(all.enumerated()), id: \.offset) { _, glyph in
                PixelIcon(glyph, size: 28, color: PixelColor.ink)
            }
        }
        .padding(PixelSpacing.xl)
    }
    .background(PixelColor.background)
}
