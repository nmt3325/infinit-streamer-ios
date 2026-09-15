import Foundation

struct LiveStreamResource {
    let id: String
    let ingestionAddress: String
    let streamName: String
}

struct LiveBroadcastResource {
    let id: String
    var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
}

/// 1 サイクル分の配信リソース（新規ライブ + 新規 RTMP ストリーム）。
struct BroadcastCycle {
    let broadcast: LiveBroadcastResource
    let stream: LiveStreamResource
}

enum YouTubeError: LocalizedError {
    case api(status: Int, message: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .api(let status, let message):
            return "YouTube API エラー (\(status)): \(message)"
        case .malformedResponse:
            return "YouTube API のレスポンスを解釈できませんでした。"
        }
    }
}

/// YouTube Data API v3 の Live Streaming 部分だけを扱う軽量クライアント。
struct YouTubeClient {
    let tokenProvider: () async throws -> String
    private let base = URL(string: "https://www.googleapis.com/youtube/v3/")!

    // MARK: - Public API

    /// アーカイブが残る新規ライブ配信を作成する。
    func createBroadcast(title: String, scheduledStart: Date) async throws -> LiveBroadcastResource {
        let body: [String: Any] = [
            "snippet": [
                "title": title,
                "scheduledStartTime": ISO8601DateFormatter().string(from: scheduledStart)
            ],
            "status": [
                "privacyStatus": AppConfig.privacyStatus,
                "selfDeclaredMadeForKids": false
            ],
            "contentDetails": [
                // 取り込み開始で自動的に公開、11時間55分後はアプリ側から明示的に終了する。
                "enableAutoStart": true,
                "enableAutoStop": false,
                // アーカイブを残すための最重要フラグ。
                "recordFromStart": true,
                "enableDvr": true,
                "latencyPreference": "low"
            ]
        ]
        let json = try await send(
            path: "liveBroadcasts",
            query: ["part": "snippet,status,contentDetails"],
            body: body
        )
        guard let id = json["id"] as? String else { throw YouTubeError.malformedResponse }
        return LiveBroadcastResource(id: id)
    }

    /// RTMP 取り込み用のストリームを作成する。
    func createStream(title: String) async throws -> LiveStreamResource {
        let body: [String: Any] = [
            "snippet": ["title": title],
            "cdn": [
                "frameRate": "variable",
                "ingestionType": "rtmp",
                "resolution": "variable"
            ]
        ]
        let json = try await send(
            path: "liveStreams",
            query: ["part": "snippet,cdn,status"],
            body: body
        )
        guard let id = json["id"] as? String,
              let cdn = json["cdn"] as? [String: Any],
              let info = cdn["ingestionInfo"] as? [String: Any],
              let address = info["ingestionAddress"] as? String,
              let name = info["streamName"] as? String else {
            throw YouTubeError.malformedResponse
        }
        return LiveStreamResource(id: id, ingestionAddress: address, streamName: name)
    }

    func bind(broadcastID: String, streamID: String) async throws {
        _ = try await send(
            path: "liveBroadcasts/bind",
            query: ["id": broadcastID, "streamId": streamID, "part": "id,contentDetails"],
            body: nil
        )
    }

    /// 配信を終了してアーカイブを確定させる。
    func complete(broadcastID: String) async throws {
        _ = try await send(
            path: "liveBroadcasts/transition",
            query: ["id": broadcastID, "broadcastStatus": "complete", "part": "id,status"],
            body: nil
        )
    }

    /// ライブ作成〜バインドまでをまとめて実行する。
    func openCycle(title: String) async throws -> BroadcastCycle {
        let broadcast = try await createBroadcast(title: title, scheduledStart: Date().addingTimeInterval(60))
        let stream = try await createStream(title: title)
        try await bind(broadcastID: broadcast.id, streamID: stream.id)
        return BroadcastCycle(broadcast: broadcast, stream: stream)
    }

    // MARK: - Transport

    private func send(path: String, query: [String: String], body: [String: Any]?) async throws -> [String: Any] {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YouTubeError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw YouTubeError.api(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YouTubeError.malformedResponse
        }
        return json
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8) ?? "unknown"
        }
        return message
    }
}
