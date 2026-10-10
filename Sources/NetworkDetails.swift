import Foundation
import Network
import SystemConfiguration
import Darwin

enum NetworkDetails {
    static func serviceNames() -> [String: String] {
        guard let prefs = SCPreferencesCreate(nil, "ThunderAudio" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return [:] }
        var result: [String: String] = [:]
        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            result[bsd] = (SCNetworkServiceGetName(service) as String?) ?? bsd
        }
        return result
    }
    static func thunderboltNames() -> Set<String> {
        guard let prefs = SCPreferencesCreate(nil, "ThunderAudio" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return [] }
        var names = Set<String>()
        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let label = ((SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? "").lowercased()
            if label.contains("thunderbolt") || label.contains("雷雳") || label.contains("雷電") || label.contains("雷电") { names.insert(bsd) }
        }
        return names
    }
    static func addresses() -> [String: [String]] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [:] }
        defer { freeifaddrs(head) }
        var result: [String: [String]] = [:]
        var current = head
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var value = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &value, socklen_t(value.count), nil, 0, NI_NUMERICHOST) == 0 {
                result[String(cString: item.pointee.ifa_name), default: []].append(String(cString: value))
            }
        }
        return result
    }
    static func label(_ interface: NWInterface) -> String {
        let name = serviceNames()[interface.name] ?? String(describing: interface.type)
        let ips = addresses()[interface.name]?.joined(separator: ", ") ?? "无 IPv4"
        return "\(interface.name) · \(name) · \(ips)"
    }
}
