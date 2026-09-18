import Foundation
import Security

/// Менеджер аутентификации FTP с хранением пароля в Keychain
public final class FTPAuthManager: @unchecked Sendable {
    public static let shared = FTPAuthManager()
    
    private let serviceName = "com.nikonzbridge.ftp"
    private let usernameKey = "nikon_ftp_username"
    private let passwordAccountKey = "nikon_ftp_password"
    
    private let lock = NSLock()
    private var inMemoryUsername: String = "nikon"
    private var inMemoryPassword: String = ""
    
    public init() {
        loadCredentials()
    }
    
    /// Загрузка учетных данных из Keychain и UserDefaults
    private func loadCredentials() {
        lock.lock()
        defer { lock.unlock() }
        
        // 1. Загрузка логина
        if let savedUser = UserDefaults.standard.string(forKey: usernameKey), !savedUser.isEmpty {
            inMemoryUsername = savedUser
        } else {
            inMemoryUsername = "nikon"
            UserDefaults.standard.set(inMemoryUsername, forKey: usernameKey)
        }
        
        // 2. Загрузка пароля из Keychain
        if let keychainPass = readPasswordFromKeychain(), !keychainPass.isEmpty {
            inMemoryPassword = keychainPass
        } else {
            // Генерация начального пароля (удобного для ввода на камере)
            let generated = generateRandomPassword()
            inMemoryPassword = generated
            savePasswordToKeychain(generated)
        }
    }
    
    /// Получение текущих учетных данных
    public func getCredentials() -> (username: String, password: String) {
        lock.lock()
        defer { lock.unlock() }
        return (inMemoryUsername, inMemoryPassword)
    }
    
    /// Проверка соответствия введенного логина и пароля
    public func validate(username: String, password: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return username == inMemoryUsername && password == inMemoryPassword
    }
    
    /// Обновление имени пользователя
    public func updateUsername(_ newUsername: String) {
        let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        inMemoryUsername = trimmed
        lock.unlock()
        UserDefaults.standard.set(trimmed, forKey: usernameKey)
    }
    
    /// Обновление пароля в Keychain
    public func updatePassword(_ newPassword: String) {
        guard !newPassword.isEmpty else { return }
        lock.lock()
        inMemoryPassword = newPassword
        lock.unlock()
        savePasswordToKeychain(newPassword)
    }
    
    /// Генерация нового случайного пароля
    @discardableResult
    public func regeneratePassword() -> String {
        let newPass = generateRandomPassword()
        updatePassword(newPass)
        return newPass
    }
    
    /// Надежный 8-символьный пароль из цифр и букв, удобный для ввода в камере
    public func generateRandomPassword() -> String {
        let digits = "0123456789"
        let letters = "abcdefghjkmnpqrstuvwxyz" // исключены похожие символы (i, l, o)
        var result = ""
        for _ in 0..<4 {
            if let d = digits.randomElement() { result.append(d) }
        }
        for _ in 0..<4 {
            if let l = letters.randomElement() { result.append(l) }
        }
        return String(result.shuffled())
    }
    
    // MARK: - Keychain Operations
    
    private func readPasswordFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: passwordAccountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let pass = String(data: data, encoding: .utf8) else {
            return nil
        }
        return pass
    }
    
    private func savePasswordToKeychain(_ password: String) {
        guard let data = password.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: passwordAccountKey
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}
