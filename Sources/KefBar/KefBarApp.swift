import SwiftUI

@main
struct KefBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(state)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window) // style "fenêtre" : indispensable pour les sliders.
    }

    /// Label de la barre de menus, personnalisable dans les réglages : icône seule, texte seul,
    /// ou les deux. L'icône reflète l'état d'alimentation ; le texte est soit un libellé fixe,
    /// soit le morceau en cours (cf. `menuBarResolvedText`). Un texte vide retombe sur l'icône.
    @ViewBuilder
    private var menuBarLabel: some View {
        let icon = state.isOn ? "hifispeaker.fill" : "hifispeaker"
        let text = state.menuBarResolvedText
        switch state.menuBarStyle {
        case .icon:
            Image(systemName: icon)
        case .text:
            if text.isEmpty {
                Image(systemName: icon)
            } else {
                Text(text)
            }
        case .both:
            if text.isEmpty {
                Image(systemName: icon)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(text)
                }
            }
        }
    }
}

/// Cache l'icône du Dock (app de type accessoire) même hors bundle .app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
