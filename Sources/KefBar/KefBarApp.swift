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
    /// ou les deux. L'icône reflète l'état d'alimentation ; le texte est libre (repli sur l'icône
    /// si le mode texte est choisi sans rien saisir).
    @ViewBuilder
    private var menuBarLabel: some View {
        let icon = state.isOn ? "hifispeaker.fill" : "hifispeaker"
        let text = state.menuBarText.trimmingCharacters(in: .whitespaces)
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
                HStack(spacing: 4) {
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
