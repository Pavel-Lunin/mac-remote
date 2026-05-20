import Foundation
import Security
import os

/// Хранит единственный bearer-токен для авторизации мобильного клиента.
///
/// Токен лежит в Keychain под service `com.macremote.app`, account `auth-token`.
/// При первом обращении (если в Keychain пусто) генерируется новый 16-байтный hex-токен.
final class TokenStore {
    private static let service = "com.macremote.app"
    private static let account = "auth-token"
    private static let tokenByteCount = 16

    private let log = Logger(subsystem: "com.macremote.app", category: "auth")

    /// Возвращает текущий токен. Если в Keychain пусто — генерирует, сохраняет, возвращает.
    func currentToken() -> String {
        if let existing = readToken() {
            return existing
        }
        log.notice("no token in Keychain, generating fresh one")
        let fresh = Self.generateHexToken()
        writeToken(fresh)
        return fresh
    }

    /// Генерирует новый токен и перезаписывает старый.
    @discardableResult
    func regenerate() -> String {
        let fresh = Self.generateHexToken()
        writeToken(fresh)
        log.notice("token regenerated")
        return fresh
    }

    // MARK: - Keychain I/O

    private func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                log.error("SecItemCopyMatching failed: \(status, privacy: .public)")
            }
            return nil
        }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            log.error("Keychain returned non-UTF8 data")
            return nil
        }
        return token
    }

    private func writeToken(_ token: String) {
        let data = Data(token.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let updateFields: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateFields as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            log.error("SecItemUpdate failed: \(updateStatus, privacy: .public)")
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.error("SecItemAdd failed: \(addStatus, privacy: .public)")
        }
    }

    // MARK: - Generation

    private static func generateHexToken() -> String {
        var bytes = [UInt8](repeating: 0, count: tokenByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
