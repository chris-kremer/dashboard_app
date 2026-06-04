import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.chriskremer.TrackerDashboard"

    func token() -> String? {
        read(account: "apiToken")
    }

    func saveToken(_ token: String) throws {
        try save(token, account: "apiToken")
    }

    private func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecSuccess {
            return
        }

        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return
            }
            throw KeychainError.unhandledStatus(addStatus)
        }

        throw KeychainError.unhandledStatus(status)
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String,
           !accessGroup.isEmpty,
           !accessGroup.contains("$(") {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}
