import Foundation
import Security

actor MailAccountCredentialsStore {
    private let service = "com.mailstrea.mail.account"

    func loadCredentials(for account: MailAccount) throws -> MailAccountCredentials? {
        let query = keychainQuery(for: account.id)
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return nil
        default:
            throw MailServiceError.keychainFailure(status)
        }

        guard let data = result as? Data,
              let secret = String(data: data, encoding: .utf8),
              secret.isEmpty == false
        else {
            return nil
        }

        return MailAccountCredentials(
            accountID: account.id,
            emailAddress: account.emailAddress,
            secret: secret
        )
    }

    func saveCredentials(accountID: UUID, secret: String) throws {
        let normalizedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSecret.isEmpty == false else {
            throw MailServiceError.missingAuthorizationCode
        }

        let data = Data(normalizedSecret.utf8)
        let query = keychainQuery(for: accountID)
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var createQuery = query
            createQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw MailServiceError.keychainFailure(addStatus)
            }
        default:
            throw MailServiceError.keychainFailure(updateStatus)
        }
    }

    func deleteCredentials(accountID: UUID) throws {
        let status = SecItemDelete(keychainQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MailServiceError.keychainFailure(status)
        }
    }

    private func keychainQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
    }
}
