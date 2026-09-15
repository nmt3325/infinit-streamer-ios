import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

enum AuthError: LocalizedError {
    case missingClientID
    case invalidCallback
    case notSignedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Info.plist の GoogleOAuthClientID が設定されていません。"
        case .invalidCallback:
            return "OAuth コールバックを解釈できませんでした。"
        case .notSignedIn:
            return "Google アカウントにサインインしていません。"
        case .server(let message):
            return "OAuth エラー: \(message)"
        }
    }
}

/// PKCE を用いた Google OAuth（インストール済みアプリ用フロー）。
final class GoogleAuth: NSObject, ObservableObject {
    static let scope = "https://www.googleapis.com/auth/youtube"

    @Published private(set) var isSignedIn = false

    private let store = TokenStore(service: "com.infinitstreamer.ios.oauth")
    private var tokens: TokenSet?
    private var webSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        tokens = store.load()
        isSignedIn = tokens != nil
    }

    func signOut() {
        tokens = nil
        store.save(nil)
        DispatchQueue.main.async { self.isSignedIn = false }
    }

    func signIn() async throws {
        guard let clientID = AppConfig.googleClientID, let redirectURI = AppConfig.redirectURI,
              let scheme = AppConfig.redirectScheme else {
            throw AuthError.missingClientID
        }

        let verifier = Self.randomURLSafeString(64)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        let callback = try await authenticate(url: components.url!, scheme: scheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidCallback
        }

        let set = try await exchange(parameters: [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ], keepingRefreshToken: nil)
        tokens = set
        store.save(set)
        await MainActor.run { self.isSignedIn = true }
    }

    /// 有効なアクセストークンを返す（必要に応じてリフレッシュ）。
    func accessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notSignedIn }
        guard current.needsRefresh else { return current.accessToken }
        guard let clientID = AppConfig.googleClientID else { throw AuthError.missingClientID }
        guard let refreshToken = current.refreshToken else { throw AuthError.notSignedIn }

        let set = try await exchange(parameters: [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ], keepingRefreshToken: refreshToken)
        tokens = set
        store.save(set)
        return set.accessToken
    }

    // MARK: - Private

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            DispatchQueue.main.async { session.start() }
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private struct ErrorResponse: Decodable {
        let error: String?
        let error_description: String?
    }

    private func exchange(parameters: [String: String], keepingRefreshToken: String?) async throws -> TokenSet {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.server(decoded?.error_description ?? decoded?.error ?? "unknown")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenSet(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? keepingRefreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expires_in)
        )
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func randomURLSafeString(_ length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count)] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
