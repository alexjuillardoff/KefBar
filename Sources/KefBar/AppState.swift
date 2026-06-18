import AppKit
import Foundation
import ServiceManagement
import SwiftUI

/// État partagé de l'app : configuration, état des enceintes, et actions.
@MainActor
final class AppState: ObservableObject {

    /// Adresse IP de l'enceinte active (persistée dans UserDefaults).
    @Published var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: Self.hostKey)
            client = host.isEmpty ? nil : KefClient(host: host)
            positionMs = 0
            resetPerSpeakerState()
            // Si le flux d'évènements tourne, on le relance pour s'abonner à la nouvelle
            // enceinte (le ré-abonnement déclenche un rafraîchissement). Sinon, simple refresh.
            if eventTask != nil {
                startEventStream()
            } else {
                Task { await refresh() }
            }
        }
    }

    /// Enceintes enregistrées (découvertes ou ajoutées à la main), persistées en JSON.
    @Published var savedSpeakers: [Speaker] {
        didSet { persistSpeakers() }
    }

    /// Enceintes trouvées au dernier scan et **pas encore** enregistrées.
    @Published private(set) var discovered: [Speaker] = []
    @Published private(set) var isScanning = false
    /// Avancement du scan en cours, 0…1.
    @Published private(set) var scanProgress: Double = 0

    @Published private(set) var isReachable = false
    @Published private(set) var isOn = false
    @Published var volume: Int = 0
    @Published private(set) var source: Source = .wifi
    @Published private(set) var nowPlaying: NowPlaying?
    /// Pochette du morceau en cours, déjà décodée. Chargée par nos soins (cf. `updateCover`)
    /// plutôt que via `AsyncImage`, qui ne s'affiche pas de façon fiable dans le popover.
    @Published private(set) var coverImage: NSImage?
    /// Position de lecture courante en millisecondes (alimente la barre de progression).
    @Published private(set) var positionMs: Int = 0
    @Published private(set) var deviceName: String?
    @Published private(set) var lastError: String?

    /// Mode de lecture courant (répétition / aléatoire).
    @Published private(set) var playMode: PlayMode = .normal
    /// Volume maximum autorisé (plafond réglé sur l'enceinte) : borne haute du slider.
    @Published private(set) var maxVolume: Int = 100
    /// Pas des boutons −/+ de volume.
    @Published private(set) var volumeStep: Int = 5

    /// Réglages DSP (miroirs **lecture seule** du profil `kef:eqProfile/v2`). L'écriture est
    /// refusée par l'enceinte (HTTP 401) — on affiche le profil sans le modifier. `eqAvailable`
    /// reste `false` tant qu'aucun profil exploitable n'a été lu (section masquée alors).
    @Published private(set) var eqAvailable = false
    @Published private(set) var eqProfileName: String?
    @Published private(set) var eqDeskMode = false
    @Published private(set) var eqWallMode = false
    @Published private(set) var eqPhaseCorrection = false
    @Published private(set) var eqHighPassMode = false
    @Published private(set) var eqSubwooferOut = false
    @Published private(set) var eqBassExtension = "standard"
    @Published private(set) var eqTrebleAmount = 0

    /// File d'attente et notifications (best-effort — chargées à l'ouverture des réglages avancés).
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var notifications: [String] = []

    /// Heure d'extinction programmée par la minuterie de veille (`nil` = pas de minuterie).
    @Published private(set) var sleepTimerEnd: Date?

    /// Lancement de l'app à l'ouverture de session (login item via `SMAppService`).
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    var isMuted: Bool { volume == 0 }

    /// L'enceinte enregistrée correspondant à l'IP active, si elle existe.
    var activeSpeaker: Speaker? { savedSpeakers.first { $0.host == host } }

    private static let hostKey = "kef.host"
    private static let speakersKey = "kef.speakers"
    private var client: KefClient?
    private var lastSource: Source = .wifi
    private var previousVolume: Int = 20
    private var eventTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var volumeSendTask: Task<Void, Never>?
    private var coverURLShown: URL?
    private var coverTask: Task<Void, Never>?

    /// Caches par enceinte : configuration de volume et profil DSP ne sont lus qu'une fois
    /// (remis à zéro au changement d'`host`).
    private var volumeConfigLoaded = false
    private var eqLoaded = false
    /// Minuterie de veille (extinction différée, côté app).
    private var sleepTask: Task<Void, Never>?

    /// Touches média du clavier + intégration « En cours de lecture » de macOS.
    private let nowPlayingCenter = NowPlayingCenter()

    init() {
        let savedHost = UserDefaults.standard.string(forKey: Self.hostKey) ?? ""
        host = savedHost
        launchAtLogin = Self.isLaunchAtLoginEnabled()

        var speakers = Self.loadSpeakers()
        // Migration : un utilisateur d'une version précédente n'a qu'une IP — on la
        // reprend comme première enceinte enregistrée.
        if speakers.isEmpty, !savedHost.isEmpty {
            speakers = [Speaker(host: savedHost)]
        }
        savedSpeakers = speakers

        client = savedHost.isEmpty ? nil : KefClient(host: savedHost)

        // Les touches média physiques pilotent l'enceinte active.
        nowPlayingCenter.onPlayPause = { [weak self] in self?.playPause() }
        nowPlayingCenter.onNext = { [weak self] in self?.next() }
        nowPlayingCenter.onPrevious = { [weak self] in self?.previous() }
    }

    // MARK: - Rafraîchissement

    func refresh() async {
        guard let client else {
            isReachable = false
            updateCover(nil)
            nowPlayingCenter.update(nowPlaying: nil, isOn: false)
            return
        }
        do {
            let on = try await client.isPoweredOn()
            let vol = try await client.volume()
            let src = try await client.currentSource()
            let np = try? await client.nowPlaying()
            let name = try? await client.deviceName()
            let pos = try? await client.playPosition()
            let mode = try? await client.playMode()

            let trackChanged = np?.title != nowPlaying?.title
            isOn = on
            volume = vol
            if vol > 0 { previousVolume = vol }
            if src != .standby { source = src; lastSource = src }
            nowPlaying = np
            updateCover(np?.coverURL)
            // Position : on prend la valeur lue ; à défaut on remet à zéro au changement de piste.
            if let pos { positionMs = pos } else if trackChanged { positionMs = 0 }
            if let mode { playMode = mode }
            if let name {
                deviceName = name
                updateActiveSpeakerName(name)
            }
            isReachable = true
            lastError = nil
            nowPlayingCenter.update(nowPlaying: np, isOn: on,
                                    elapsed: pos.map { TimeInterval($0) / 1000 })
            // Configuration peu changeante (plafond de volume, profil DSP) : lue une seule fois
            // par enceinte, sans bloquer le rafraîchissement principal.
            await loadSpeakerConfigIfNeeded()
        } catch {
            isReachable = false
            report(error)
        }
    }

    // MARK: - Flux d'évènements temps réel (long-poll)

    /// Démarre le suivi de l'enceinte par **push** : on s'abonne aux changements et on attend
    /// (long-poll) qu'ils surviennent, au lieu de sonder toutes les 3 s. Réveil quasi instantané
    /// sur changement de volume/piste, et beaucoup moins de trafic réseau.
    func startEventStream() {
        stopEventStream()
        eventTask = Task { [weak self] in await self?.runEventLoop() }
    }

    func stopEventStream() {
        eventTask?.cancel()
        eventTask = nil
    }

    /// Boucle : s'abonne, puis enchaîne les long-polls. Chaque retour (changement signalé **ou**
    /// expiration du délai) déclenche un `refresh()` qui relit les valeurs faisant foi. En cas
    /// d'échec (firmware sans évènements, file expirée, enceinte injoignable), on rafraîchit
    /// quand même puis on retente — ce repli équivaut à un polling périodique.
    private func runEventLoop() async {
        while !Task.isCancelled {
            guard let client else {
                await refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            do {
                let queueId = try await client.subscribeToEvents()
                await refresh()
                while !Task.isCancelled {
                    _ = try await client.pollEvents(queueId: queueId, timeout: 10)
                    if Task.isCancelled { return }
                    await refresh()
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                isReachable = false
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    // MARK: - Position de lecture (rafraîchie pendant que le popover est ouvert)

    /// Met à jour la position toutes les secondes tant que la vue est affichée et que ça joue.
    func startPositionTicker() {
        stopPositionTicker()
        positionTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickPosition()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stopPositionTicker() {
        positionTask?.cancel()
        positionTask = nil
    }

    private func tickPosition() async {
        guard let client, isOn, nowPlaying?.isPlaying == true,
              let ms = try? await client.playPosition() else { return }
        positionMs = ms
        nowPlayingCenter.updatePosition(elapsed: TimeInterval(ms) / 1000, isPlaying: true)
    }

    // MARK: - Pochette

    /// Charge la pochette en `NSImage` (via `URLSession`, chemin éprouvé) au lieu de s'en
    /// remettre à `AsyncImage`, qui ne s'affiche pas de façon fiable dans un popover
    /// `MenuBarExtra`. Ne recharge que si l'URL a changé ; garde l'image précédente le temps
    /// du chargement pour éviter un clignotement.
    private func updateCover(_ url: URL?) {
        guard url != coverURLShown else { return }
        coverURLShown = url
        coverTask?.cancel()
        guard let url else { coverImage = nil; return }
        coverTask = Task { [weak self] in
            let image = await Self.loadImage(url)
            guard !Task.isCancelled, let self, self.coverURLShown == url else { return }
            self.coverImage = image
        }
    }

    private static func loadImage(_ url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Volume (avec anti-rebond pour ne pas saturer l'enceinte au drag)

    func setVolume(_ value: Int) {
        // Borne haute = plafond réglé sur l'enceinte (`maxVolume`, 100 par défaut).
        let clamped = max(0, min(maxVolume, value))
        if clamped > 0 { previousVolume = clamped }
        volume = clamped
        volumeSendTask?.cancel()
        volumeSendTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self, let client = self.client else { return }
            do { try await client.setVolume(clamped) } catch { self.report(error) }
        }
    }

    func toggleMute() {
        setVolume(isMuted ? max(previousVolume, 10) : 0)
    }

    // MARK: - Alimentation & source

    func togglePower() {
        guard let client else { return }
        Task {
            do {
                if isOn {
                    try await client.powerOff()
                    isOn = false
                } else {
                    try await client.powerOn(lastSource)
                    isOn = true
                    source = lastSource
                }
            } catch { report(error) }
            await refresh()
        }
    }

    func select(_ newSource: Source) {
        guard let client else { return }
        source = newSource
        lastSource = newSource
        isOn = true
        Task {
            do { try await client.setSource(newSource) } catch { report(error) }
        }
    }

    // MARK: - Transport

    func playPause() { perform { try await $0.playPause() } }
    func next()      { perform { try await $0.next() } }
    func previous()  { perform { try await $0.previous() } }

    private func perform(_ action: @escaping (KefClient) async throws -> Void) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                await refresh()
            } catch { report(error) }
        }
    }

    // MARK: - Mode de lecture (répétition / aléatoire)

    /// Bouton unique : passe au mode suivant (normal → répéter tout → répéter la piste →
    /// aléatoire → …). Mise à jour optimiste puis écriture.
    func cyclePlayMode() {
        guard let client else { return }
        let newMode = playMode.next
        playMode = newMode
        Task {
            do { try await client.setPlayMode(newMode) } catch { report(error) }
        }
    }

    // MARK: - Boutons de volume −/+

    /// Monte/descend le volume d'un `volumeStep` (borné à `maxVolume` par `setVolume`).
    func stepVolume(up: Bool) {
        setVolume(volume + (up ? volumeStep : -volumeStep))
    }

    // MARK: - Configuration peu changeante (plafond volume + DSP), lue une fois par enceinte

    /// Lit, **une seule fois par enceinte**, le plafond de volume, le pas, et le profil DSP.
    /// Appelée à la fin de `refresh()` ; n'écrase rien si les lectures échouent.
    private func loadSpeakerConfigIfNeeded() async {
        guard let client else { return }
        if !volumeConfigLoaded {
            volumeConfigLoaded = true
            if let m = try? await client.maximumVolume(), (1...100).contains(m) { maxVolume = m }
            if let s = try? await client.volumeStep(), (1...50).contains(s) { volumeStep = s }
            if volume > maxVolume { volume = maxVolume }
        }
        if !eqLoaded {
            eqLoaded = true
            await refreshEQ()
        }
    }

    // MARK: - DSP / Profil EQ (lecture seule)

    /// Relit le profil DSP (`kef:eqProfile/v2`) et met à jour les miroirs **lecture seule**.
    /// Tolérant : un profil illisible laisse `eqAvailable = false` (section DSP masquée).
    func refreshEQ() async {
        guard let client else { return }
        guard let value = (try? await client.eqProfile()) ?? nil else { eqAvailable = false; return }
        eqProfileName = (value["profileName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        eqDeskMode = Self.bool(value["deskMode"]) ?? false
        eqWallMode = Self.bool(value["wallMode"]) ?? false
        eqPhaseCorrection = Self.bool(value["phaseCorrection"]) ?? false
        eqHighPassMode = Self.bool(value["highPassMode"]) ?? false
        eqSubwooferOut = Self.bool(value["subwooferOut"]) ?? false
        eqBassExtension = (value["bassExtension"] as? String) ?? "standard"
        eqTrebleAmount = (value["trebleAmount"] as? NSNumber)?.intValue ?? 0
        eqAvailable = true
    }

    /// Libellé lisible de l'extension des graves.
    var bassExtensionLabel: String {
        switch eqBassExtension {
        case "less":  return "Réduite"
        case "extra": return "Étendue"
        default:       return "Standard"
        }
    }

    /// Lit un booléen tolérant aux formes `bool_`/entier 0-1/chaîne.
    private static func bool(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        if let s = any as? String { return s == "true" || s == "1" }
        return nil
    }

    // MARK: - File d'attente & notifications (best-effort)

    func refreshQueue() async {
        guard let client else { return }
        queue = (try? await client.playQueue()) ?? []
    }

    func refreshNotifications() async {
        guard let client else { return }
        notifications = (try? await client.notifications()) ?? []
    }

    // MARK: - Minuterie de veille (extinction différée, côté app)

    var sleepTimerActive: Bool { sleepTimerEnd != nil }

    /// Programme l'extinction de l'enceinte dans `minutes`. Annule une minuterie en cours.
    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        sleepTimerEnd = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.sleepTimerEnd = nil
            self.sleepTask = nil
            await self.powerOffNow()
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerEnd = nil
    }

    private func powerOffNow() async {
        guard let client else { return }
        do { try await client.powerOff(); isOn = false } catch { report(error) }
        await refresh()
    }

    // MARK: - Lancement à l'ouverture de session (login item)

    /// Évite la récursion du `didSet` quand on resynchronise l'interrupteur après un échec.
    private var suppressLaunchDidSet = false

    private static func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enregistre/retire le login item. Nécessite le **bundle `.app`** (un `CFBundleIdentifier`) :
    /// sans lui (`swift run`), l'opération échoue proprement et l'interrupteur se resynchronise.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard !suppressLaunchDidSet else { return }
        let service = SMAppService.mainApp
        do {
            switch (enabled, service.status) {
            case (true, let s) where s != .enabled:  try service.register()
            case (false, .enabled):                   try service.unregister()
            default:                                   break
            }
        } catch {
            report(error)
            suppressLaunchDidSet = true
            launchAtLogin = (service.status == .enabled)
            suppressLaunchDidSet = false
        }
    }

    /// Réinitialise l'état spécifique à une enceinte au changement d'`host`.
    private func resetPerSpeakerState() {
        volumeConfigLoaded = false
        eqLoaded = false
        maxVolume = 100
        volumeStep = 5
        playMode = .normal
        eqAvailable = false
        eqProfileName = nil
        queue = []
        notifications = []
    }

    // MARK: - Multi-enceintes & découverte

    /// Bascule l'enceinte active sur l'IP donnée (reconstruit le client + rafraîchit via `didSet`).
    func selectHost(_ newHost: String) {
        guard newHost != host else { return }
        host = newHost
    }

    /// Enregistre une enceinte (sans doublon) et la sélectionne par défaut.
    func add(_ speaker: Speaker, select: Bool = true) {
        if !savedSpeakers.contains(where: { $0.id == speaker.id || $0.host == speaker.host }) {
            savedSpeakers.append(speaker)
        }
        discovered.removeAll { $0.id == speaker.id || $0.host == speaker.host }
        if select { selectHost(speaker.host) }
    }

    /// Ajoute une enceinte par IP saisie à la main, puis tente de récupérer son vrai nom/MAC.
    func addManualHost(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        add(Speaker(host: trimmed))
        Task {
            if let identified = await KefClient(host: trimmed, timeout: 3).identify() {
                mergeIdentity(identified)
            }
        }
    }

    /// Retire une enceinte ; si c'était l'active, bascule sur une autre (ou plus rien).
    func remove(_ speaker: Speaker) {
        savedSpeakers.removeAll { $0.id == speaker.id }
        if host == speaker.host {
            host = savedSpeakers.first?.host ?? ""
        }
    }

    /// Lance un scan du réseau local pour découvrir les enceintes KEF.
    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        discovered = []
        Task {
            let found = await Discovery.scan { fraction in
                Task { @MainActor in self.scanProgress = fraction }
            }
            self.applyScanResults(found)
            self.isScanning = false
            self.scanProgress = 1
        }
    }

    /// Intègre les résultats d'un scan : met à jour les IP des enceintes connues dont la MAC
    /// correspond (l'IP a pu changer via DHCP), puis isole les nouvelles dans `discovered`.
    private func applyScanResults(_ found: [Speaker]) {
        var speakers = savedSpeakers
        var newActiveHost = host

        for f in found {
            guard let mac = f.mac,
                  let idx = speakers.firstIndex(where: { $0.mac == mac }) else { continue }
            // Suit le changement d'IP de l'enceinte active.
            if speakers[idx].host == host { newActiveHost = f.host }
            speakers[idx].host = f.host
            if speakers[idx].name == Speaker.defaultName { speakers[idx].name = f.name }
        }

        savedSpeakers = speakers
        if newActiveHost != host { host = newActiveHost }

        discovered = found.filter { f in
            !speakers.contains { saved in
                (saved.mac != nil && saved.mac == f.mac) || saved.host == f.host
            }
        }
    }

    /// Complète une enceinte enregistrée avec le nom/MAC réels une fois sondée.
    private func mergeIdentity(_ identified: Speaker) {
        guard let idx = savedSpeakers.firstIndex(where: { $0.host == identified.host }) else { return }
        if savedSpeakers[idx].name == Speaker.defaultName { savedSpeakers[idx].name = identified.name }
        if savedSpeakers[idx].mac == nil { savedSpeakers[idx].mac = identified.mac }
    }

    /// Garde le nom de l'enceinte active à jour avec celui renvoyé par l'appareil.
    private func updateActiveSpeakerName(_ name: String) {
        guard !name.isEmpty,
              let idx = savedSpeakers.firstIndex(where: { $0.host == host }),
              savedSpeakers[idx].name != name else { return }
        savedSpeakers[idx].name = name
    }

    // MARK: - Persistance des enceintes

    private static func loadSpeakers() -> [Speaker] {
        guard let data = UserDefaults.standard.data(forKey: speakersKey),
              let list = try? JSONDecoder().decode([Speaker].self, from: data) else { return [] }
        return list
    }

    private func persistSpeakers() {
        if let data = try? JSONEncoder().encode(savedSpeakers) {
            UserDefaults.standard.set(data, forKey: Self.speakersKey)
        }
    }

    // MARK: -

    private func report(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
