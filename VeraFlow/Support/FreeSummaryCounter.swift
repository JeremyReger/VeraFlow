import Foundation
import Security

/// The free-summary count (SPEC §13.2), kept in the Keychain so it survives a reinstall, mirrored
/// in `UserDefaults`. The larger of the two wins, so neither store can be used to reset it.
struct FreeSummaryCounter: Sendable {
    var service = "com.jeremyreger.veraflow.freeSummaries"
    var account = "count"
    var defaults: UserDefaults = .standard
    var defaultsKey = "purchases.freeSummariesUsed"

    func value() -> Int {
        max(keychainValue() ?? 0, defaults.integer(forKey: defaultsKey))
    }

    func increment() {
        set(value() + 1)
    }

    func set(_ count: Int) {
        defaults.set(count, forKey: defaultsKey)
        writeKeychain(count)
    }

    /// Test/support control: clears both stores.
    func reset() {
        defaults.removeObject(forKey: defaultsKey)
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: Keychain

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainValue() -> Int? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return Int(text)
    }

    private func writeKeychain(_ count: Int) {
        let data = Data(String(count).utf8)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        // Not synchronized to iCloud, readable after first unlock (the pipeline runs in the background).
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }
}
