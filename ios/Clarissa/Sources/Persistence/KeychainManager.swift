import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "dev.rye.Clarissa", category: "KeychainManager")

/// Manages secure storage of sensitive data in the iOS Keychain
final class KeychainManager: @unchecked Sendable {
    static let shared = KeychainManager()
    
    private let service = "dev.rye.Clarissa"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Store a string value securely in the Keychain
    func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        // Delete existing item first
        try? delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to save to Keychain: \(status)")
            throw KeychainError.saveFailed(status)
        }
        
        logger.info("Saved value for key: \(key)")
    }
    
    /// Retrieve a string value from the Keychain
    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    /// Delete a value from the Keychain
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete from Keychain: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Check if a key exists in the Keychain
    func exists(key: String) -> Bool {
        get(key: key) != nil
    }
    
    /// Clear all items for this service
    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        
        logger.info("Cleared all Keychain items")
    }
}

// MARK: - Keychain Keys

extension KeychainManager {
    enum Keys {
        static let openRouterApiKey = "openRouterApiKey"
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for Keychain storage"
        case .saveFailed(let status):
            return "Failed to save to Keychain (error: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (error: \(status))"
        case .notFound:
            return "Item not found in Keychain"
        }
    }
}

