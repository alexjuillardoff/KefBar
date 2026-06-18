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

    private var session: URLSession {
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
        let cover = (trackRoles?["icon"] as? String).flatMap(URL.init(string:))

        let np = NowPlaying(title: title, artist: artist, album: album,
                            coverURL: cover, isPlaying: state == "playing")
        return np.isEmpty ? nil : np
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
