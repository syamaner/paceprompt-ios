import Combine
import Foundation
import Security

// Only this component and its backend handle secret bytes. Presentation sees redacted states.
@MainActor
protocol ImportKeychainBackend {
    func contains() throws -> Bool
    func add(_ data: Data) throws
    func replace(_ data: Data) throws
    func delete() throws
    func read() throws -> Data
}

@MainActor
final class DeviceImportKeychain: ImportKeychainBackend {
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.paceprompt.workout-import.openrouter",
         kSecAttrAccount as String: "workout-import",
         kSecAttrSynchronizable as String: false]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw ImportFailure.missingCredential }
    }
    func contains() throws -> Bool {
        var query = Self.query
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }
    func add(_ data: Data) throws {
        var query = Self.query
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        try check(SecItemAdd(query as CFDictionary, nil))
    }
    func replace(_ data: Data) throws {
        // Atomic update: never delete the old item before replacement succeeds.
        try check(SecItemUpdate(Self.query as CFDictionary,
            [kSecValueData as String: data,
             kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
             kSecAttrSynchronizable as String: false] as CFDictionary))
    }
    func delete() throws {
        let status = SecItemDelete(Self.query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    func read() throws -> Data {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data else { throw ImportFailure.missingCredential }
        return data
    }
}

@MainActor
final class ImportCredentialStore: ObservableObject {
    enum State: String { case absent, present, replacing, deleting, failed }
    @Published private(set) var state: State = .absent
    @Published var entry = ""
    private let backend: any ImportKeychainBackend

    init(backend: (any ImportKeychainBackend)? = nil) { self.backend = backend ?? DeviceImportKeychain() }
    func refresh() {
        do { state = try backend.contains() ? .present : .absent }
        catch { state = .failed }
    }
    func beginReplacement() { entry = ""; state = .replacing }
    func cancelEntry() { entry = ""; refresh() }
    func save(replacing: Bool) {
        defer { entry = "" }
        guard !entry.isEmpty, entry.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { state = .failed; return }
        do {
            if replacing { try backend.replace(Data(entry.utf8)) }
            else { try backend.add(Data(entry.utf8)) }
            state = .present
        } catch { state = .failed }
    }
    func delete() {
        entry = ""
        state = .deleting
        do { try backend.delete(); state = .absent } catch { state = .failed }
    }
    func protectedDataLost() { entry = ""; state = .failed }

    // No public key getter. The only permitted release is into the fixed request.
    func authorize(_ request: inout URLRequest) throws {
        guard request.url == WorkoutImportContract.endpoint, request.httpMethod == "POST" else { throw ImportFailure.identity }
        var bytes = try backend.read()
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        guard !bytes.isEmpty, bytes.allSatisfy({ $0 >= 33 && $0 <= 126 }),
              let key = String(data: bytes, encoding: .utf8) else { throw ImportFailure.missingCredential }
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    }
}
