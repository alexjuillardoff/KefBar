import SwiftUI

/// Point d'entrée. L'app n'a **pas de fenêtre principale** : toute l'UI vit dans la barre de
/// menus, gérée en AppKit par `MenuBarController` (un `NSStatusItem` qui héberge une vue SwiftUI
/// avec texte **et boutons cliquables**, plus un `NSPopover` pour le panneau complet). On ne peut
/// pas obtenir plusieurs boutons aux actions distinctes avec `MenuBarExtra`, d'où le passage à
/// AppKit. La scène `Settings` vide ne sert qu'à satisfaire le protocole `App`.
@main
struct KefBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Crée l'état partagé et le contrôleur de barre de menus, et force la politique d'activation
/// « accessoire » (pas d'icône dans le Dock), même hors bundle .app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(state: state)
    }
}
