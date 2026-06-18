import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false
    @State private var showAdvanced = false

    /// Largeur fixe du popover et marge intérieure — partagées pour dimensionner les boutons
    /// de source (carrés qui pavent exactement la largeur disponible).
    private static let popoverWidth: CGFloat = 340
    private static let contentPadding: CGFloat = 14

    /// Vrai quand l'écran des réglages doit s'afficher : soit ouvert à la demande, soit forcé
    /// tant qu'aucune enceinte n'est enregistrée (il faut bien en ajouter une).
    private var showingSettings: Bool { showSettings || state.savedSpeakers.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingSettings {
                // Écran dédié : le retour est masqué tant qu'aucune enceinte n'existe.
                SettingsView(canClose: !state.savedSpeakers.isEmpty) { showSettings = false }
            } else {
                playerContent
            }

            Divider()
            footer
        }
        .padding(Self.contentPadding)
        .frame(width: Self.popoverWidth)
        .task {
            // L'ouverture/fermeture (et donc le suivi temps réel) est pilotée par
            // `MenuBarController` via `popoverAppeared()`/`popoverDisappeared()`.
            await state.refresh()
            await state.refreshNotifications()
        }
        .onChange(of: showAdvanced) { open in
            // Charge file d'attente + notifications (best-effort) à l'ouverture du panneau.
            if open {
                Task {
                    await state.refreshQueue()
                    await state.refreshNotifications()
                }
            }
        }
    }

    /// Le lecteur proprement dit : en-tête, sources, lecture en cours et réglages avancés.
    @ViewBuilder
    private var playerContent: some View {
        header

        if !state.host.isEmpty {
            Divider()
            sourceButtons
            nowPlayingView
            notificationsView
            progressBar
            transportControls
            volumeControl
            volumeReadout
            Divider()
            advancedSection
        }

        if let error = state.lastError, !state.isReachable {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - En-tête (enceinte, IP, statut, alimentation)

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isOn ? "hifispeaker.fill" : "hifispeaker")
                .font(.title3)
                .foregroundStyle(state.isReachable ? Color.primary : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                if state.savedSpeakers.count > 1 {
                    speakerSwitcher
                } else {
                    Text(headerTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                if !state.host.isEmpty {
                    Text(state.host)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Circle()
                .fill(state.isReachable ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .help(state.isReachable ? "Connectée" : "Injoignable")

            // Allumer / éteindre (écrit la source courante ou `standby`).
            Button { state.togglePower() } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(state.isOn ? Color.accentColor : Color.secondary)
            .help(state.isOn ? "Éteindre" : "Allumer")
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

    // MARK: - Sélecteur de source (boutons raccourcis)

    /// Une rangée de boutons-raccourcis **carrés** : la source active est mise en évidence.
    private var sourceButtons: some View {
        let spacing: CGFloat = 6
        let count = CGFloat(Source.selectable.count)
        // Côté du carré = largeur intérieure moins les espaces, divisée par le nombre de sources.
        let side = (Self.popoverWidth - Self.contentPadding * 2 - spacing * (count - 1)) / count
        return HStack(spacing: spacing) {
            ForEach(Source.selectable) { src in
                sourceButton(src, side: side)
            }
        }
    }

    private func sourceButton(_ src: Source, side: CGFloat) -> some View {
        let active = state.isOn && state.source == src
        return Button { state.select(src) } label: {
            VStack(spacing: 3) {
                Image(systemName: src.systemImage)
                    .font(.system(size: 16))
                Text(src.shortName)
                    .font(.system(size: 9, weight: .regular))
                    .lineLimit(1)
            }
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(active ? Color.white : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(src.displayName)
    }

    // MARK: - En cours de lecture (pochette + métadonnées défilantes)

    private var nowPlayingView: some View {
        HStack(spacing: 10) {
            cover
            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(text: state.nowPlaying?.title ?? "—",
                            font: .subheadline.weight(.medium))
                if let artist = state.nowPlaying?.artist, !artist.isEmpty {
                    MarqueeText(text: artist, font: .caption, color: .secondary)
                }
                if let album = state.nowPlaying?.album, !album.isEmpty {
                    MarqueeText(text: album, font: .caption2, color: .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let image = state.coverImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderCover
        }
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 52, height: 52)
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

    // MARK: - Transport (boucle à gauche, puis précédent / pause / suivant)

    private var transportControls: some View {
        HStack(spacing: 0) {
            // Bouton « Boucle » (mode de lecture) à gauche. Désactivé hors lecture :
            // l'enceinte refuse d'écrire le mode sans session active (HTTP 401).
            Button { state.cyclePlayMode() } label: {
                Image(systemName: state.playMode.systemImage)
            }
            .font(.callout)
            .foregroundStyle(state.playMode.isActive ? Color.accentColor : Color.secondary)
            .disabled(state.nowPlaying == nil)
            .help("Mode de lecture : \(state.playMode.displayName)")

            Spacer()
            Button { state.previous() } label: { Image(systemName: "backward.fill") }
            Spacer().frame(width: 26)
            Button { state.playPause() } label: {
                Image(systemName: state.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
            }
            Spacer().frame(width: 26)
            Button { state.next() } label: { Image(systemName: "forward.fill") }
            Spacer()

            // Réserve symétrique (même gabarit que le bouton Boucle) pour centrer le trio.
            Image(systemName: state.playMode.systemImage).font(.callout).opacity(0)
        }
        .font(.title3)
        .buttonStyle(.borderless)
    }

    // MARK: - Volume (barre pleine largeur + lecture/saisie du niveau)

    /// Barre de volume encadrée des boutons − / + (chacun ajuste le niveau de 1).
    private var volumeControl: some View {
        HStack(spacing: 10) {
            Button { state.nudgeVolume(up: false) } label: { Image(systemName: "minus") }
                .buttonStyle(.borderless)
                .disabled(state.volume <= 0)
            Slider(
                value: Binding(
                    get: { Double(min(state.volume, state.maxVolume)) },
                    set: { state.setVolume(Int($0.rounded())) }
                ),
                in: 0...Double(max(state.maxVolume, 1))
            )
            Button { state.nudgeVolume(up: true) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .disabled(state.volume >= state.maxVolume)
        }
    }

    /// Sous la barre : icône haut-parleur (nombre d'ondes selon le niveau, clic = muet) et
    /// niveau en %, **éditable** (saisie directe + flèches ↑/↓ pour ±1).
    private var volumeReadout: some View {
        HStack(spacing: 6) {
            Button { state.toggleMute() } label: {
                Image(systemName: volumeSymbol)
                    .frame(width: 20, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .help(state.isMuted ? "Réactiver le son" : "Couper le son")

            VolumeField(value: state.volume, range: 0...max(state.maxVolume, 1)) { newValue in
                state.setVolume(newValue)
            }
            .frame(width: 30, height: 18)
            Text("%")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.callout.monospacedDigit())
    }

    /// Icône haut-parleur : muet, ou 1 à 3 ondes selon le niveau relatif au plafond.
    private var volumeSymbol: String {
        guard !state.isMuted else { return "speaker.slash.fill" }
        let fraction = state.maxVolume > 0 ? Double(state.volume) / Double(state.maxVolume) : 0
        switch fraction {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }

    /// Notifications affichées par l'enceinte (best-effort — souvent vide). Masqué si rien.
    @ViewBuilder
    private var notificationsView: some View {
        if !state.notifications.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(state.notifications.enumerated()), id: \.offset) { _, note in
                    Label(note, systemImage: "bell")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: Réglages avancés (DSP, minuterie de veille, file d'attente)

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                    Text("Réglages avancés")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                if state.eqAvailable { dspControls }
                sleepTimerControls
                if !state.queue.isEmpty { queueView }
            }
        }
    }

    /// Profil DSP **en lecture seule** (`kef:eqProfile/v2`). L'API refuse l'écriture (HTTP 401),
    /// donc KefBar affiche le réglage sans le modifier. Masqué si aucun profil n'a été lu.
    private var dspControls: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("DSP").font(.caption).foregroundStyle(.secondary)
                if let name = state.eqProfileName {
                    Text("· \(name)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            dspRow("Mode bureau", on: state.eqDeskMode)
            dspRow("Mode mural", on: state.eqWallMode)
            dspRow("Correction de phase", on: state.eqPhaseCorrection)
            dspRow("Filtre passe-haut", on: state.eqHighPassMode)
            dspRow("Sortie caisson", on: state.eqSubwooferOut)
            HStack {
                Text("Graves").foregroundStyle(.secondary)
                Spacer()
                Text(state.bassExtensionLabel)
            }
            .font(.caption2)
            Text("Lecture seule — réglable dans l'app KEF Connect.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Une ligne DSP « libellé … état » en lecture seule.
    private func dspRow(_ label: String, on: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
        }
        .font(.caption2)
    }

    /// Minuterie de veille : extinction différée, gérée côté app.
    @ViewBuilder
    private var sleepTimerControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Minuterie de veille").font(.caption).foregroundStyle(.secondary)
            if let end = state.sleepTimerEnd {
                HStack {
                    Label("Extinction à \(Self.clockLabel(end))", systemImage: "moon.zzz.fill")
                        .font(.caption)
                    Spacer()
                    Button("Annuler") { state.cancelSleepTimer() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            } else {
                Menu {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                        Button("\(minutes) min") { state.startSleepTimer(minutes: minutes) }
                    }
                } label: {
                    Label("Programmer…", systemImage: "moon.zzz")
                }
                .font(.caption)
                .fixedSize()
            }
        }
    }

    /// File d'attente (best-effort). Affichée seulement si l'enceinte en renvoie une.
    private var queueView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File d'attente").font(.caption).foregroundStyle(.secondary)
            ForEach(state.queue.prefix(8)) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(.caption).lineLimit(1)
                    if let artist = item.artist, !artist.isEmpty {
                        Text(artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    /// Formate une heure en `HH:mm`.
    private static func clockLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Pied : paramètres + quitter

    private var footer: some View {
        HStack {
            // Bouton « Paramètres » masqué quand l'écran des réglages est déjà affiché
            // (il a son propre bouton de retour).
            if !showingSettings {
                Button { showSettings = true } label: {
                    Label("Paramètres", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Enceintes et apparence")
            }

            Spacer()

            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }
}

// MARK: - Titre défilant de la barre de menus

/// Texte du label de la barre de menus, en **chasse fixe**, qui défile **en continu** (pixel
/// par pixel) quand il dépasse `AppState.menuBarMaxChars`. La chasse fixe rend la largeur du
/// caractère connue : la fenêtre de clip et la boucle sont donc calculées exactement, et deux
/// copies espacées d'un écart assurent un défilement sans couture. En deçà de la largeur, le
/// texte est affiché tel quel, sans défilement.
struct MenuBarTitle: View {
    let text: String
    /// Décalage du défilement en points (croissant), fourni par `AppState.menuBarScrollOffset`.
    let offset: Double

    /// Police du label : doit correspondre à la mesure `charWidth` ci-dessous.
    private static let font: Font = .system(.body, design: .monospaced)
    /// Largeur d'un caractère de la police à chasse fixe (mesurée une fois).
    private static let charWidth: CGFloat = {
        let nsFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: nsFont]).width
    }()
    /// Écart (en caractères) entre la fin du texte et son recommencement.
    private static let gapChars = 4

    var body: some View {
        if text.count <= AppState.menuBarMaxChars {
            Text(text).font(Self.font)
        } else {
            let piece = text + String(repeating: " ", count: Self.gapChars)
            let loopWidth = CGFloat(piece.count) * Self.charWidth
            let windowWidth = CGFloat(AppState.menuBarMaxChars) * Self.charWidth
            let x = CGFloat(offset).truncatingRemainder(dividingBy: loopWidth)
            HStack(spacing: 0) {
                Text(piece).font(Self.font).fixedSize()
                Text(piece).font(Self.font).fixedSize()
            }
            .offset(x: -x)
            .frame(width: windowWidth, alignment: .leading)
            .clipped()
        }
    }
}

// MARK: - Texte défilant (marquee)

/// Texte sur une seule ligne qui **défile** horizontalement quand il dépasse la largeur
/// disponible ; sous cette largeur il reste fixe. Survoler le texte **met le défilement en
/// pause** là où il en est. Deux copies espacées de `gap` assurent une boucle sans couture.
struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var color: Color = .primary

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var hovering = false
    @State private var ticker = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    private let speed: CGFloat = 30   // points par seconde
    private let gap: CGFloat = 44     // écart entre les deux copies

    /// On ne fait défiler **que si** le texte dépasse réellement la largeur disponible, et
    /// seulement une fois cette largeur connue (`containerWidth > 0`) — sinon un premier rendu
    /// mesurant le texte avant le conteneur déclencherait un faux défilement.
    private var needsScroll: Bool { containerWidth > 0 && textWidth > containerWidth + 2 }

    var body: some View {
        Group {
            if needsScroll {
                HStack(spacing: gap) {
                    Text(text).fixedSize()
                    Text(text).fixedSize()
                }
                .offset(x: -offset)
                .frame(width: containerWidth, alignment: .leading)
                .clipped()
            } else {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
        // Largeur réellement disponible (mesurée quel que soit le contenu affiché).
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { containerWidth = $0 }
            }
        )
        // Largeur réelle du texte, mesurée à part (copie cachée, jamais tronquée).
        .background(
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { textWidth = geo.size.width }
                            .onChange(of: geo.size.width) { textWidth = $0 }
                    }
                ),
            alignment: .leading
        )
        .onHover { hovering = $0 }
        .onReceive(ticker) { _ in
            guard needsScroll, !hovering else { return }
            offset += speed * 0.02
            let span = textWidth + gap
            if span > 0, offset >= span { offset -= span }
        }
        .onChange(of: text) { _ in offset = 0 }
    }
}

// MARK: - Champ de saisie du volume (%)

/// Champ numérique du volume en % : saisie directe au clavier, **flèches ↑/↓ pour ±1**, et
/// validation à la touche Entrée ou à la perte du focus. Réalisé en `NSTextField` car les
/// raccourcis clavier SwiftUI (`onKeyPress`) n'existent qu'à partir de macOS 14, or la cible
/// est macOS 13. La saisie n'est jamais écrasée par les rafraîchissements pendant l'édition.
struct VolumeField: NSViewRepresentable {
    let value: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.alignment = .right
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.stringValue = String(value)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // On ne resynchronise l'affichage que **hors édition**, pour ne pas écraser la saisie.
        if field.currentEditor() == nil {
            let s = String(value)
            if field.stringValue != s { field.stringValue = s }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: VolumeField
        init(_ parent: VolumeField) { self.parent = parent }

        private func clamped(_ v: Int) -> Int {
            min(parent.range.upperBound, max(parent.range.lowerBound, v))
        }

        /// Intercepte les flèches ↑/↓ (±1) et la touche Entrée (validation) du champ.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)):
                bump(+1, in: textView); return true
            case #selector(NSResponder.moveDown(_:)):
                bump(-1, in: textView); return true
            case #selector(NSResponder.insertNewline(_:)):
                // Fin d'édition ⇒ `controlTextDidEndEditing` valide et resynchronise.
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        /// Valide la saisie (Entrée ou perte de focus) : une valeur correcte est bornée et
        /// envoyée ; une entrée vide/invalide est restaurée à la valeur courante.
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let digits = field.stringValue.filter(\.isNumber)
            if let n = Int(digits) {
                let value = clamped(n)
                field.stringValue = String(value)
                parent.onCommit(value)
            } else {
                field.stringValue = String(parent.value)
            }
        }

        /// Flèches ↑/↓ : ajuste de `delta`, met à jour l'affichage et envoie aussitôt.
        private func bump(_ delta: Int, in textView: NSTextView) {
            let current = Int(textView.string.filter(\.isNumber)) ?? parent.value
            let next = clamped(current + delta)
            textView.string = String(next)
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
            parent.onCommit(next)
        }
    }
}
