import AppKit
import SwiftUI

/// Écran **dédié** des réglages, affiché à la place du lecteur depuis le bouton « Paramètres ».
/// Regroupe la gestion des enceintes (liste, scan réseau, ajout par IP), l'apparence dans la
/// barre de menus et le lancement au démarrage. Hébergé par `ContentView`, dont il hérite la
/// largeur et la marge du popover.
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    /// Autorise le retour au lecteur. `false` tant qu'aucune enceinte n'est enregistrée :
    /// on reste sur les réglages le temps d'en ajouter une.
    let canClose: Bool
    /// Ferme l'écran (retour au lecteur).
    let onClose: () -> Void

    @State private var manualIP = ""
    /// `true` une fois qu'un scan s'est terminé sans rien remonter de nouveau.
    @State private var triedScanWithNoResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !state.savedSpeakers.isEmpty {
                savedSpeakersList
                Divider()
            }
            addSpeakerSection
            Divider()
            menuBarAppearanceSection
            Divider()
            Toggle("Lancer au démarrage", isOn: $state.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
        }
        .onChange(of: state.isScanning) { scanning in
            // À la fin d'un scan, retient s'il n'a rien trouvé de nouveau (pour le message d'aide).
            if scanning {
                triedScanWithNoResult = false
            } else {
                triedScanWithNoResult = state.discovered.isEmpty
            }
        }
    }

    // MARK: - En-tête (titre + retour)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
            Text("Paramètres")
                .font(.headline)
            Spacer()
            if canClose {
                Button("Terminé", action: onClose)
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Enceintes enregistrées

    private var savedSpeakersList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mes enceintes")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(state.savedSpeakers) { speaker in
                HStack(spacing: 6) {
                    Image(systemName: speaker.host == state.host ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(speaker.host == state.host ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(speaker.name).lineLimit(1)
                        Text(speaker.host)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        state.remove(speaker)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Retirer cette enceinte")
                }
                .contentShape(Rectangle())
                .onTapGesture { state.selectHost(speaker.host) }
            }
        }
    }

    // MARK: - Ajouter une enceinte

    private var addSpeakerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ajouter une enceinte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    state.scan()
                } label: {
                    Label("Scanner le réseau", systemImage: "wifi")
                }
                .buttonStyle(.borderless)
                .disabled(state.isScanning)
            }

            if state.isScanning {
                ProgressView(value: state.scanProgress)
                    .progressViewStyle(.linear)
                Text("Recherche d'enceintes sur le réseau…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(state.discovered) { speaker in
                HStack(spacing: 6) {
                    Image(systemName: "hifispeaker")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(speaker.name).lineLimit(1)
                        Text(speaker.host)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Ajouter") { state.add(speaker) }
                        .buttonStyle(.borderless)
                }
            }

            if !state.isScanning && state.discovered.isEmpty && triedScanWithNoResult {
                Text("Aucune nouvelle enceinte trouvée. Vérifie qu'elle est allumée et sur le même réseau, ou saisis son IP ci-dessous.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                TextField("192.168.1.x", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addManual)
                Button("Ajouter", action: addManual)
                    .disabled(manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("IP visible dans l'app KEF Connect : Réglages → enceinte → Infos → Adresse IP.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func addManual() {
        let ip = manualIP.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        state.addManualHost(ip)
        manualIP = ""
    }

    // MARK: - Apparence dans la barre de menus

    /// Personnalisation du label affiché en haut de l'écran : icône, texte libre, ou les deux.
    private var menuBarAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Barre de menus")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Affichage", selection: $state.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if state.menuBarStyle.showsText {
                TextField("Texte (ex. KEF)", text: $state.menuBarText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }

            Text("Personnalise l'icône et le texte affichés dans la barre de menus, en haut de l'écran.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
