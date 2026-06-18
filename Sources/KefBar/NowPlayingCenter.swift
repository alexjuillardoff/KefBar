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
        // Commandes non gérées : désactivées pour ne pas capturer inutilement les touches
        // (et éviter un scrubber trompeur, faute de position de lecture connue).
        c.seekForwardCommand.isEnabled = false
        c.seekBackwardCommand.isEnabled = false
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
        c.changePlaybackPositionCommand.isEnabled = false
    }

    // MARK: - Publication de la lecture en cours

    /// Met à jour le centre « En cours de lecture » à partir de l'état de l'enceinte.
    /// Appeler à chaque rafraîchissement : l'opération est idempotente et ne recharge la
    /// pochette que si son URL a changé.
    func update(nowPlaying: NowPlaying?, isOn: Bool) {
        guard isOn, let np = nowPlaying else {
            clear()
            return
        }

        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = np.title ?? "—"
        info[MPMediaItemPropertyArtist] = np.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = np.album ?? ""
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = np.isPlaying ? .playing : .paused

        if np.coverURL != publishedArtworkURL {
            publishedArtworkURL = np.coverURL
            loadArtwork(np.coverURL)
        }
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
