import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false
    @State private var manualIP = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if showSettings || state.savedSpeakers.isEmpty {
                settingsSection
            }

            if !state.host.isEmpty {
                Divider()
                nowPlayingView
                progressBar
                transportControls
                volumeControl
                sourcePicker
            }

            if let error = state.lastError, !state.isReachable {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .task {
            await state.refresh()
            state.startEventStream()
            state.startPositionTicker()
        }
        .onDisappear {
            state.stopEventStream()
            state.stopPositionTicker()
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

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.isOn ? "hifispeaker.fill" : "hifispeaker")
                .foregroundStyle(state.isReachable ? Color.primary : Color.secondary)

            if state.savedSpeakers.count > 1 {
                speakerSwitcher
            } else {
                Text(headerTitle)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Circle()
                .fill(state.isReachable ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .help(state.isReachable ? "Connectée" : "Injoignable")
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Gérer les enceintes")
        }
    }

    private var headerTitle: String {
        state.deviceName ?? state.activeSpeaker?.name ?? "Enceintes KEF"
    }

    /// Menu déroulant pour basculer rapidement entre plusieurs enceintes.
    private var speakerSwitcher: some View {
        Menu {
            ForEach(state.savedSpeakers) { speaker in
                Button { state.selectHost(speaker.host) } label: {
                    if speaker.host == state.host {
                        Label(speaker.name, systemImage: "checkmark")
                    } else {
                        Text(speaker.name)
                    }
                }
            }
        } label: {
            Text(headerTitle)
                .font(.headline)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.savedSpeakers.isEmpty {
                savedSpeakersList
                Divider()
            }
            addSpeakerSection
        }
    }

    // MARK: Enceintes enregistrées

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

    // MARK: Ajouter une enceinte

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

    /// `true` une fois qu'un scan s'est terminé sans rien remonter de nouveau.
    @State private var triedScanWithNoResult = false

    private func addManual() {
        let ip = manualIP.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        state.addManualHost(ip)
        manualIP = ""
    }

    private var nowPlayingView: some View {
        HStack(spacing: 10) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(state.nowPlaying?.title ?? "—")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(state.nowPlaying?.artist ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let image = state.coverImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderCover
        }
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
    }

    /// Barre de progression + temps écoulé/total. Masquée tant que la durée est inconnue
    /// (best-effort : tous les services ne la communiquent pas).
    @ViewBuilder
    private var progressBar: some View {
        if let durationMs = state.nowPlaying?.durationMs, durationMs > 0 {
            let position = min(max(0, state.positionMs), durationMs)
            VStack(spacing: 2) {
                ProgressView(value: Double(position), total: Double(durationMs))
                    .progressViewStyle(.linear)
                HStack {
                    Text(Self.timeLabel(position))
                    Spacer()
                    Text(Self.timeLabel(durationMs))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Formate un nombre de millisecondes en `m:ss`.
    private static func timeLabel(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var transportControls: some View {
        HStack(spacing: 28) {
            Spacer()
            Button { state.previous() } label: { Image(systemName: "backward.fill") }
            Button { state.playPause() } label: {
                Image(systemName: state.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
            }
            Button { state.next() } label: { Image(systemName: "forward.fill") }
            Spacer()
        }
        .font(.title3)
        .buttonStyle(.borderless)
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button { state.toggleMute() } label: {
                Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.fill")
            }
            .buttonStyle(.borderless)
            Slider(
                value: Binding(
                    get: { Double(state.volume) },
                    set: { state.setVolume(Int($0)) }
                ),
                in: 0...100
            )
            Text("\(state.volume)")
                .font(.caption.monospacedDigit())
                .frame(width: 26, alignment: .trailing)
        }
    }

    private var sourcePicker: some View {
        Picker("Source", selection: Binding(
            get: { state.source },
            set: { state.select($0) }
        )) {
            ForEach(Source.selectable) { src in
                Label(src.displayName, systemImage: src.systemImage).tag(src)
            }
        }
        .pickerStyle(.menu)
    }

    private var footer: some View {
        HStack {
            Button {
                state.togglePower()
            } label: {
                Label(state.isOn ? "Éteindre" : "Allumer",
                      systemImage: "power")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }
}
