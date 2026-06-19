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

// MARK: - Résolution de l'endpoint API (schéma + port) d'une enceinte connue

extension Discovery {

    /// Plage de ports balayée pour retrouver l'API. **1…10000** : couvre tous les ports d'API
    /// réalistes (80, 4430, 8000/8080/8443…) ; un balayage 1…65535 serait impraticable car
    /// l'enceinte **filtre** (ignore) ses ports fermés — chacun consommerait alors tout le délai.
    static let portScanRange: ClosedRange<Int> = 1...10000
    /// Sockets ouverts simultanément par lot de `poll`. Sous la limite de descripteurs relevée.
    static let portScanBatch = 800
    /// Délai d'une vague de connexions (s). Un port ouvert répond en quelques ms ; ce délai ne
    /// pèse que sur les ports filtrés (silencieux), traités en masse par lot.
    static let portScanTimeout: TimeInterval = 0.6

    /// Résout l'endpoint de l'API KEF pour une **IP déjà connue** : on essaie d'abord les
    /// endpoints **connus** (`https:4430`, `http:80`), puis, en dernier recours, on **balaie les
    /// ports** de l'enceinte et on teste l'API KEF sur chaque port ouvert (HTTPS puis HTTP).
    /// Renvoie le premier endpoint qui répond comme une enceinte KEF, ou `nil` (injoignable).
    ///
    /// Survit ainsi à un futur déplacement de l'API vers un autre port — comme le passage
    /// `http:80` → `https:4430` du firmware 2024.
    static func resolveEndpoint(host: String, timeout: TimeInterval = 2) async -> KefEndpoint? {
        guard !host.isEmpty else { return nil }
        // 1. Endpoints connus, dans l'ordre de préférence (instantané s'ils répondent).
        if let hit = await firstKefEndpoint(host: host,
                                            candidates: [.modern, .legacy], timeout: timeout) {
            return hit
        }
        // 2. Repli : ports réellement ouverts de l'hôte, en HTTPS puis HTTP, en ignorant ceux
        //    déjà testés à l'étape 1.
        let open = await openPorts(host: host)
        let candidates = open
            .filter { $0 != KefEndpoint.modern.port && $0 != KefEndpoint.legacy.port }
            .flatMap { [KefEndpoint(scheme: "https", port: $0), KefEndpoint(scheme: "http", port: $0)] }
        return await firstKefEndpoint(host: host, candidates: candidates, timeout: timeout)
    }

    /// Premier endpoint de `candidates` qui répond comme une enceinte KEF (chemin `speakerStatus`
    /// parsable). Essayés en série pour respecter l'ordre de préférence (HTTPS avant HTTP).
    private static func firstKefEndpoint(host: String, candidates: [KefEndpoint],
                                         timeout: TimeInterval) async -> KefEndpoint? {
        for ep in candidates {
            let client = KefClient(host: host, timeout: timeout, endpoint: ep)
            if (try? await client.isPoweredOn()) != nil { return ep }
        }
        return nil
    }

    /// Ports TCP **ouverts** de l'hôte. Technique du **`poll` groupé** : par lots de
    /// `portScanBatch`, on ouvre des sockets non bloquants, on lance toutes les connexions, puis
    /// on attend l'ensemble en **un seul `poll`** (un seul thread, pas d'explosion de threads).
    /// Tout le balayage tourne sur une file de fond pour ne pas bloquer le pool coopératif Swift.
    static func openPorts(host: String, range: ClosedRange<Int> = portScanRange) async -> [Int] {
        await withCheckedContinuation { (cont: CheckedContinuation<[Int], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: scanPorts(host: host, range: range))
            }
        }
    }

    private static func scanPorts(host: String, range: ClosedRange<Int>) -> [Int] {
        var base = sockaddr_in()
        base.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &base.sin_addr) == 1 else { return [] }
        raiseDescriptorLimit()

        var open: [Int] = []
        var start = range.lowerBound
        while start <= range.upperBound {
            let end = min(start + portScanBatch - 1, range.upperBound)
            open += connectBatch(base: base, ports: start...end)
            start = end + 1
        }
        return open.sorted()
    }

    /// Lance les connexions non bloquantes d'un lot de ports puis les attend en un seul `poll`.
    private static func connectBatch(base: sockaddr_in, ports: ClosedRange<Int>) -> [Int] {
        var open: [Int] = []
        var pfds: [pollfd] = []
        var portOf: [Int32: Int] = [:]

        for p in ports {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            if fd < 0 { continue }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
            var addr = base
            addr.sin_port = in_port_t(p).bigEndian
            let rc = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if rc == 0 { open.append(p); close(fd); continue }       // connecté tout de suite
            if errno != EINPROGRESS { close(fd); continue }          // refusé immédiatement
            portOf[fd] = p
            pfds.append(pollfd(fd: fd, events: Int16(POLLOUT), revents: 0))
        }

        if !pfds.isEmpty {
            _ = poll(&pfds, nfds_t(pfds.count), Int32(portScanTimeout * 1000))
            for pfd in pfds where (pfd.revents & Int16(POLLOUT)) != 0 {
                var soErr: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(pfd.fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
                if soErr == 0, let p = portOf[pfd.fd] { open.append(p) }
            }
        }
        portOf.keys.forEach { close($0) }
        return open
    }

    /// Relève la limite douce de descripteurs (souvent 256 par défaut) pour tenir un lot de
    /// `portScanBatch` sockets simultanés. Best-effort.
    private static func raiseDescriptorLimit() {
        var lim = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &lim) == 0 else { return }
        let target = rlim_t(portScanBatch + 256)
        if lim.rlim_cur < target {
            lim.rlim_cur = min(target, lim.rlim_max)
            _ = setrlimit(RLIMIT_NOFILE, &lim)
        }
    }
}
