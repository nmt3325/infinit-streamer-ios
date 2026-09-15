import Foundation
import Security

struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var needsRefresh: Bool { Date() >= expiresAt.addingTimeInterval(-120) }
}

/// Keychain に OAuth トークンを保存する。
struct TokenStore {
    let service: String
    let account = "google-oauth"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> TokenSet? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    func save(_ tokens: TokenSet?) {
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}
