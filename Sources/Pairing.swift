import Foundation
import Security
import Network

protocol CredentialStore {
    func read(account: String) throws -> String?
    func save(_ secret: String, account: String) throws
    func remove(account: String) throws
}
struct KeychainCredentials: CredentialStore {
    var service = "local.thunderaudio.pairing"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else { throw NSError(domain: "钥匙串记录格式错误", code: 1) }
        return secret
    }
    func save(_ secret: String, account: String) throws {
        let value = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(query(account) as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = Data(secret.utf8)
            q[kSecAttrLabel as String] = "ThunderAudio 配对口令"
            // macOS login keychain, with normal per-app access controls; no iCloud sync.
            try check(SecItemAdd(q as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: "ThunderAudio.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: (SecCopyErrorMessageString(status, nil) as String?) ?? "钥匙串访问失败 (\(status))"])
        }
    }
}
enum Pairing {
    static func isValid(_ secret: String) -> Bool {
        let sixDigits = secret.utf8.count == 6 && secret.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        return sixDigits || (16...128).contains(secret.utf8.count)
    }
    static func newPIN() -> String { String(format: "%06d", Int.random(in: 0...999999)) }
}
struct DiscoveredPeer: Identifiable {
    let name: String
    let domain: String
    var id: String { Data((name + "\0" + domain).utf8).base64EncodedString() }
    var endpoint: NWEndpoint { .service(name: name, type: "_thunderaudio._tcp", domain: domain, interface: nil) }
    static func decode(_ id: String) -> DiscoveredPeer? {
        guard let data = Data(base64Encoded: id), let value = String(data: data, encoding: .utf8) else { return nil }
        let parts = value.components(separatedBy: "\0")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return DiscoveredPeer(name: parts[0], domain: parts[1])
    }
    static func collect(_ results: Set<NWBrowser.Result>) -> [DiscoveredPeer] {
        var unique: [String: DiscoveredPeer] = [:]
        for result in results {
            guard case .service(let name, _, let domain, _) = result.endpoint else { continue }
            let peer = DiscoveredPeer(name: name, domain: domain)
            unique[peer.id] = peer
        }
        return unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
