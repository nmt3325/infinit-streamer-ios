import AVFoundation
import Foundation
import HaishinKit

enum PublishError: LocalizedError {
    case connectFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectFailed(let code):
            return "RTMP 接続に失敗しました (\(code))"
        }
    }
}

/// カメラ/マイクを RTMP で YouTube に送出する。配信先の切り替えもここで行う。
final class RTMPPublisher: NSObject, ObservableObject {
    @Published private(set) var isPublishing = false

    private let connection = RTMPConnection()
    lazy var stream: RTMPStream = RTMPStream(connection: connection)
    private var continuation: CheckedContinuation<Void, Error>?
    private var isPrepared = false

    func prepare() throws {
        guard !isPrepared else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        stream.frameRate = 30
        stream.sessionPreset = .hd1280x720
        stream.videoSettings = VideoCodecSettings(
            videoSize: .init(width: 1280, height: 720),
            bitRate: 2_500_000
        )
        stream.attachAudio(AVCaptureDevice.default(for: .audio)) { _, _ in }
        stream.attachCamera(
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            track: 0
        ) { _, _ in }
        isPrepared = true
    }

    /// 現在の配信を止め、新しい YouTube ライブの RTMP エンドポイントへ publish し直す。
    func switchTarget(url: String, streamKey: String) async throws {
        try prepare()
        stop()
        try await connect(url)
        stream.publish(streamKey)
        await MainActor.run { self.isPublishing = true }
    }

    func stop() {
        stream.close()
        connection.close()
        connection.removeEventListener(.rtmpStatus, selector: #selector(handleStatus(_:)), observer: self)
        DispatchQueue.main.async { self.isPublishing = false }
    }

    private func connect(_ url: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            connection.addEventListener(.rtmpStatus, selector: #selector(handleStatus(_:)), observer: self)
            connection.connect(url)
        }
    }

    @objc private func handleStatus(_ notification: Notification) {
        guard let data = Event.from(notification).data as? ASObject,
              let code = data["code"] as? String else { return }
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            continuation?.resume()
            continuation = nil
        case RTMPConnection.Code.connectFailed.rawValue,
             RTMPConnection.Code.connectClosed.rawValue,
             RTMPConnection.Code.connectRejected.rawValue:
            continuation?.resume(throwing: PublishError.connectFailed(code))
            continuation = nil
        default:
            break
        }
    }
}
