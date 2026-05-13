import Foundation
import Speech
import AVFoundation

/// 한국어 STT를 위한 SFSpeechRecognizer 래퍼.
/// PlaceReviewSheet의 마이크 버튼에서 사용한다.
@MainActor
final class SpeechRecognizer: ObservableObject {
    // MARK: - Published state

    /// 인식된 누적 텍스트(최종 + 부분 결과). UI는 이 값을 관찰한다.
    @Published var transcript: String = ""

    /// 현재 마이크 캡처 + 인식이 진행 중인지.
    @Published var isRecording: Bool = false

    /// 음성 인식 권한 상태.
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// 마이크 권한 상태(iOS 17+: AVAudioApplication).
    @Published var microphonePermission: AVAudioSession.RecordPermission = .undetermined

    /// 사람이 읽을 수 있는 마지막 에러 메시지(권한 거부, 엔진 실패 등).
    @Published var lastErrorMessage: String?

    // MARK: - Private

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// start() 호출 시점에 이미 입력되어 있던 텍스트.
    /// 부분 결과(partial)가 들어올 때마다 baseText + 새 결과로 합쳐서 transcript를 업데이트한다.
    /// 이렇게 하면 사용자가 키보드로 친 텍스트 뒤에 받아쓰기 결과가 자연스럽게 이어 붙는다.
    private var baseText: String = ""

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
        self.authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        #if os(iOS)
        self.microphonePermission = AVAudioSession.sharedInstance().recordPermission
        #endif
    }

    // MARK: - Permission

    /// 음성 인식 + 마이크 권한을 모두 요청한다.
    /// 결과는 @Published 상태에 반영된다.
    func requestPermissions() async {
        // 1. Speech Recognition 권한
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        self.authorizationStatus = speechStatus

        // 2. 마이크 권한
        #if os(iOS)
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        self.microphonePermission = micGranted ? .granted : .denied
        #endif
    }

    /// 받아쓰기를 시작할 수 있는 상태인지.
    var canRecord: Bool {
        guard let r = recognizer, r.isAvailable else { return false }
        return authorizationStatus == .authorized && microphonePermission == .granted
    }

    // MARK: - Control

    /// 받아쓰기 시작. 이미 transcript에 들어 있는 텍스트(키보드로 친 것 포함)는 보존되고,
    /// 새 음성 결과는 그 뒤에 이어 붙는다.
    func start() {
        // 이미 녹음 중이면 무시
        guard !isRecording else { return }

        // 권한 미부여면 즉시 에러
        guard canRecord else {
            lastErrorMessage = "마이크 또는 음성 인식 권한이 필요합니다."
            return
        }

        guard let recognizer = recognizer else {
            lastErrorMessage = "음성 인식기를 초기화할 수 없습니다."
            return
        }

        // 기존 세션 정리
        cancelInternal()

        // 현재 transcript를 base로 보존(이어 붙이기 위해)
        // 단, 비어있지 않다면 끝에 공백 한 칸을 두어 새 결과와 자연스럽게 분리한다
        if transcript.isEmpty {
            baseText = ""
        } else if transcript.hasSuffix(" ") {
            baseText = transcript
        } else {
            baseText = transcript + " "
        }

        // AVAudioSession 구성
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastErrorMessage = "오디오 세션 설정 실패: \(error.localizedDescription)"
            return
        }
        #endif

        // 인식 요청
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if #available(iOS 13, *) {
            req.requiresOnDeviceRecognition = false
        }
        self.request = req

        // 입력 노드에서 PCM 버퍼를 받아 요청에 전달
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // 시뮬레이터·일부 환경에서 outputFormat이 sampleRate=0 / channelCount=0인
        // invalid AVAudioFormat을 반환해서 installTap이 NSException으로 크래시하는 케이스 방어.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            #if targetEnvironment(simulator)
            lastErrorMessage = "시뮬레이터에서는 마이크 입력을 사용할 수 없습니다. 실기기에서 시도해주세요."
            #else
            lastErrorMessage = "마이크 초기화 실패. 다른 앱이 마이크를 사용 중인지 확인해주세요."
            #endif
            cancelInternal()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        // 인식 태스크 시작
        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let result = result {
                    let newPart = result.bestTranscription.formattedString
                    self.transcript = self.baseText + newPart
                }
                if let error = error {
                    // cancel/end 정상 종료가 아닌 경우에만 표시
                    let nsErr = error as NSError
                    if nsErr.code != 301, nsErr.code != 216 { // common silent stop codes
                        self.lastErrorMessage = "음성 인식 오류: \(error.localizedDescription)"
                    }
                    self.cleanupAudio()
                    self.isRecording = false
                }
                if let result = result, result.isFinal {
                    self.cleanupAudio()
                    self.isRecording = false
                }
            }
        }

        // 엔진 시작
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "마이크 시작 실패: \(error.localizedDescription)"
            cancelInternal()
        }
    }

    /// 받아쓰기 중지. 지금까지 인식된 텍스트는 transcript에 그대로 남는다.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        cleanupAudio()
        isRecording = false
    }

    /// 모든 상태 초기화(텍스트도 비움).
    func reset() {
        cancelInternal()
        transcript = ""
        baseText = ""
        lastErrorMessage = nil
    }

    // MARK: - Internals

    private func cancelInternal() {
        task?.cancel()
        task = nil
        request = nil
        cleanupAudio()
        isRecording = false
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
