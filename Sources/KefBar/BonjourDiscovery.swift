import Foundation

/// Découverte **Bonjour** des enceintes KEF — complément du scan actif port-80 de
/// [`Discovery`](Discovery.swift).
///
/// Pourquoi ce complément : une enceinte KEF gén. 2 **en veille endort son API HTTP** (port 80
/// ne répond plus, la connexion expire), si bien que le scan actif ne la voit plus du tout.
/// Or l'enceinte **reste annoncée en AirPlay** (`_airplay._tcp`) même en veille, et son
/// enregistrement TXT porte tout ce qu'il faut :
///
///   `manufacturer=KEF   model=LSX II   deviceid=84:17:15:04:43:49`
///
/// On filtre donc sur `manufacturer == KEF` (ce qui écarte Apple TV / HomePod / Chromecast,
/// la raison pour laquelle Bonjour avait été initialement écarté), et on récupère **nom +
/// MAC + IP**. La MAC permet de **reconnecter une enceinte connue par son identité stable**
/// même injoignable — là où le scan port-80 échoue.
@MainActor
final class BonjourDiscovery: NSObject {

    /// Une enceinte KEF repérée via Bonjour (annoncée même en veille).
    struct Result {
        let host: String   // IPv4 résolue
        let name: String   // modèle annoncé (« LSX II »…)
        let mac: String    // `deviceid` du TXT (= adresse MAC)
    }

    private let browser = NetServiceBrowser()
    /// Services en cours de résolution : référence forte le temps du `resolve`.
    private var resolving: Set<NetService> = []
    /// Résultats dédupliqués par MAC normalisée.
    private var found: [String: Result] = [:]
    private var continuation: CheckedContinuation<[Result], Never>?
    private var timeoutTask: Task<Void, Never>?

    /// Parcourt le réseau pendant `timeout` secondes et renvoie les enceintes KEF annoncées.
    /// Sans danger si aucune n'est trouvée (renvoie un tableau vide à l'expiration).
    func discover(timeout: TimeInterval = 3) async -> [Result] {
        await withCheckedContinuation { (cont: CheckedContinuation<[Result], Never>) in
            self.continuation = cont
            self.browser.delegate = self
            self.browser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish()
            }
        }
    }

    /// Clôt la découverte : arrête tout et renvoie les résultats (idempotent).
    private func finish() {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        browser.stop()
        resolving.forEach { $0.stop() }
        resolving.removeAll()
        cont.resume(returning: Array(found.values))
    }
}

// MARK: - Parcours + résolution

extension BonjourDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.insert(service)                 // garde une référence forte pendant la résolution
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer { sender.stop(); resolving.remove(sender) }
        guard let txtData = sender.txtRecordData() else { return }
        let txt = NetService.dictionary(fromTXTRecord: txtData)
        func value(_ key: String) -> String? { txt[key].flatMap { String(data: $0, encoding: .utf8) } }

        // Discriminant : seules les enceintes KEF passent (écarte Apple TV, HomePod, etc.).
        guard let manufacturer = value("manufacturer"),
              manufacturer.caseInsensitiveCompare("KEF") == .orderedSame,
              let mac = value("deviceid"),
              let key = Speaker.normalizeMac(mac),
              let ip = Self.ipv4(from: sender.addresses) else { return }

        let name = value("model") ?? sender.name
        found[key] = Result(host: ip, name: name, mac: mac)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        sender.stop()
        resolving.remove(sender)
    }

    /// Première adresse IPv4 (« 192.168.x.y ») d'un service résolu.
    private static func ipv4(from addresses: [Data]?) -> String? {
        guard let addresses else { return nil }
        for data in addresses {
            let ip: String? = data.withUnsafeBytes { raw in
                guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                      sa.pointee.sa_family == UInt8(AF_INET) else { return nil }
                var addr = raw.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buf)
            }
            if let ip { return ip }
        }
        return nil
    }
}
