//
//  KeychainSecurityService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import Security

protocol SecretStore {
    func read(key: String) throws -> Data?
    func write(key: String, data: Data) throws
}

enum SecretStoreError: Error { case unavailable(OSStatus) }

/// Keychain storage. X25519 keys are not Secure Enclave keys.
public final class KeychainSecurityService: Sendable, SecretStore {
    public static let shared = KeychainSecurityService()
    
    private let serviceName = "com.ScendLabs.Myaow.security"
    
    private init() {}
    
    /// Guarda un secreto criptográfico en el Keychain con protección de hardware
    @discardableResult
    public func saveSecret(key: String, data: Data) -> Bool {
        do { try write(key: key, data: data); return true } catch { return false }
    }

    func write(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError.unavailable(status) }
    }
    
    /// Recupera un secreto del Keychain
    public func loadSecret(key: String) -> Data? {
        try? read(key: key)
    }

    func read(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretStoreError.unavailable(status) }
        return data
    }
    
    /// Elimina una clave del Keychain
    @discardableResult
    public func deleteSecret(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
