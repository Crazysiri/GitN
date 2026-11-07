import Foundation
import Observation
import Security

protocol CredentialBackend {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}

struct KeychainCredentialBackend: CredentialBackend {
    // Stable across local app names; never include credentials in errors/logs.
    private let service = "com.gitn.hosted-review"

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func read(account: String) throws -> String? {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return value
    }

    func write(_ value: String, account: String) throws {
        let changes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query(account) as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(account)
            attributes[kSecValueData as String] = Data(value.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unable to access credential") (\(status))"
        }
    }
}

@MainActor @Observable
final class HostedCredentialStore {
    static let shared = HostedCredentialStore()
    enum Provider: String { case github, gitlab }

    private let backend: any CredentialBackend
    private let defaults: UserDefaults
    private(set) var errorMessage: String?

    init(backend: any CredentialBackend = KeychainCredentialBackend(), defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        // No migration: the single user will re-enter credentials.
        for provider in [Provider.github, .gitlab] {
            defaults.removeObject(forKey: "GitN.\(provider.rawValue)Token")
        }
    }

    func token(for provider: Provider) -> String {
        do { return try backend.read(account: provider.rawValue) ?? "" }
        catch { errorMessage = error.localizedDescription; return "" }
    }

    func save(_ value: String, for provider: Provider) throws {
        do {
            if value.isEmpty { try backend.delete(account: provider.rawValue) }
            else { try backend.write(value, account: provider.rawValue) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
