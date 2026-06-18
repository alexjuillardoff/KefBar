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
            Image(systemName: state.isOn ? "hifispeaker.fill" : "hifispeaker")
        }
        .menuBarExtraStyle(.window) // style "fenêtre" : indispensable pour les sliders.
    }
}

/// Cache l'icône du Dock (app de type accessoire) même hors bundle .app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
