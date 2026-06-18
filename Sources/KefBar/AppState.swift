import Foundation
import SwiftUI

/// État partagé de l'app : configuration, état des enceintes, et actions.
@MainActor
final class AppState: ObservableObject {

    /// Adresse IP de l'enceinte active (persistée dans UserDefaults).
    @Published var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: Self.hostKey)
            client = host.isEmpty ? nil : KefClient(host: host)
            Task { await refresh() }
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
    @Published private(set) var deviceName: String?
    @Published private(set) var lastError: String?

    var isMuted: Bool { volume == 0 }

    /// L'enceinte enregistrée correspondant à l'IP active, si elle existe.
    var activeSpeaker: Speaker? { savedSpeakers.first { $0.host == host } }

    private static let hostKey = "kef.host"
    private static let speakersKey = "kef.speakers"
    private var client: KefClient?
    private var lastSource: Source = .wifi
    private var previousVolume: Int = 20
    private var pollTask: Task<Void, Never>?
    private var volumeSendTask: Task<Void, Never>?

    init() {
        let savedHost = UserDefaults.standard.string(forKey: Self.hostKey) ?? ""
        host = savedHost

        var speakers = Self.loadSpeakers()
        // Migration : un utilisateur d'une version précédente n'a qu'une IP — on la
        // reprend comme première enceinte enregistrée.
        if speakers.isEmpty, !savedHost.isEmpty {
            speakers = [Speaker(host: savedHost)]
        }
        savedSpeakers = speakers

        client = savedHost.isEmpty ? nil : KefClient(host: savedHost)
    }

    // MARK: - Rafraîchissement

    func refresh() async {
        guard let client else { isReachable = false; return }
        do {
            let on = try await client.isPoweredOn()
            let vol = try await client.volume()
            let src = try await client.currentSource()
            let np = try? await client.nowPlaying()
            let name = try? await client.deviceName()

            isOn = on
            volume = vol
            if vol > 0 { previousVolume = vol }
            if src != .standby { source = src; lastSource = src }
            nowPlaying = np
            if let name {
                deviceName = name
                updateActiveSpeakerName(name)
            }
            isReachable = true
            lastError = nil
        } catch {
            isReachable = false
            report(error)
        }
    }

    func startPolling(every seconds: UInt64 = 3) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Volume (avec anti-rebond pour ne pas saturer l'enceinte au drag)

    func setVolume(_ value: Int) {
        let clamped = max(0, min(100, value))
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
