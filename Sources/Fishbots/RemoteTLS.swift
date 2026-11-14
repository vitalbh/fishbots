import Foundation
import Network
import CryptoKit

/// How the aquarium and another device talk (Remote.swift on the Mac, the iPhone app): HTTP inside TLS 1.2 with a
/// pre-shared key, the 32-byte pairing key the QR code carries. Both sides build the connection here.
enum RemoteTLS {
    static let serviceType = "_fishbots._tcp"
    static let pskIdentity = "fishbots"

    /// TLS 1.2 with a pre-shared key (the same on both sides: the iPhone app builds its connection with this). The key
    /// proves who's who; ECDHE makes a fresh key for each connection, so a key that leaks one day doesn't open
    /// traffic someone recorded before (forward secrecy).
    static func parameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let psk = Data(HMAC<SHA256>.authenticationCode(for: Data("fishbots-psk-v1".utf8), using: SymmetricKey(data: key)))
        let sec = tls.securityProtocolOptions
        sec_protocol_options_add_pre_shared_key(sec, psk.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
                                                Data(pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(sec, tls_ciphersuite_t(rawValue: suite)!)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        let p = NWParameters(tls: tls, tcp: tcp)
        p.includePeerToPeer = true
        return p
    }

    /// The suite `parameters` asks for. Listing it doesn't stop a server from taking a client's plain-PSK offer,
    /// so `admits` checks what was agreed.
    static let suite = UInt16(TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256)

    /// A connection stays if it agreed on the suite with forward secrecy and comes from a private network (the home
    /// network, Tailscale, link-local): an address on the internet is refused even with the key, so a forwarded port
    /// or a global IPv6 address doesn't put the aquarium on the internet.
    static func admits(_ c: NWConnection) -> Bool {
        guard let m = c.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
              sec_protocol_metadata_get_negotiated_tls_ciphersuite(m.securityProtocolMetadata).rawValue == suite else { return false }
        guard case .hostPort(let host, _) = c.endpoint else { return false }
        return isPrivate(host)
    }

    static func isPrivate(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let a):
            return isPrivate(v4: [UInt8](a.rawValue))
        case .ipv6(let a):
            let b = [UInt8](a.rawValue)
            guard b.count == 16 else { return false }
            if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return isPrivate(v4: Array(b[12...])) }   // ::ffff:a.b.c.d
            if b[0..<15].allSatisfy({ $0 == 0 }), b[15] == 1 { return true }          // ::1
            if b[0] == 0xfe, b[1] & 0xc0 == 0x80 { return true }                      // fe80::/10, link-local
            return b[0] & 0xfe == 0xfc                                                // fc00::/7, unique local (Tailscale's fd7a:…)
        default:
            return false
        }
    }

    private static func isPrivate(v4 b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 127 || b[0] == 10 || (b[0] == 172 && b[1] & 0xf0 == 16) || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254) || (b[0] == 100 && b[1] & 0xc0 == 64)    // 100.64.0.0/10: Tailscale
    }

}
