import AppKit
import SwiftUI

/// Gère la présence de l'app dans la barre de menus en **AppKit** : un `NSStatusItem` dont le
/// bouton héberge une vue SwiftUI (`MenuBarRootView`) — texte personnalisable **et boutons
/// cliquables** aux actions distinctes, impossibles avec `MenuBarExtra`. Le panneau complet
/// (`ContentView`) est présenté dans un `NSPopover` ouvert/fermé à la demande.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configurePopover()
        configureStatusItem()
    }

    /// Le popover transitoire (se referme au clic en dehors) héberge l'UI SwiftUI complète.
    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(state)
        )
    }

    /// Pose la vue SwiftUI dans le bouton du status item, calée sur ses bords (le status item
    /// `variableLength` adopte alors la largeur intrinsèque de la vue). Les boutons SwiftUI
    /// reçoivent leurs clics ; le reste de la zone est inerte (le bouton n'a pas d'action).
    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let root = MenuBarRootView(state: state) { [weak self] in self?.togglePopover() }
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])
    }

    /// Ouvre/ferme le popover ancré sous le status item.
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            state.popoverAppeared()
        }
    }

    /// Fermeture (clic en dehors, Échap…) : stoppe le suivi temps réel s'il n'est plus requis.
    func popoverDidClose(_ notification: Notification) {
        state.popoverDisappeared()
    }
}

// MARK: - Vue SwiftUI du status item (texte défilant + boutons)

/// Contenu du status item : les boutons activés (marche/arrêt, précédent, lecture/pause, suivant,
/// muet) puis l'« ouvreur » (icône + texte) qui ouvre le popover. Chaque élément est activable
/// indépendamment dans les réglages ; l'icône s'affiche d'office si aucun texte n'est visible,
/// pour garantir un point d'accès au popover.
struct MenuBarRootView: View {
    @ObservedObject var state: AppState
    let openPopover: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if state.menuBarShowPower {
                control("power", help: state.isOn ? "Éteindre" : "Allumer", active: state.isOn) {
                    state.togglePower()
                }
            }
            if state.menuBarShowPrevious {
                control("backward.fill", help: "Précédent") { state.previous() }
            }
            if state.menuBarShowPlayPause {
                control(state.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                        help: "Lecture / Pause") { state.playPause() }
            }
            if state.menuBarShowNext {
                control("forward.fill", help: "Suivant") { state.next() }
            }
            if state.menuBarShowMute {
                control(state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        help: state.isMuted ? "Réactiver le son" : "Couper le son",
                        active: state.isMuted) { state.toggleMute() }
            }
            opener
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }

    /// Icône + texte défilant, regroupés dans un bouton qui ouvre le popover. L'icône est forcée
    /// quand aucun texte n'est affiché, pour ne jamais perdre l'accès au panneau.
    @ViewBuilder
    private var opener: some View {
        let text = state.menuBarFullText
        let showText = !text.isEmpty
        let showIcon = state.menuBarShowIcon || !showText
        Button(action: openPopover) {
            HStack(spacing: 6) {
                if showIcon {
                    Image(systemName: state.isOn ? "hifispeaker.fill" : "hifispeaker")
                        .font(.system(size: 13))
                }
                if showText {
                    MenuBarTitle(text: text, offset: state.menuBarScrollOffset)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help("Ouvrir KefBar")
    }

    /// Un bouton de contrôle (icône SF Symbol), mis en évidence en couleur d'accent quand `active`.
    private func control(_ symbol: String, help: String, active: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .help(help)
    }
}
