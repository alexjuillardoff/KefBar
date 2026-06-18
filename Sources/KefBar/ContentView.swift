import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if showSettings || state.host.isEmpty {
                settingsSection
            }

            if !state.host.isEmpty {
                Divider()
                nowPlayingView
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
            state.startPolling()
        }
        .onDisappear { state.stopPolling() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.isOn ? "hifispeaker.fill" : "hifispeaker")
                .foregroundStyle(state.isReachable ? Color.primary : Color.secondary)
            Text(state.deviceName ?? "Enceintes KEF")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Circle()
                .fill(state.isReachable ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .help(state.isReachable ? "Connectée" : "Injoignable")
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adresse IP de l'enceinte")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("192.168.1.x", text: $state.host)
                    .textFieldStyle(.roundedBorder)
                Button("Tester") { Task { await state.refresh() } }
            }
            Text("Visible dans l'app KEF Connect : Réglages → enceinte → Infos → Adresse IP.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
        if let url = state.nowPlaying?.coverURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholderCover
            }
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
