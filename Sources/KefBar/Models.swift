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

/// Métadonnées de lecture en cours (best-effort — la structure dépend du service source).
struct NowPlaying: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var coverURL: URL?
    var isPlaying: Bool

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
