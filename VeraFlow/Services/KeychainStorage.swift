import Foundation
import Security

/// Tamper-resistant Keychain storage helper for persisting purchase entitlements and free trial quotas (§13).
public final class KeychainStorage: Sendable {
    private let service: String
    
    public init(service: String = "com.veraflow.app.security") {
        self.service = service
    }
    
    // MARK: - Integer Operations
    
    public func integer(forKey key: String) -> Int? {
        guard let data = data(forKey: key) else { return nil }
        guard data.count == MemoryLayout<Int>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Int.self) }
    }
    
    public func set(_ value: Int, forKey key: String) {
        var val = value
        let data = Data(bytes: &val, count: MemoryLayout<Int>.size)
        set(data, forKey: key)
    }
    
    // MARK: - Generic Data Operations
    
    public func data(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
    
    public func set(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newQuery as CFDictionary, nil)
        }
    }
    
    public func remove(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
