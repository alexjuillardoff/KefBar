import Foundation

/// Client de l'API locale HTTP/JSON des enceintes KEF de 2ᵉ génération
/// (LSX II, LS50 Wireless II, LS60, XIO).
///
/// Protocole (non officiel, rétro-ingénierié depuis l'app KEF Connect — cf. pykefcontrol) :
///   • Lecture :     GET  http://<ip>/api/getData?path=<path>&roles=value
///                   → renvoie un tableau JSON à un élément, p.ex. `[{"type":"i32_","i32_":40}]`
///   • Écriture :    POST http://<ip>/api/setData
///                   body JSON : {"path": "...", "roles": "value", "value": { ... }}
///
/// HTTP simple sur le port 80, sans TLS ni authentification. Réserve une IP fixe
/// pour l'enceinte dans ta box, sinon l'adresse changera.
struct KefClient {
    let host: String
    /// Délai max par requête. Court (~1,5 s) pendant un scan réseau, plus long en usage normal.
    let timeout: TimeInterval

    init(host: String, timeout: TimeInterval = 5) {
        self.host = host
        self.timeout = timeout
    }

    private var session: URLSession { session(timeout: timeout) }

    /// Session éphémère avec un délai d'attente explicite. Le long-poll d'événements
    /// (`pollEvents`) en a besoin : sa requête reste ouverte plus longtemps que le délai normal.
    private func session(timeout: TimeInterval) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    // MARK: - Couche bas niveau

    /// GET /api/getData — renvoie le premier objet du tableau de réponse.
    private func getData(path: String, roles: String = "value") async throws -> [String: Any] {
        var comps = URLComponents(string: "http://\(host)/api/getData")!
        comps.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: roles),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"

        let (data, resp) = try await session.data(for: req)
        try Self.validate(resp)

        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [[String: Any]], let first = array.first else {
            throw KefError.unexpectedResponse
        }
        return first
    }

    /// POST /api/setData
    private func setData(path: String, value: [String: Any], roles: String = "value") async throws {
        var req = URLRequest(url: URL(string: "http://\(host)/api/setData")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["path": path, "roles": roles, "value": value]
        )
        let (_, resp) = try await session.data(for: req)
        try Self.validate(resp)
    }

    private static func validate(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw KefError.badStatus(http.statusCode)
        }
    }

    private static func int(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    /// Construit l'URL de pochette en relevant le schéma en **HTTPS** pour les hôtes publics.
    ///
    /// App Transport Security bloque le HTTP en clair vers Internet ; or l'API KEF renvoie
    /// souvent l'`icon` en `http://` (CDN du service — p.ex. `resources.tidal.com`, qui sert
    /// aussi en HTTPS). On bascule donc ces URLs en `https://`. Les pochettes servies par
    /// l'enceinte elle-même (IP locale, AirPlay) restent en HTTP : elles sont autorisées par
    /// `NSAllowsLocalNetworking` et l'enceinte ne sert pas de HTTPS.
    private static func artworkURL(from raw: String) -> URL? {
        guard var comps = URLComponents(string: raw) else { return nil }
        if comps.scheme == "http", let host = comps.host, !isLocalHost(host) {
            comps.scheme = "https"
        }
        return comps.url
    }

    /// `true` pour un hôte du réseau local (IP privée/loopback/link-local ou `.local`),
    /// qu'il ne faut pas basculer en HTTPS.
    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.hasPrefix("127.") || host.hasPrefix("169.254.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        return false
    }

    // MARK: - Volume

    func volume() async throws -> Int {
        let obj = try await getData(path: "player:volume")
        return Self.int(obj["i32_"]) ?? 0
    }

    func setVolume(_ value: Int) async throws {
        let clamped = max(0, min(100, value))
        try await setData(path: "player:volume",
                          value: ["type": "i32_", "i32_": clamped])
    }

    // MARK: - Alimentation & source (même path)

    /// `true` si l'enceinte est allumée.
    func isPoweredOn() async throws -> Bool {
        let obj = try await getData(path: "settings:/kef/host/speakerStatus")
        return (obj["kefSpeakerStatus"] as? String) == "powerOn"
    }

    func currentSource() async throws -> Source {
        let obj = try await getData(path: "settings:/kef/play/physicalSource")
        let raw = obj["kefPhysicalSource"] as? String ?? "standby"
        return Source(apiValue: raw) ?? .standby
    }

    func setSource(_ source: Source) async throws {
        try await setData(path: "settings:/kef/play/physicalSource",
                          value: ["type": "kefPhysicalSource", "kefPhysicalSource": source.apiValue])
    }

    /// Met en veille (= éteint).
    func powerOff() async throws { try await setSource(.standby) }

    /// Allume en sélectionnant une source réelle.
    func powerOn(_ source: Source = .wifi) async throws { try await setSource(source) }

    // MARK: - Transport

    private func control(_ command: String) async throws {
        try await setData(path: "player:player/control",
                          value: ["control": command],
                          roles: "activate")
    }

    func playPause() async throws { try await control("pause") }
    func next() async throws { try await control("next") }
    func previous() async throws { try await control("previous") }

    // MARK: - Lecture en cours

    func nowPlaying() async throws -> NowPlaying? {
        let obj = try await getData(path: "player:player/data")
        let state = obj["state"] as? String
        let trackRoles = obj["trackRoles"] as? [String: Any]
        let mediaData = trackRoles?["mediaData"] as? [String: Any]
        let metaData = mediaData?["metaData"] as? [String: Any]

        let title = trackRoles?["title"] as? String
        let artist = metaData?["artist"] as? String
        let album = metaData?["album"] as? String
        let cover = (trackRoles?["icon"] as? String).flatMap(Self.artworkURL(from:))

        // Durée : aucun emplacement n'est garanti (dépend du service). On essaie les formes
        // observées, dans l'ordre, et on accepte l'absence (lecture sans durée connue).
        // Sur TIDAL (Wi-Fi), la valeur fiable est `status.duration` ; `activeResource`/
        // `resources[0]` servent de repli pour d'autres services.
        let status = obj["status"] as? [String: Any]
        let activeResource = mediaData?["activeResource"] as? [String: Any]
        let resources = mediaData?["resources"] as? [[String: Any]]
        let durationMs = Self.int(status?["duration"])
            ?? Self.int(metaData?["duration"])
            ?? Self.int(activeResource?["duration"])
            ?? Self.int(resources?.first?["duration"])

        let np = NowPlaying(title: title, artist: artist, album: album,
                            coverURL: cover, isPlaying: state == "playing",
                            durationMs: durationMs)
        return np.isEmpty ? nil : np
    }

    /// Position de lecture courante en millisecondes (`player:player/data/playTime`, `i64_`).
    func playPosition() async throws -> Int {
        let obj = try await getData(path: "player:player/data/playTime")
        return Self.int(obj["i64_"]) ?? Self.int(obj["i32_"]) ?? 0
    }

    // MARK: - Infos appareil (optionnel)

    func deviceName() async throws -> String? {
        let obj = try await getData(path: "settings:/deviceName")
        return obj["string_"] as? String
    }

    /// Adresse MAC de l'enceinte — identité stable même si l'IP change (DHCP).
    func macAddress() async throws -> String? {
        let obj = try await getData(path: "settings:/system/primaryMacAddress")
        return obj["string_"] as? String
    }

    // MARK: - Push temps réel (long-poll d'événements)

    /// Chemins auxquels on s'abonne : sous-ensemble `itemWithValue` de ce qu'envoie l'app KEF
    /// Connect (charge utile éprouvée). On n'exploite pas le contenu des évènements — ils
    /// servent de signal de réveil ; les valeurs faisant foi sont relues via les accesseurs
    /// typés. Couvre volume, lecture en cours et mode de lecture ; l'alimentation/source change
    /// presque toujours en même temps que `player/data`, et le `pollEvents` rafraîchit de toute
    /// façon à intervalle régulier.
    private static let eventSubscriptions: [[String: String]] = [
        ["path": "player:volume", "type": "itemWithValue"],
        ["path": "player:player/data", "type": "itemWithValue"],
        ["path": "settings:/mediaPlayer/playMode", "type": "itemWithValue"],
        ["path": "settings:/kef/host/maximumVolume", "type": "itemWithValue"],
        ["path": "settings:/deviceName", "type": "itemWithValue"],
    ]

    /// S'abonne aux changements d'état (`POST /api/event/modifyQueue`) et renvoie l'identifiant
    /// de file. La réponse est l'UUID **entre guillemets** : on les retire.
    func subscribeToEvents() async throws -> String {
        var req = URLRequest(url: URL(string: "http://\(host)/api/event/modifyQueue")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["subscribe": Self.eventSubscriptions, "unsubscribe": []]
        )
        let (data, resp) = try await session.data(for: req)
        try Self.validate(resp)
        guard let raw = String(data: data, encoding: .utf8) else { throw KefError.unexpectedResponse }
        let id = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
        guard !id.isEmpty else { throw KefError.unexpectedResponse }
        return id
    }

    /// Long-poll : `GET /api/event/pollQueue` bloque jusqu'à `timeout` secondes et renvoie les
    /// éléments modifiés. On renvoie `true` si au moins un changement a été signalé (`false` si
    /// le délai a expiré sans rien). La requête tolère le blocage (marge au-dessus du `timeout`).
    func pollEvents(queueId: String, timeout seconds: Int) async throws -> Bool {
        var comps = URLComponents(string: "http://\(host)/api/event/pollQueue")!
        comps.queryItems = [
            URLQueryItem(name: "queueId", value: queueId),
            URLQueryItem(name: "timeout", value: String(seconds)),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        let (data, resp) = try await session(timeout: TimeInterval(seconds) + 5).data(for: req)
        try Self.validate(resp)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return !array.isEmpty
        }
        return false
    }

    // MARK: - Découverte

    /// Sonde l'hôte : renvoie un `Speaker` si c'est bien une enceinte KEF gén. 2, sinon `nil`.
    ///
    /// Le test discriminant est `speakerStatus`, un chemin **propre à KEF** : un serveur HTTP
    /// quelconque sur le port 80 renverra autre chose (ou rien de parsable) et `getData`
    /// lèvera, ce qui nous fait répondre `nil`. Sur un hit confirmé seulement (rare), on va
    /// chercher le nom et la MAC.
    func identify() async -> Speaker? {
        guard (try? await isPoweredOn()) != nil else { return nil }
        let name = (try? await deviceName()).flatMap { $0 }
        let mac = (try? await macAddress()).flatMap { $0 }
        return Speaker(host: host, name: name ?? Speaker.defaultName, mac: mac)
    }
}
