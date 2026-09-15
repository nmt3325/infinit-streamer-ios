import Foundation
import SwiftUI

/// アプリのメイン機能: 11時間55分ごとに新しい YouTube ライブへ切り替えながら、
/// アーカイブを残しつつ永久に配信を続ける。
@MainActor
final class SessionCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case live
        case preparingNext
        case rotating
        case retrying(String)

        var label: String {
            switch self {
            case .idle: return "停止中"
            case .starting: return "開始中"
            case .live: return "配信中"
            case .preparingNext: return "次の配信を準備中"
            case .rotating: return "切り替え中"
            case .retrying(let message): return "再試行待ち: \(message)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentBroadcastURL: URL?
    @Published private(set) var nextRotationAt: Date?
    @Published private(set) var cycleCount = 0
    @Published private(set) var logs: [String] = []

    let publisher = RTMPPublisher()
    let plan = RotationPlan()

    private let auth: GoogleAuth
    private let youtube: YouTubeClient
    private var loop: Task<Void, Never>?

    init(auth: GoogleAuth) {
        self.auth = auth
        self.youtube = YouTubeClient(tokenProvider: { try await auth.accessToken() })
    }

    var isRunning: Bool { loop != nil }

    func start() {
        guard loop == nil else { return }
        phase = .starting
        loop = Task { [weak self] in await self?.runForever() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        publisher.stop()
        nextRotationAt = nil
        phase = .idle
        append("停止しました")
    }

    // MARK: - Core loop

    private func runForever() async {
        var failures = 0
        var prepared: BroadcastCycle?
        var previousBroadcastID: String?

        do {
            try publisher.prepare()
        } catch {
            append("キャプチャ初期化に失敗: \(error.localizedDescription)")
        }

        while !Task.isCancelled {
            do {
                cycleCount += 1
                let now = Date()
                let cycle: BroadcastCycle
                if let prepared {
                    cycle = prepared
                } else {
                    append("新規ライブを作成中…")
                    cycle = try await youtube.openCycle(title: plan.title(cycle: cycleCount, date: now))
                }
                prepared = nil

                try await publisher.switchTarget(
                    url: cycle.stream.ingestionAddress,
                    streamKey: cycle.stream.streamName
                )
                currentBroadcastURL = cycle.broadcast.watchURL
                phase = .live
                append("配信 #\(cycleCount) 開始: \(cycle.broadcast.watchURL?.absoluteString ?? cycle.broadcast.id)")

                // 旧配信を終了してアーカイブを確定。
                if let previousBroadcastID {
                    do {
                        try await youtube.complete(broadcastID: previousBroadcastID)
                        append("前の配信を終了（アーカイブ確定）")
                    } catch {
                        append("前の配信の終了に失敗: \(error.localizedDescription)")
                    }
                }
                previousBroadcastID = cycle.broadcast.id

                let rotateAt = plan.rotationDate(startedAt: Date())
                nextRotationAt = rotateAt

                try await sleep(until: plan.prepareDate(rotatingAt: rotateAt))
                phase = .preparingNext
                append("次のライブを事前作成中…")
                prepared = try await youtube.openCycle(
                    title: plan.title(cycle: cycleCount + 1, date: rotateAt)
                )

                try await sleep(until: rotateAt)
                phase = .rotating
                failures = 0
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                let wait = plan.backoffSeconds(failureCount: failures)
                phase = .retrying(error.localizedDescription)
                append("エラー: \(error.localizedDescription) / \(Int(wait)) 秒後に再試行")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func sleep(until date: Date) async throws {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func append(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.insert("[\(formatter.string(from: Date()))] \(message)", at: 0)
        if logs.count > 200 { logs.removeLast(logs.count - 200) }
    }
}
