import Foundation
import Network
import Security
import CryptoKit

enum Transport {
    // TLS-PSK avoids self-signed certificate trust overrides. The user shares a
    // random secret out of band; it is never advertised through Bonjour.
    static func parameters(secret: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = Data(SHA256.hash(data: Data(("ThunderAudio-TLS-v1:" + secret).utf8)))
        let identity = Data("ThunderAudio-v1".utf8)
        let keyBytes = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityBytes = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, keyBytes as __DispatchData, identityBytes as __DispatchData)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0x00A8)!)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}
