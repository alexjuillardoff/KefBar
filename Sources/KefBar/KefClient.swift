import Foundation

/// Client de l'API locale HTTP/JSON des enceintes KEF de 2ᵉ génération
/// (LSX II, LS50 Wireless II, LS60, XIO).
///
/// Protocole (non officiel, rétro-ingénierié depuis l'app KEF Connect — cf. pykefcontrol) :
///   • Lecture :     GET  <base>/api/getData?path=<path>&roles=value
///                   → renvoie un tableau JSON à un élément, p.ex. `[{"type":"i32_","i32_":40}]`
///   • Écriture :    POST <base>/api/setData
///                   body JSON : {"path": "...", "roles": "value", "value": { ... }}
///
/// **Transport** : depuis le firmware 2024 (`p20.x`), `<base>` est `https://<ip>:4430`
/// (TLS, certificat **auto-signé** KEF accepté par `KefTLSTrustDelegate`). Les firmwares
/// antérieurs servaient en clair sur `http://<ip>:80` ; on s'y replie automatiquement quand
/// le HTTPS ne se connecte pas (`allowsLegacyFallback`). Aucune authentification dans les deux
/// cas. Réserve une IP fixe pour l'enceinte dans ta box, sinon l'adresse changera.
struct KefClient {
    let host: String
    /// Délai max par requête. Court (~1,5 s) pendant un scan réseau, plus long en usage normal.
    let timeout: TimeInterval
    /// Transports à essayer **dans l'ordre**, avec repli au transport suivant sur échec de
    /// connexion. Par défaut : moderne (`https:4430`) puis historique (`http:80`). Quand
    /// l'endpoint a été **résolu** pour l'enceinte (cf. [`Discovery.resolveEndpoint`](Discovery.swift)),
    /// la liste se réduit à ce seul endpoint — y compris un port non standard découvert par scan.
    let transports: [KefEndpoint]

    /// - Parameters:
    ///   - endpoint: endpoint **résolu** de l'enceinte (schéma+port). Fourni → seul transport essayé.
    ///   - allowsLegacyFallback: à défaut d'`endpoint`, autorise le repli `http:80` après `https:4430`.
    ///     Désactivé pendant le scan réseau (sondes uniques) ; les firmwares anciens sont repérés
    ///     par Bonjour puis pilotés via ce repli ou un endpoint résolu.
    init(host: String, timeout: TimeInterval = 5,
         endpoint: KefEndpoint? = nil, allowsLegacyFallback: Bool = true) {
        self.host = host
        self.timeout = timeout
        if let endpoint {
            self.transports = [endpoint]
        } else {
            self.transports = allowsLegacyFallback ? [.modern, .legacy] : [.modern]
        }
    }

    /// Session partagée acceptant le certificat auto-signé de l'enceinte (cf. `KefTLSTrustDelegate`).
    /// Le délai d'attente est fixé **par requête** (`URLRequest.timeoutInterval`) — nécessaire car
    /// le long-poll d'évènements (`pollEvents`) reste ouvert bien plus longtemps que les autres appels.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: KefTLSTrustDelegate(), delegateQueue: nil)
    }()

    // MARK: - Couche bas niveau

    /// URL `/api/<path>` pour un transport donné.
    private func url(_ apiPath: String, query: [URLQueryItem]?, transport: KefEndpoint) -> URL {
        var comps = URLComponents()
        comps.scheme = transport.scheme
        comps.host = host
        comps.port = transport.port
        comps.path = "/api/\(apiPath)"
        comps.queryItems = query
        return comps.url!
    }

    /// Exécute une requête en essayant les `transports` **dans l'ordre** : sur échec **de
    /// connexion** (port fermé / injoignable / TLS), on passe au transport suivant ; sur le
    /// dernier, l'erreur remonte. Une erreur HTTP (statut ≥ 400) **ne** déclenche **pas** de repli
    /// (elle n'apparaît qu'à la validation, pas ici). `build` peut régler méthode/corps/en-têtes
    /// et écraser le délai par défaut (utile pour le long-poll).
    private func send(apiPath: String, query: [URLQueryItem]? = nil,
                      build: (inout URLRequest) -> Void = { _ in }) async throws -> (Data, URLResponse) {
        func request(_ transport: KefEndpoint) -> URLRequest {
            var req = URLRequest(url: url(apiPath, query: query, transport: transport))
            req.timeoutInterval = timeout
            build(&req)
            return req
        }
        var lastError: Error = URLError(.cannotConnectToHost)
        for transport in transports {
            do {
                return try await Self.session.data(for: request(transport))
            } catch let error as URLError where Self.isConnectionFailure(error) {
                lastError = error   // tente le transport suivant, s'il en reste
            }
        }
        throw lastError
    }

    /// Vraie pour une erreur de **connexion** (et non un statut HTTP) : justifie l'essai du transport suivant.
    private static func isConnectionFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .timedOut, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    /// GET /api/getData — renvoie le premier objet du tableau de réponse.
    private func getData(path: String, roles: String = "value") async throws -> [String: Any] {
        let (data, resp) = try await send(apiPath: "getData", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: roles),
        ])
        try Self.validate(resp)

        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [[String: Any]], let first = array.first else {
            throw KefError.unexpectedResponse
        }
        return first
    }

    /// GET /api/getData mais renvoie **tout** le tableau de réponse (pas seulement le premier
    /// objet). Utile pour les lectures `roles=rows` (file d'attente, notifications) dont la
    /// réponse est une liste d'éléments. Renvoie un tableau vide si le corps n'est pas une liste.
    private func getDataArray(path: String, roles: String = "value") async throws -> [[String: Any]] {
        let (data, resp) = try await send(apiPath: "getData", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: roles),
        ])
        try Self.validate(resp)

        let json = try JSONSerialization.jsonObject(with: data)
        // Réponse `rows` tolérante : une file vide renvoie `[null]` (vérifié sur LSX II), et une
        // file remplie peut mêler éléments `null` et objets. On ne garde que les objets.
        guard let array = json as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }
    }

    /// POST /api/setData
    private func setData(path: String, value: [String: Any], roles: String = "value") async throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["path": path, "roles": roles, "value": value]
        )
        let (_, resp) = try await send(apiPath: "setData") { req in
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
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

    /// Extrait un entier quelle que soit la largeur typée renvoyée par l'enceinte. Vérifié sur
    /// LSX II : `volumeStep` arrive en **`i16_`**, pas `i32_` — d'où ce balayage des clés.
    private static func anyInt(_ obj: [String: Any]) -> Int? {
        for key in ["i32_", "i16_", "i64_", "i8_", "u32_", "u16_", "u8_", "u64_"] {
            if let v = int(obj[key]) { return v }
        }
        return nil
    }

    /// Extrait la chaîne d'un objet réponse, tolérant à la forme : `string_` explicite, sinon
    /// la valeur typée pointée par `type` (p.ex. `{"type":"playMode","playMode":"shuffle"}`).
    private static func string(_ obj: [String: Any]) -> String? {
        if let s = obj["string_"] as? String { return s }
        if let type = obj["type"] as? String, let s = obj[type] as? String { return s }
        return nil
    }

    /// Extrait la valeur typée pointée par `type` quand c'est un objet imbriqué
    /// (p.ex. `kef:eqProfile/v2` → `{"type":"kefEqProfileV2","kefEqProfileV2":{ … profil … }}`).
    /// Renvoie aussi le `type` d'enveloppe.
    private static func typedObject(_ obj: [String: Any]) -> (type: String, value: [String: Any])? {
        guard let type = obj["type"] as? String, let value = obj[type] as? [String: Any] else { return nil }
        return (type, value)
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
        return Self.anyInt(obj) ?? 0
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

    private func control(_ command: String, extra: [String: Any] = [:]) async throws {
        var value: [String: Any] = ["control": command]
        value.merge(extra) { _, new in new }
        try await setData(path: "player:player/control",
                          value: value,
                          roles: "activate")
    }

    func playPause() async throws { try await control("pause") }
    func next() async throws { try await control("next") }
    func previous() async throws { try await control("previous") }

    /// Déplace la tête de lecture à `ms` millisecondes depuis le début de la piste (clic ou
    /// glissement sur la barre de progression).
    ///
    /// ⚠️ **Non vérifié sur matériel.** On emploie la **forme étendue** de la commande de
    /// transport repérée par `m-lange` (`{"control":"<cmd>", "<type>":"<value>"}`), ici
    /// `{"control":"seek","i64_":<ms>}` — cohérente avec la position lue en `i64_` (ms). Selon le
    /// service source et le firmware, le seek peut être refusé : l'erreur remonte alors à l'appelant.
    func seek(toMs ms: Int) async throws {
        try await control("seek", extra: ["i64_": max(0, ms)])
    }

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
        return Self.anyInt(obj) ?? 0
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

    // MARK: - Limite de volume

    /// Volume maximum configuré sur l'enceinte (`settings:/kef/host/maximumVolume`). Sert à
    /// borner le slider pour ne pas dépasser le plafond réglé dans KEF Connect.
    func maximumVolume() async throws -> Int? {
        let obj = try await getData(path: "settings:/kef/host/maximumVolume")
        return Self.anyInt(obj)
    }

    /// Pas de volume configuré sur l'enceinte (`settings:/kef/host/volumeStep`). Lecture
    /// disponible mais **non utilisée par l'UI** : les boutons −/+ vont par pas de 1.
    /// Vérifié sur LSX II : renvoyé en `i16_`.
    func volumeStep() async throws -> Int? {
        let obj = try await getData(path: "settings:/kef/host/volumeStep")
        return Self.anyInt(obj)
    }

    // MARK: - Mode de lecture (répétition / aléatoire)

    /// Lit le mode de lecture (`settings:/mediaPlayer/playMode`). Vérifié sur LSX II : la valeur
    /// est typée **`playerPlayMode`** (p.ex. `"normal"`). Lecture tolérante.
    func playMode() async throws -> PlayMode {
        let obj = try await getData(path: "settings:/mediaPlayer/playMode")
        return PlayMode(apiValue: Self.string(obj) ?? "normal")
    }

    /// Écrit le mode de lecture (enveloppe `playerPlayMode`, confirmée par la lecture).
    /// ⚠️ Vérifié sur LSX II : l'écriture est **refusée (HTTP 401) quand rien ne joue** —
    /// elle ne s'applique qu'avec une session de lecture active. Les libellés des valeurs autres
    /// que `normal` restent à confirmer en lecture.
    func setPlayMode(_ mode: PlayMode) async throws {
        try await setData(path: "settings:/mediaPlayer/playMode",
                          value: ["type": "playerPlayMode", "playerPlayMode": mode.apiValue])
    }

    // MARK: - DSP / Profil EQ (lecture seule)

    /// Lit le profil DSP de l'enceinte. Chemin vérifié sur LSX II : **`kef:eqProfile/v2`**
    /// (type `kefEqProfileV2`) — `kef:eqProfile` (sans `/v2`) **n'existe pas**. Renvoie l'objet
    /// interne (deskMode, wallMode, phaseCorrection, bassExtension, trebleAmount, profileName…).
    ///
    /// ⚠️ **Lecture seule.** Vérifié sur LSX II : toute écriture sur `kef:eqProfile/v2` est
    /// **refusée (HTTP 401 « Forbidden »)** — objet complet, partiel, ou sous-chemin de feuille
    /// (`/deskMode` n'existe pas). KEF Connect modifie donc le DSP par un mécanisme non encore
    /// rétro-ingénierié. KefBar se contente d'**afficher** le profil. Cf. PROTOCOL.md A.12.
    func eqProfile() async throws -> [String: Any]? {
        let obj = try await getData(path: "kef:eqProfile/v2")
        return Self.typedObject(obj)?.value
    }

    // MARK: - File d'attente & notifications (best-effort)

    /// File d'attente / pistes à venir (`playlists:pq/getitems`, `roles=rows`). Parsing
    /// **défensif** : la forme des « rows » KEF est mal documentée — on tente plusieurs
    /// emplacements de titre/artiste et on ignore les éléments non exploitables.
    func playQueue() async throws -> [QueueItem] {
        let rows = try await getDataArray(path: "playlists:pq/getitems", roles: "rows")
        var items: [QueueItem] = []
        for (index, row) in rows.enumerated() {
            // L'élément peut être { title, … } à plat, ou imbriqué sous trackRoles/mediaData.
            let trackRoles = row["trackRoles"] as? [String: Any]
            let metaData = (trackRoles?["mediaData"] as? [String: Any])?["metaData"] as? [String: Any]
            let title = (row["title"] as? String)
                ?? (trackRoles?["title"] as? String)
                ?? (metaData?["title"] as? String)
            guard let title, !title.isEmpty else { continue }
            let artist = (row["artist"] as? String) ?? (metaData?["artist"] as? String)
            items.append(QueueItem(id: index, title: title, artist: artist))
        }
        return items
    }

    /// Notifications affichées par l'enceinte (`notifications:/display/queue`, `roles=rows`).
    /// Best-effort : on extrait un texte lisible de chaque ligne, en ignorant le reste.
    func notifications() async throws -> [String] {
        let rows = try await getDataArray(path: "notifications:/display/queue", roles: "rows")
        return rows.compactMap { row in
            (row["title"] as? String)
                ?? (row["message"] as? String)
                ?? (row["text"] as? String)
                ?? Self.string(row)
        }.filter { !$0.isEmpty }
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
        let body = try JSONSerialization.data(
            withJSONObject: ["subscribe": Self.eventSubscriptions, "unsubscribe": []]
        )
        let (data, resp) = try await send(apiPath: "event/modifyQueue") { req in
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
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
        let (data, resp) = try await send(apiPath: "event/pollQueue", query: [
            URLQueryItem(name: "queueId", value: queueId),
            URLQueryItem(name: "timeout", value: String(seconds)),
        ]) { req in
            req.timeoutInterval = TimeInterval(seconds) + 5   // dépasse le blocage du long-poll
        }
        try Self.validate(resp)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return !array.isEmpty
        }
        return false
    }

    // MARK: - Découverte

    /// Sonde l'hôte : renvoie un `Speaker` si c'est bien une enceinte KEF gén. 2, sinon `nil`.
    ///
    /// Le test discriminant est `speakerStatus`, un chemin **propre à KEF** : un serveur HTTP(S)
    /// quelconque renverra autre chose (ou rien de parsable) et `getData` lèvera, ce qui nous fait
    /// répondre `nil`. Sur un hit confirmé seulement (rare), on va chercher le nom et la MAC.
    func identify() async -> Speaker? {
        guard (try? await isPoweredOn()) != nil else { return nil }
        let name = (try? await deviceName()).flatMap { $0 }
        let mac = (try? await macAddress()).flatMap { $0 }
        return Speaker(host: host, name: name ?? Speaker.defaultName, mac: mac)
    }
}

/// Accepte le certificat **auto-signé** de l'enceinte KEF (`O=KEF, CN=KEF-device`, émis par
/// `KEF-CA`). L'API HTTPS locale (`https://<ip>:4430`) ne présente pas de chaîne remontant à une
/// autorité publique, et le certificat est émis pour un nom d'appareil, pas pour l'IP : la
/// validation standard échouerait donc toujours. La connexion restant cantonnée au réseau local
/// (même niveau de confiance que l'ancien HTTP en clair), on fait confiance au certificat serveur.
private final class KefTLSTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
