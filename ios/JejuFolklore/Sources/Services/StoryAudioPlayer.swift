import Foundation
import AVFoundation
import Combine

/// Story 음성 재생.
///
/// **오디 대본이 아니라 놀멍봅서가 쓴 문장을 읽는다** (2026-09-02 결정).
/// 화면에 보이는 자막과 귀에 들리는 말이 같은 `story.script` 하나에서 나온다.
///
/// ## 왜 다운로드가 아니라 스트리밍인가
///
/// 첫 재생은 서버가 Typecast 로 만드느라 3초쯤 걸린다(실측). 통째로 받고 나서
/// 재생하면 그 3초 동안 화면이 멈춘 것처럼 보인다. `AVPlayer` 로 흘려 들으면
/// 준비되는 대로 소리가 난다. 두 번째부터는 서버 캐시라 즉시다.
///
/// ## 소리가 안 나도 진행은 막지 않는다
///
/// 현장은 통신이 불안하다. 음성이 실패하면 **자막은 그대로 있고** 재생 버튼만
/// 「소리를 못 불러왔어요」로 바뀐다. 이야기를 못 들었다고 다음 Point 로 못 가면 안 된다.
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
    /// 지금 재생 중인 이야기. 화면이 여러 개 떠 있어도 자기 것만 반응하게 한다.
    @Published private(set) var currentStoryId: String?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    private override init() {
        super.init()
        // 무음 스위치가 켜져 있어도 들려야 한다 — 이어폰을 끼고 걷는 사용이 기본이다.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(playId: String, storyId: String) {
        stop()
        guard var c = URLComponents(string: Config.baseURL + "/tts/story") else {
            state = .failed; return
        }
        c.queryItems = [
            .init(name: "play_id", value: playId),
            .init(name: "story_id", value: storyId),
        ]
        guard let url = c.url else { state = .failed; return }

        currentStoryId = storyId
        state = .loading

        let item = AVPlayerItem(url: url)
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
        currentStoryId = nil
    }

    /// 이 이야기가 지금 재생 중인가. 버튼 모양을 정하는 데 쓴다.
    func isActive(_ storyId: String) -> Bool {
        currentStoryId == storyId && (state == .playing || state == .loading)
    }
}
