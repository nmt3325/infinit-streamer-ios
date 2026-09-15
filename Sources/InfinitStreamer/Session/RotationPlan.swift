import Foundation

/// 配信ローテーションのルール（純粋ロジックのためテスト対象）。
struct RotationPlan: Equatable {
    /// 1 本あたりの配信長。YouTube の 12 時間上限に対して 5 分の余裕を確保する。
    var intervalSeconds: TimeInterval = 11 * 3600 + 55 * 60

    /// 次のライブを事前に作成しておく秒数（切り替え時の断を最小化する）。
    var prerollSeconds: TimeInterval = 90

    /// 再試行の最大待ち時間。
    var maxBackoffSeconds: TimeInterval = 300

    func rotationDate(startedAt start: Date) -> Date {
        start.addingTimeInterval(intervalSeconds)
    }

    /// 次のライブを作り始める時刻。
    func prepareDate(rotatingAt rotation: Date) -> Date {
        rotation.addingTimeInterval(-prerollSeconds)
    }

    func backoffSeconds(failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return 0 }
        let exponential = pow(2.0, Double(min(failureCount, 10)))
        return min(maxBackoffSeconds, exponential)
    }

    func title(cycle: Int, date: Date, prefix: String = AppConfig.broadcastTitlePrefix) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(prefix) #\(cycle) — \(formatter.string(from: date))"
    }
}
