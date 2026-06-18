import Foundation
import SwiftUI

/// État partagé de l'app : configuration, état des enceintes, et actions.
@MainActor
final class AppState: ObservableObject {

    /// Adresse IP de l'enceinte (persistée dans UserDefaults).
    @Published var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: Self.hostKey)
            client = host.isEmpty ? nil : KefClient(host: host)
            Task { await refresh() }
        }
    }

    @Published private(set) var isReachable = false
    @Published private(set) var isOn = false
    @Published var volume: Int = 0
    @Published private(set) var source: Source = .wifi
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var deviceName: String?
    @Published private(set) var lastError: String?

    var isMuted: Bool { volume == 0 }

    private static let hostKey = "kef.host"
    private var client: KefClient?
    private var lastSource: Source = .wifi
    private var previousVolume: Int = 20
    private var pollTask: Task<Void, Never>?
    private var volumeSendTask: Task<Void, Never>?

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostKey) ?? ""
        client = host.isEmpty ? nil : KefClient(host: host)
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
            if let name { deviceName = name }
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

    // MARK: -

    private func report(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
