import Foundation
import AVFoundation
import Combine

/// 곱딱이 대사 음성 재생.
///
/// **곱딱이가 말하는 모든 말을 읽는다** (2026-09-11 조익준님 결정). 전에는 Story 만
/// 읽었고 말풍선 안 스피커 버튼을 눌러야 들렸다. 이제 단계가 바뀌어 대사가 나오면
/// **자동으로 재생**되고, 상단 HUD 의 스피커 버튼으로 끄고 켠다. 끈 상태는 기기에
/// 남아 다음 PLAY 에도 이어진다.
///
/// 화면에 보이는 자막과 귀에 들리는 말은 같은 문장이다 — 서버가 대사 열쇠
/// (`point:…` `mission:…:0` `story:…`)로 우리 원고에서 문장을 찾아 읽는다.
/// 클라이언트는 문장을 보내지 않는다.
///
/// ## 왜 다운로드가 아니라 스트리밍인가
///
/// 첫 재생은 서버가 Typecast 로 만드느라 3초쯤 걸린다(실측). 통째로 받고 나서
/// 재생하면 그 3초 동안 화면이 멈춘 것처럼 보인다. `AVPlayer` 로 흘려 들으면
/// 준비되는 대로 소리가 난다. 두 번째부터는 서버 캐시라 즉시다.
///
/// ## 소리가 안 나도 진행은 막지 않는다
///
/// 현장은 통신이 불안하다. 음성이 실패하면 **자막은 그대로 있고** 상태만 `failed` 가
/// 된다. 이야기를 못 들었다고 다음 Point 로 못 가면 안 된다.
@MainActor
final class StoryAudioPlayer: NSObject, ObservableObject {
    static let shared = StoryAudioPlayer()

    enum State: Equatable {
        case idle
        case loading
        case playing
        case failed
    }

    @Published private(set) var state: State = .idle
    /// 지금 재생 중인 대사 열쇠. 화면이 여러 개 떠 있어도 자기 것만 반응하게 한다.
    @Published private(set) var currentLine: String?

    private static let mutedKey = "play.voiceMuted"
    /// 사용자가 스피커를 끈 상태. 기기에 남는다.
    @Published private(set) var isMuted: Bool = UserDefaults.standard.bool(forKey: StoryAudioPlayer.mutedKey)

    func setMuted(_ muted: Bool) {
        isMuted = muted
        UserDefaults.standard.set(muted, forKey: Self.mutedKey)
        if muted { stop() }
    }

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    /// 미리 받아 둔 대사 음성. 열쇠 → 임시 파일. 로컬 파일은 `AVPlayer` 가 거의
    /// 즉시 `readyToPlay` 가 되어 글자와 소리가 같이 출발한다.
    private var prefetched: [String: URL] = [:]
    private var prefetching: Set<String> = []

    private override init() {
        super.init()
        // 무음 스위치가 켜져 있어도 들려야 한다 — 이어폰을 끼고 걷는 사용이 기본이다.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// 대사 한 줄을 읽는다. 음소거 중이면 아무것도 하지 않는다.
    /// 같은 줄을 이미 읽고 있으면 다시 시작하지 않는다 — 화면이 다시 그려질 때마다
    /// 처음부터 들리면 안 된다.
    func play(playId: String, line: String) {
        if isMuted { return }
        if currentLine == line, state == .playing || state == .loading { return }
        stop()
        guard var c = URLComponents(string: Config.baseURL + "/tts/line") else {
            state = .failed; return
        }
        c.queryItems = [
            .init(name: "play_id", value: playId),
            .init(name: "line", value: line),
        ]
        guard let url = c.url else { state = .failed; return }

        currentLine = line
        state = .loading

        let item = AVPlayerItem(url: prefetched[line] ?? url)
        let p = AVPlayer(playerItem: item)
        player = p

        statusObserver = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay: self.state = .playing
                case .failed:      self.state = .failed
                default:           break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        p.play()
    }

    private static func lineURL(playId: String, line: String) -> URL? {
        var c = URLComponents(string: Config.baseURL + "/tts/line")
        c?.queryItems = [.init(name: "play_id", value: playId), .init(name: "line", value: line)]
        return c?.url
    }

    /// 다음에 나올 대사를 미리 받아 둔다. 실패해도 조용히 넘어간다 — 재생 때 서버에서
    /// 바로 흘려 듣는 길이 그대로 있다. 음소거 중에도 받아 둔다(켜는 순간 바로 들리게).
    func prefetch(playId: String, line: String) {
        if prefetched[line] != nil || prefetching.contains(line) { return }
        guard let url = Self.lineURL(playId: playId, line: line) else { return }
        prefetching.insert(line)
        Task { [weak self] in
            defer { Task { @MainActor in self?.prefetching.remove(line) } }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("line-" + String(line.hashValue, radix: 16))
                .appendingPathExtension("mp3")
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
            await MainActor.run { self?.prefetched[line] = file }
        }
    }

    func stop() {
        player?.pause()
        player = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        state = .idle
        currentLine = nil
    }
}
