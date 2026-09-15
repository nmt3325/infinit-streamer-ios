import Foundation

/// アプリ全体の設定。Info.plist の `GoogleOAuthClientID` を読み取る。
enum AppConfig {
    /// 作成する配信のタイトル接頭辞。
    static let broadcastTitlePrefix = "InfinitStreamer"

    /// 作成する配信の公開設定（public / unlisted / private）。
    static let privacyStatus = "public"

    /// iOS 用 OAuth クライアント ID（例: 1234-abc.apps.googleusercontent.com）。
    static var googleClientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
              !value.isEmpty,
              !value.hasPrefix("YOUR_CLIENT_ID") else { return nil }
        return value
    }

    /// 逆ドメイン形式のカスタム URL スキーム。
    static var redirectScheme: String? {
        guard let id = googleClientID else { return nil }
        let suffix = ".apps.googleusercontent.com"
        guard id.hasSuffix(suffix) else { return nil }
        return "com.googleusercontent.apps." + String(id.dropLast(suffix.count))
    }

    static var redirectURI: String? {
        guard let scheme = redirectScheme else { return nil }
        return scheme + ":/oauth2redirect"
    }
}
