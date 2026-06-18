import AppKit
import Foundation
import MediaPlayer

/// Relie les **touches média physiques** du clavier (lecture/pause, précédent, suivant) à
/// l'enceinte, et publie la lecture en cours dans le Centre de contrôle / la pastille « En
/// cours de lecture » de macOS.
///
/// Mécanisme (framework MediaPlayer — aucune permission d'accessibilité requise) :
///   • `MPRemoteCommandCenter` reçoit les commandes de transport du système.
///   • En renseignant `MPNowPlayingInfoCenter` avec un `playbackState` ≠ `.stopped`, l'app
///     devient l'application « En cours de lecture » : macOS lui route alors les touches média
///     physiques (F7/F8/F9 ou les touches dédiées).
///
/// Quand l'enceinte est éteinte ou ne joue rien, on **relâche** ce statut (`playbackState =
/// .stopped`, infos vidées) pour rendre les touches média aux autres apps (Musique, Spotify…).
///
/// ⚠️ Ne fonctionne que depuis le bundle `.app` (un `CFBundleIdentifier` est nécessaire), pas
/// via `swift run`. Cf. CLAUDE.md.
@MainActor
final class NowPlayingCenter {
    /// Actions déclenchées par les touches média. Branchées par `AppState`.
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    /// Déplacement de la tête de lecture (scrubber « En cours de lecture » de macOS), en secondes.
    var onSeek: ((TimeInterval) -> Void)?

    private let commandCenter = MPRemoteCommandCenter.shared()
    private let infoCenter = MPNowPlayingInfoCenter.default()
    /// URL de la pochette actuellement publiée — évite de la recharger à chaque sondage (3 s).
    private var publishedArtworkURL: URL?
    private var artworkTask: Task<Void, Never>?

    init() {
        registerCommands()
    }

    // MARK: - Commandes de transport

    private func registerCommands() {
        let c = commandCenter
        // La touche lecture/pause envoie `togglePlayPause` ; les boutons du Centre de contrôle
        // envoient `play`/`pause`. La commande KEF « pause » bascule déjà l'état → on les
        // mappe toutes sur la même action.
        for command in [c.togglePlayPauseCommand, c.playCommand, c.pauseCommand] {
            command.addTarget { [weak self] _ in
                Task { @MainActor in self?.onPlayPause?() }
                return .success
            }
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNext?() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }
            return .success
        }
        // Le scrubber de la pastille « En cours de lecture » déplace la tête de lecture (seek).
        c.changePlaybackPositionCommand.isEnabled = true
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.onSeek?(e.positionTime) }
            return .success
        }
        // Commandes non gérées : désactivées pour ne pas capturer inutilement les touches.
        c.seekForwardCommand.isEnabled = false
        c.seekBackwardCommand.isEnabled = false
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
    }

    // MARK: - Publication de la lecture en cours

    /// Met à jour le centre « En cours de lecture » à partir de l'état de l'enceinte.
    /// Appeler à chaque rafraîchissement : l'opération est idempotente et ne recharge la
    /// pochette que si son URL a changé. `elapsed` (secondes) renseigne la position courante :
    /// avec la durée et le débit de lecture, macOS interpole la barre de progression sans qu'on
    /// ait à la rafraîchir en continu.
    func update(nowPlaying: NowPlaying?, isOn: Bool, elapsed: TimeInterval? = nil) {
        guard isOn, let np = nowPlaying else {
            clear()
            return
        }

        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = np.title ?? "—"
        info[MPMediaItemPropertyArtist] = np.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = np.album ?? ""
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        if let durationMs = np.durationMs, durationMs > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = TimeInterval(durationMs) / 1000
        } else {
            info[MPMediaItemPropertyPlaybackDuration] = nil
        }
        if let elapsed {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = np.isPlaying ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = np.isPlaying ? .playing : .paused

        if np.coverURL != publishedArtworkURL {
            publishedArtworkURL = np.coverURL
            loadArtwork(np.coverURL)
        }
    }

    /// Met à jour uniquement la position de lecture (sans toucher au reste des infos), pour le
    /// ticker seconde par seconde. Sans effet si rien n'est publié.
    func updatePosition(elapsed: TimeInterval, isPlaying: Bool) {
        guard infoCenter.playbackState != .stopped, infoCenter.nowPlayingInfo != nil else { return }
        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
    }

    private func clear() {
        guard infoCenter.playbackState != .stopped else { return }
        artworkTask?.cancel()
        publishedArtworkURL = nil
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
    }

    /// Télécharge la pochette en arrière-plan et l'ajoute aux infos en cours (best-effort).
    private func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard !Task.isCancelled, let self else { return }
            var info = self.infoCenter.nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            self.infoCenter.nowPlayingInfo = info
        }
    }
}
