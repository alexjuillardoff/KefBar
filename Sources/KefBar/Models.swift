import Foundation

/// Entrées physiques / état d'alimentation des enceintes KEF "W2" (gén. 2).
/// La même valeur `kefPhysicalSource` sert à choisir la source ET à allumer
/// (écrire `standby` met l'enceinte en veille).
enum Source: String, CaseIterable, Identifiable, Hashable {
    case wifi
    case bluetooth
    case tv        // entrée TV / HDMI ARC
    case optic     // optique (TOSLINK)
    case coaxial   // coaxial numérique
    case analog    // entrée analogique / Aux
    case standby   // veille (= éteint)

    var id: String { rawValue }

    /// Chaîne exacte attendue par l'API (`kefPhysicalSource`).
    var apiValue: String { rawValue }

    init?(apiValue: String) { self.init(rawValue: apiValue) }

    /// Sources réellement sélectionnables dans l'UI (la veille est gérée par le bouton power).
    static let selectable: [Source] = [.wifi, .bluetooth, .tv, .optic, .coaxial, .analog]

    var displayName: String {
        switch self {
        case .wifi:      return "Wi-Fi"
        case .bluetooth: return "Bluetooth"
        case .tv:        return "TV / HDMI"
        case .optic:     return "Optique"
        case .coaxial:   return "Coaxial"
        case .analog:    return "Aux (analogique)"
        case .standby:   return "Veille"
        }
    }

    /// Libellé court pour les boutons-raccourcis de source (l'infobulle garde `displayName`).
    var shortName: String {
        switch self {
        case .wifi:      return "Wi-Fi"
        case .bluetooth: return "Bluetooth"
        case .tv:        return "TV/HDMI"
        case .optic:     return "Optique"
        case .coaxial:   return "Coaxial"
        case .analog:    return "Aux"
        case .standby:   return "Veille"
        }
    }

    var systemImage: String {
        switch self {
        case .wifi:      return "wifi"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .tv:        return "tv"
        case .optic:     return "fibrechannel"
        case .coaxial:   return "cable.connector"
        case .analog:    return "cable.connector.horizontal"
        case .standby:   return "power"
        }
    }
}

/// Apparence du label affiché dans la barre de menus macOS (icône, texte, ou les deux).
/// Persisté en `String` (rawValue) dans UserDefaults.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon
    case text
    case both

    var id: String { rawValue }

    /// Libellé du segment dans les réglages.
    var label: String {
        switch self {
        case .icon: return "Icône"
        case .text: return "Texte"
        case .both: return "Icône + texte"
        }
    }

    /// `true` si ce style affiche le texte personnalisé (donc le champ de saisie est utile).
    var showsText: Bool { self != .icon }
    /// `true` si ce style affiche l'icône.
    var showsIcon: Bool { self != .text }
}

/// Ce que le texte de la barre de menus affiche : un libellé fixe saisi par l'utilisateur,
/// ou le morceau en cours de lecture (titre). Persisté en `String` (rawValue) dans UserDefaults.
enum MenuBarTextSource: String, CaseIterable, Identifiable {
    case custom
    case nowPlaying

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom:     return "Texte fixe"
        case .nowPlaying: return "Morceau en cours"
        }
    }
}

/// Une enceinte KEF connue de l'app (découverte ou ajoutée à la main).
///
/// L'identité stable est l'**adresse MAC** quand on la connaît : l'IP peut changer
/// (DHCP), pas la MAC. À défaut de MAC, on retombe sur l'IP. Cela permet de suivre
/// une enceinte dont l'IP a bougé et de gérer plusieurs enceintes sans collision.
struct Speaker: Identifiable, Codable, Hashable {
    /// Adresse IP actuelle (hôte HTTP de l'API KEF).
    var host: String
    /// Nom affiché (nom de l'appareil renvoyé par l'enceinte, ou libellé par défaut).
    var name: String
    /// Adresse MAC (`settings:/system/primaryMacAddress`) si connue — identité stable.
    var mac: String?

    /// Identifiant stable : la MAC si disponible, sinon l'IP.
    var id: String { mac ?? host }

    /// Libellé par défaut quand le nom de l'appareil n'est pas (encore) connu.
    static let defaultName = "Enceinte KEF"

    init(host: String, name: String = Speaker.defaultName, mac: String? = nil) {
        self.host = host
        self.name = name.isEmpty ? Speaker.defaultName : name
        self.mac = mac
    }
}

/// Mode de lecture (répétition / aléatoire) — chemin `settings:/mediaPlayer/playMode`.
///
/// ⚠️ Les chaînes exactes (`repeatAll`, `repeatOne`, `shuffle`…) sont **rétro-ingénieriées**
/// et **non vérifiées sur matériel** : selon le firmware/service, l'API peut combiner
/// répétition et aléatoire différemment. On modélise donc un **cycle** de modes mutuellement
/// exclusifs (le plus robuste), et la lecture tolère une valeur inconnue (`.unknown`).
enum PlayMode: String, CaseIterable, Hashable {
    case normal
    case repeatAll
    case repeatOne
    case shuffle

    /// Valeur renvoyée/écrite par l'API (`string_`).
    var apiValue: String { rawValue }

    /// Tolérant : une chaîne non reconnue retombe sur `.normal`.
    init(apiValue: String) { self = PlayMode(rawValue: apiValue) ?? .normal }

    /// Mode suivant dans le cycle (bouton unique couvrant répétition et aléatoire).
    var next: PlayMode {
        switch self {
        case .normal:    return .repeatAll
        case .repeatAll: return .repeatOne
        case .repeatOne: return .shuffle
        case .shuffle:   return .normal
        }
    }

    var displayName: String {
        switch self {
        case .normal:    return "Lecture normale"
        case .repeatAll: return "Répéter tout"
        case .repeatOne: return "Répéter la piste"
        case .shuffle:   return "Aléatoire"
        }
    }

    var systemImage: String {
        switch self {
        case .normal:    return "arrow.forward.to.line"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle:   return "shuffle"
        }
    }

    /// `true` quand un mode non neutre est actif (pour mettre le bouton en évidence).
    var isActive: Bool { self != .normal }
}

/// Un élément de la file d'attente (`playlists:pq/getitems`) ou une piste à venir.
/// Best-effort : la structure des « rows » KEF est mal documentée (cf. PROTOCOL.md A.11).
struct QueueItem: Identifiable, Hashable {
    let id: Int
    var title: String
    var artist: String?
}

/// Métadonnées de lecture en cours (best-effort — la structure dépend du service source).
struct NowPlaying: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var coverURL: URL?
    var isPlaying: Bool
    /// Durée totale de la piste en millisecondes, si l'enceinte la communique (best-effort :
    /// le champ varie selon le service source — voir `KefClient.nowPlaying()`).
    var durationMs: Int?

    var isEmpty: Bool { (title?.isEmpty ?? true) && (artist?.isEmpty ?? true) }
}

enum KefError: LocalizedError {
    case noHost
    case badStatus(Int)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .noHost:             return "Aucune adresse IP d'enceinte configurée."
        case .badStatus(let code): return "L'enceinte a répondu avec le code HTTP \(code)."
        case .unexpectedResponse:  return "Réponse inattendue de l'enceinte."
        }
    }
}
