import Foundation
import Darwin

/// Découverte automatique des enceintes KEF sur le réseau local.
///
/// Stratégie : **scan actif du sous-réseau**. On énumère les interfaces locales
/// (`getifaddrs`), on en déduit la plage d'hôtes du LAN, puis on sonde chaque IP avec
/// [`KefClient.identify()`](KefClient.swift) (un GET court sur un chemin propre à KEF).
/// Seules les vraies enceintes KEF gén. 2 répondent — contrairement à une découverte
/// Bonjour (`_airplay._tcp`) qui remonterait aussi Apple TV, HomePod, Chromecast, etc.
///
/// L'API KEF étant déjà du HTTP en clair (cf. [PROTOCOL.md](../../docs/PROTOCOL.md)),
/// ce scan ne requiert aucune permission supplémentaire au-delà de l'accès réseau local
/// déjà déclaré (`NSLocalNetworkUsageDescription`).
enum Discovery {

    /// Nombre de sondes HTTP simultanées. En dessous de la limite de descripteurs de
    /// fichiers macOS (256 par défaut), avec une marge confortable.
    static let maxConcurrentProbes = 64

    /// Délai max par sonde (s). Court : un hôte absent du LAN ne répond pas (timeout),
    /// un hôte présent mais non-KEF refuse vite la connexion.
    static let probeTimeout: TimeInterval = 1.5

    /// Plafond d'hôtes scannés (couvre tout un /24 ; borne les réseaux plus larges).
    static let maxHosts = 1024

    /// Scanne le réseau local et renvoie les enceintes KEF trouvées, triées par IP.
    /// - Parameter progress: fraction d'avancement 0…1, appelée au fil des sondes.
    static func scan(progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> [Speaker] {
        let hosts = candidateHosts()
        guard !hosts.isEmpty else { progress(1); return [] }

        let total = hosts.count
        var found: [Speaker] = []

        await withTaskGroup(of: Speaker?.self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0

            // Amorce une fenêtre glissante de sondes concurrentes.
            while inFlight < maxConcurrentProbes, let host = iterator.next() {
                group.addTask { await KefClient(host: host, timeout: probeTimeout, allowsLegacyFallback: false).identify() }
                inFlight += 1
            }

            // `group.next()` est consommé séquentiellement ici : un simple compteur suffit.
            var done = 0
            while let result = await group.next() {
                done += 1
                progress(Double(done) / Double(total))
                if let speaker = result { found.append(speaker) }
                // Relance une sonde dès qu'un slot se libère.
                if let host = iterator.next() {
                    group.addTask { await KefClient(host: host, timeout: probeTimeout, allowsLegacyFallback: false).identify() }
                }
            }
        }

        return found.sorted { $0.host.compare($1.host, options: .numeric) == .orderedAscending }
    }

    // MARK: - Calcul de la plage d'hôtes

    /// Liste dédupliquée des IP à sonder, toutes interfaces LAN confondues.
    static func candidateHosts() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for iface in localInterfaces() {
            for host in hostRange(address: iface.address, netmask: iface.netmask) {
                if seen.insert(host).inserted { result.append(host) }
            }
        }
        return result
    }

    private struct Interface { let name: String; let address: String; let netmask: String }

    /// Interfaces IPv4 actives de type Ethernet/Wi-Fi (`en*`) sur une plage privée.
    /// On écarte loopback, VPN (`utun*`), AirDrop (`awdl*`) et les adresses publiques.
    private static func localInterfaces() -> [Interface] {
        var out: [Interface] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }

        var ptr = head
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }

            guard let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }

            guard let address = ipString(sa),
                  let maskPtr = cur.pointee.ifa_netmask,
                  let netmask = ipString(maskPtr),
                  isPrivateIPv4(address) else { continue }

            out.append(Interface(name: name, address: address, netmask: netmask))
        }
        return out
    }

    /// Convertit un `sockaddr` IPv4 en chaîne pointée (« 192.168.1.42 »).
    private static func ipString(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(sa.pointee.sa_len)
        guard getnameinfo(sa, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func isPrivateIPv4(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        if p[0] == 10 { return true }                          // 10.0.0.0/8
        if p[0] == 172, (16...31).contains(p[1]) { return true } // 172.16.0.0/12
        if p[0] == 192, p[1] == 168 { return true }            // 192.168.0.0/16
        return false
    }

    /// Toutes les IP hôtes du sous-réseau (hors adresse réseau, broadcast et notre propre IP),
    /// plafonnées à `maxHosts`.
    private static func hostRange(address: String, netmask: String) -> [String] {
        guard let addr = ipv4ToUInt32(address),
              let mask = ipv4ToUInt32(netmask), mask != 0 else { return [] }
        let network = addr & mask
        let broadcast = network | ~mask
        guard broadcast > network &+ 1 else { return [] }

        var hosts: [String] = []
        var ip = network &+ 1
        while ip < broadcast && hosts.count < maxHosts {
            if ip != addr { hosts.append(uint32ToIPv4(ip)) }
            ip &+= 1
        }
        return hosts
    }

    private static func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private static func uint32ToIPv4(_ n: UInt32) -> String {
        "\((n >> 24) & 0xFF).\((n >> 16) & 0xFF).\((n >> 8) & 0xFF).\(n & 0xFF)"
    }
}
