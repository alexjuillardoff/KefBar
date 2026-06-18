# Architecture de KefBar — détaillée

Comment l'app est structurée et fonctionne, du réseau jusqu'à l'UI. Signatures exactes,
modèle de concurrence, séquencement, pièges, et points d'extension.

---

## 1. Vue d'ensemble & dépendances

Quatre couches + un module transverse :

```
┌─────────────────────────────────────────────┐
│  KefBarApp        scène MenuBarExtra, entrée  │  @main
├─────────────────────────────────────────────┤
│  ContentView      UI SwiftUI (le menu)        │  lit AppState, déclenche ses méthodes
├─────────────────────────────────────────────┤
│  AppState         état observable + actions   │  @MainActor, ObservableObject
├─────────────────────────────────────────────┤
│  KefClient        protocole HTTP/JSON KEF      │  struct sans état, async/await
└─────────────────────────────────────────────┘
        Models  (Source, NowPlaying, KefError)  ← utilisé par toutes les couches
   NowPlayingCenter (touches média + Now Playing macOS)  ← détenu par AppState
```

Graphe de dépendances (qui connaît qui) :

```
KefBarApp ──▶ ContentView ──▶ AppState ──▶ KefClient ──▶ URLSession
                  │                │  │         │
                  │                │  └──▶ NowPlayingCenter ──▶ MediaPlayer (système)
                  └────────────────┴────────────┴──▶ Models
```

Règle : **les dépendances ne pointent que vers le bas**. `KefClient` ignore l'existence de
`AppState` et de l'UI ; `AppState` ignore SwiftUI (il n'importe `SwiftUI` que pour
`ObservableObject`/`@Published`). `NowPlayingCenter` ignore lui aussi l'UI et le réseau : il
ne connaît que `NowPlaying` (Models) et le framework MediaPlayer, et `AppState` lui branche
des callbacks (touches → actions).

## 2. Fichiers & responsabilités

| Fichier | Responsabilité |
|---|---|
| [`KefClient.swift`](../Sources/KefBar/KefClient.swift) | Couche réseau pure. `getData`/`setData` bas niveau + méthodes haut niveau (timeout configurable, `macAddress()`, sonde `identify()`). Aucune dépendance UI. |
| [`Discovery.swift`](../Sources/KefBar/Discovery.swift) | Scan actif du sous-réseau local (`getifaddrs` + sondes `KefClient.identify()` concurrentes) pour découvrir les enceintes KEF. Pur, sans dépendance UI. |
| [`AppState.swift`](../Sources/KefBar/AppState.swift) | `@MainActor ObservableObject` : état `@Published`, orchestration async, polling, debounce, **liste d'enceintes** + scan, persistance (IP active + enceintes). Détient le `NowPlayingCenter`. |
| [`NowPlayingCenter.swift`](../Sources/KefBar/NowPlayingCenter.swift) | `@MainActor`. Pont vers **MediaPlayer** : reçoit les **touches média** physiques (`MPRemoteCommandCenter`) et publie la lecture en cours (`MPNowPlayingInfoCenter`) — ce qui fait de l'app l'application « En cours de lecture » du système, condition pour recevoir ces touches. Aucune dépendance UI/réseau. |
| [`Models.swift`](../Sources/KefBar/Models.swift) | `Source` (enum + libellés FR + SF Symbols), `Speaker` (enceinte connue, identité par MAC), `NowPlaying`, `KefError`. |
| [`ContentView.swift`](../Sources/KefBar/ContentView.swift) | UI déclarative : en-tête/statut, réglages IP, now-playing, transport, slider, picker, footer. |
| [`KefBarApp.swift`](../Sources/KefBar/KefBarApp.swift) | `@main`, `MenuBarExtra(.window)`, `AppDelegate → setActivationPolicy(.accessory)`. |

## 3. Surface d'API

### `KefClient` (struct)

| Méthode | Signature | Endpoint (voir [PROTOCOL.md](PROTOCOL.md)) |
|---|---|---|
| Lecture bas niveau | `getData(path:roles:) async throws -> [String: Any]` | `GET /api/getData` → premier objet du tableau |
| Écriture bas niveau | `setData(path:value:roles:) async throws` | `POST /api/setData` |
| Validation HTTP | `static validate(_:) throws` | rejette hors 2xx |
| Parsing entier tolérant | `static int(_:) -> Int?` | `NSNumber` **ou** `String` |
| Volume (lire) | `volume() async throws -> Int` | `player:volume` |
| Volume (écrire) | `setVolume(_:) async throws` | `player:volume` (clamp 0–100) |
| Power (lire) | `isPoweredOn() async throws -> Bool` | `settings:/kef/host/speakerStatus` |
| Source (lire) | `currentSource() async throws -> Source` | `settings:/kef/play/physicalSource` |
| Source (écrire) | `setSource(_:) async throws` | idem |
| Éteindre | `powerOff() async throws` | `setSource(.standby)` |
| Allumer | `powerOn(_ source: Source = .wifi) async throws` | `setSource(source)` |
| Transport | `playPause()`, `next()`, `previous()` `async throws` | `player:player/control` (`roles=activate`) |
| Now-playing | `nowPlaying() async throws -> NowPlaying?` | `player:player/data` (titre/artiste/album/pochette + **durée** best-effort) |
| Position | `playPosition() async throws -> Int` | `player:player/data/playTime` (`i64_`, ms) |
| Nom appareil | `deviceName() async throws -> String?` | `settings:/deviceName` |
| Évènements (s'abonner) | `subscribeToEvents() async throws -> String` | `POST /api/event/modifyQueue` → UUID de file |
| Évènements (attendre) | `pollEvents(queueId:timeout:) async throws -> Bool` | `GET /api/event/pollQueue` (long-poll) |

### `AppState` (@MainActor ObservableObject)

État publié :

| Propriété | Type | Accès |
|---|---|---|
| `host` | `String` | lecture/écriture (didSet → persiste + reconstruit le client + refresh) |
| `isReachable` | `Bool` | `private(set)` |
| `isOn` | `Bool` | `private(set)` |
| `volume` | `Int` | lecture/écriture |
| `source` | `Source` | `private(set)` |
| `nowPlaying` | `NowPlaying?` | `private(set)` |
| `coverImage` | `NSImage?` | `private(set)` — pochette déjà décodée (chargée par `updateCover`) |
| `positionMs` | `Int` | `private(set)` — position de lecture (ms) |
| `deviceName` | `String?` | `private(set)` |
| `lastError` | `String?` | `private(set)` |
| `isMuted` | `Bool` | calculé : `volume == 0` |

État privé : `client: KefClient?`, `lastSource: Source`, `previousVolume: Int = 20`,
`eventTask`, `positionTask`, `volumeSendTask`, `coverURLShown`/`coverTask`. Clé de persistance :
`"kef.host"` (UserDefaults).

Actions : `refresh()`, `startEventStream()`, `stopEventStream()`, `startPositionTicker()`,
`stopPositionTicker()`, `setVolume(_:)`, `toggleMute()`, `togglePower()`, `select(_:)`,
`playPause()`, `next()`, `previous()`.

### `NowPlayingCenter` (@MainActor, détenu par `AppState`)

| Membre | Type | Rôle |
|---|---|---|
| `onPlayPause` / `onNext` / `onPrevious` | `(() -> Void)?` | callbacks branchés dans `AppState.init` sur `playPause()`/`next()`/`previous()`. |
| `update(nowPlaying:isOn:)` | `func` | appelé à chaque `refresh()` ; publie l'état dans `MPNowPlayingInfoCenter` (idempotent ; ne recharge la pochette que si l'URL change), ou **relâche** le statut « En cours de lecture » si l'enceinte est éteinte/inactive. |

État privé : `commandCenter` (`MPRemoteCommandCenter.shared()`), `infoCenter`
(`MPNowPlayingInfoCenter.default()`), `publishedArtworkURL`, `artworkTask`.

## 4. Modèle de concurrence

| Élément | Choix | Conséquence |
|---|---|---|
| `AppState` | `@MainActor` | toutes les mutations `@Published` sont sur le main thread, sans `DispatchQueue.main`. |
| `KefClient` | `struct` (value type, `Sendable`) | capturable sans risque dans une `Task`, reconstruit quand l'IP change. |
| Appels réseau | `async/await` via `URLSession` | non bloquants ; chaque méthode `KefClient` est `async throws`. |
| Actions UI | `Task { … }` lancées depuis `@MainActor` | reviennent automatiquement sur le main actor en fin de `await`. |
| Build | tools-version **5.9** (mode langage Swift 5) | concurrence stricte Swift 6 désactivée → pas d'erreurs de `Sendable` parasites. |

## 5. Flux de données

### 5.1 Rafraîchissement (lecture)

`refresh()` enchaîne **5 lectures séquentielles** :

```
refresh()
 ├─▶ isPoweredOn()    GET speakerStatus      (try   — échec ⇒ catch global)
 ├─▶ volume()         GET player:volume      (try)
 ├─▶ currentSource()  GET physicalSource     (try)
 ├─▶ nowPlaying()     GET player:player/data (try? — optionnel, n'invalide rien)
 └─▶ deviceName()     GET settings:/deviceName (try? — optionnel)
        ▼
   met à jour les @Published ⇒ SwiftUI redessine
        ▼
   nowPlayingCenter.update(nowPlaying:isOn:) ⇒ Now Playing macOS + touches média
```

Règles de mise à jour notables :
- `if vol > 0 { previousVolume = vol }` — mémorise le dernier volume non nul (pour l'unmute).
- `if src != .standby { source = src; lastSource = src }` — en veille, on **ne** remplace
  **pas** la source affichée par `standby` (on garde la dernière source réelle).
- `nowPlaying`/`deviceName` en `try?` : leur échec n'éteint pas l'indicateur « joignable ».

> **Compromis assumé** : les 5 GET sont **séquentiels** (simple, lisible). On pourrait les
> paralléliser avec `async let` pour diviser la latence — voir §9.

### 5.2 Écriture (action utilisateur)

```
Slider/Bouton ─▶ AppState.<action>()
                   ├─ met à jour l'état local immédiatement (UI réactive)
                   └─ Task { try await client.<call>() ; await refresh() }
```

## 6. Mécanismes précis

### Anti-rebond du volume (150 ms)

`setVolume(_:)` :
1. clamp 0–100 ; si > 0, met à jour `previousVolume` ;
2. écrit `volume` **immédiatement** (l'UI suit le doigt sans latence réseau) ;
3. **annule** la `volumeSendTask` précédente, en programme une nouvelle qui `sleep(150 ms)`
   puis envoie `client.setVolume`.

Effet : un drag qui émet 40 valeurs/s ne déclenche **qu'une** requête HTTP, ~150 ms après
l'arrêt du geste.

```
drag: 12 13 15 18 22 25 (relâché)
                          └─ 150 ms ─▶ une seule requête setVolume(25)
```

### Mute / unmute

`isMuted` est calculé (`volume == 0`). `toggleMute()` :
`setVolume(isMuted ? max(previousVolume, 10) : 0)`. C'est le **soft-mute** (volume 0 +
restauration), indépendant du firmware (cf. [PROTOCOL A.6](PROTOCOL.md#a6-mute--deux-méthodes)).

### Machine d'état power / source

```
        select(s)               togglePower (isOn)
   ┌────────────────┐        ┌──────────────────────┐
   ▼                │        ▼                      │
[Allumé/source]  setSource(s)            powerOff() → standby
   │  ▲                                              │
   │  └────────── powerOn(lastSource) ───────────────┘
   ▼            togglePower (!isOn)
[Veille]
```

- `select(s)` : met `isOn = true`, mémorise `lastSource = s`, écrit la source.
- `togglePower()` : si allumé → `powerOff()` ; sinon → `powerOn(lastSource)` puis `source = lastSource`.
- Toute action se termine par `await refresh()` pour resynchroniser l'état réel.

### Cycle de vie du suivi d'état (push temps réel + ticker de position)

`ContentView` : `.task { await state.refresh(); state.startEventStream(); state.startPositionTicker() }`
à l'ouverture du menu, `.onDisappear { state.stopEventStream(); state.stopPositionTicker() }` à la
fermeture.

- **Flux d'évènements** (`startEventStream`) : `runEventLoop()` s'abonne via
  `subscribeToEvents()` ([PROTOCOL A.8](PROTOCOL.md#a8-push-temps-réel-long-poll)) puis enchaîne
  des long-polls `pollEvents(queueId:timeout: 10)`. Chaque retour — changement signalé **ou**
  expiration du délai — déclenche un `refresh()` qui relit les valeurs faisant foi (modèle
  **hybride** : l'évènement réveille, les accesseurs typés font foi). Réveil quasi instantané sur
  changement de volume/piste, et nettement moins de trafic qu'un sondage 3 s. En cas d'échec
  (firmware sans évènements, file expirée, enceinte injoignable) on rafraîchit quand même puis on
  retente — **repli équivalent à un polling périodique**. Boucle annulable ; un changement de
  `host` la relance pour s'abonner à la nouvelle enceinte.
- **Ticker de position** (`startPositionTicker`) : toutes les secondes, tant que ça joue, relit
  `playPosition()` pour la barre de progression et pousse la position au `NowPlayingCenter`.

> Conséquence : l'état n'est rafraîchi **que menu ouvert**. Pour que l'icône reflète l'état
> menu fermé, il faudrait un suivi permanent (léger) — voir §9.

### Touches média du clavier & « En cours de lecture » ([`NowPlayingCenter.swift`](../Sources/KefBar/NowPlayingCenter.swift))

Faire réagir les touches média physiques (lecture/pause, ⏮, ⏭) **sans permission
d'accessibilité** passe par le framework **MediaPlayer** plutôt que par une capture
bas niveau du clavier (`NSEvent`/`CGEventTap`, qui exigeraient l'autorisation Accessibilité
et captureraient les touches des autres apps) :

1. `MPRemoteCommandCenter.shared()` : on s'abonne aux commandes `togglePlayPause`, `play`,
   `pause`, `nextTrack`, `previousTrack`. Les handlers re-sautent sur le main actor
   (`Task { @MainActor in … }`) et appellent les callbacks branchés par `AppState`. Les
   commandes seek/skip sont **désactivées** ; `changePlaybackPositionCommand` l'est aussi (on
   **affiche** la position mais l'API KEF n'offre pas de seek → barre en lecture seule).
2. `MPNowPlayingInfoCenter.default()` : `update(nowPlaying:isOn:elapsed:)` y publie titre/artiste/
   album + pochette, la **durée** et la **position** (avec le débit de lecture, macOS interpole
   la barre de progression sans rafraîchissement continu), et fixe `playbackState`
   (`.playing`/`.paused`). `updatePosition(elapsed:isPlaying:)` met à jour la seule position pour
   le ticker. **C'est cette publication qui fait de KefBar l'application « En cours de lecture »
   du système** — condition pour que macOS lui route les touches média.

```
enceinte joue  ──refresh──▶ update(np, isOn:true)  ──▶ playbackState=.playing/.paused
                                                        + nowPlayingInfo (titre/pochette)
                                                        ⇒ KefBar devient « Now Playing »
                                                        ⇒ touches média ⇒ onPlayPause/Next/Prev

enceinte off / rien   ─────▶ update(nil, …)  ──▶ playbackState=.stopped, info vidée
                                                 ⇒ KefBar relâche le statut
                                                 ⇒ Musique/Spotify récupèrent les touches
```

Détails :
- **Relâchement volontaire.** Tant que l'enceinte n'est pas l'élément actif (éteinte, ou sans
  lecture), on rend les touches aux autres apps. Une seule app système peut posséder les
  touches média à la fois.
- **Pochette en best-effort.** Téléchargée en tâche annulable, rechargée **seulement** quand
  l'URL change (`publishedArtworkURL`) — sinon chaque rafraîchissement la rechargerait sans cesse.
- **Bundle obligatoire.** L'intégration MediaPlayer exige un `CFBundleIdentifier` : elle ne
  fonctionne **que** depuis `KefBar.app`, pas en `swift run` (cf. §8).

### Pochette dans le popover

Deux pièges, deux parades :

1. **HTTP en clair vers Internet.** L'`icon` du now-playing pointe souvent vers le CDN du
   service en `http://` (p.ex. `resources.tidal.com`). App Transport Security bloque le HTTP
   clair vers un hôte **public** (l'`Info.plist` n'autorise le clair que vers le LAN, via
   `NSAllowsLocalNetworking`). [`KefClient.artworkURL(from:)`](../Sources/KefBar/KefClient.swift)
   relève donc le schéma en `https://` pour les hôtes publics (ces CDN servent en HTTPS) et
   laisse en HTTP les pochettes servies par l'enceinte (IP locale / AirPlay).
2. **`AsyncImage` peu fiable en popover `MenuBarExtra`.** L'image se charge correctement via
   `URLSession`, mais `AsyncImage` ne la rend pas de façon fiable dans ce contexte. `AppState`
   charge donc la pochette lui-même en `NSImage`
   ([`updateCover`](../Sources/KefBar/AppState.swift), rechargée seulement quand l'URL change)
   et `ContentView` l'affiche via `Image(nsImage:)`.

### Gestion d'erreur

`report(_:)` mappe l'erreur vers `lastError` (`LocalizedError.errorDescription` si dispo).
`KefError` ([Models.swift](../Sources/KefBar/Models.swift)) couvre `noHost`, `badStatus(Int)`,
`unexpectedResponse`. En cas d'échec de `refresh()`, `isReachable = false` et le message
s'affiche en rouge dans le menu.

### Persistance

Deux clés `UserDefaults` :
- `kef.host` — IP de l'enceinte **active** (via le `didSet` de `host`).
- `kef.speakers` — liste des enceintes connues (`[Speaker]` encodée en JSON), via le `didSet`
  de `savedSpeakers`.

**Migration** : au démarrage, si `kef.speakers` est vide mais `kef.host` existe (utilisateur
d'une version antérieure), une `Speaker` est créée à partir de l'IP.

### Découverte réseau (`Discovery.swift`)

Scan **actif** du sous-réseau, pas de Bonjour :

```
candidateHosts()                       group de tâches (fenêtre glissante, 64 en vol)
 ├─ getifaddrs() → interfaces en*       ┌─────────────────────────────────────────┐
 │   privées, actives, non-loopback     │ KefClient(ip, timeout: 1,5 s).identify() │
 ├─ adresse & masque → plage d'hôtes    │  └─ getData speakerStatus (propre à KEF) │
 └─ /24 typique = 254 IP (cap 1024)     │     hit ⇒ + deviceName + macAddress      │
                                        └─────────────────────────────────────────┘
                                                  ▼  Speaker? (nil si non-KEF)
                                          tri par IP → AppState.discovered
```

- **Pourquoi un scan HTTP plutôt que `NWBrowser`/Bonjour ?** Le chemin `speakerStatus` est
  spécifique à KEF : seules de vraies enceintes répondent. Bonjour (`_airplay._tcp`) remonterait
  aussi Apple TV, HomePod, Chromecast… L'API étant déjà du HTTP local, aucune permission en plus.
- **Concurrence** : `withTaskGroup` en fenêtre glissante de 64 sondes (< limite de descripteurs
  macOS). Un /24 se scanne en quelques secondes ; la progression `0…1` alimente `scanProgress`.

### Multi-enceintes & identité

`AppState.savedSpeakers: [Speaker]` ; l'enceinte active est celle dont `host == kef.host`.
`Speaker.id = mac ?? host` : la **MAC** sert d'identité stable. Conséquence concrète — si une
enceinte change d'IP (DHCP), un scan la retrouve par sa MAC et `applyScanResults` **met à jour
son IP** (et suit l'enceinte active si c'est elle). À défaut de MAC, l'IP fait office d'identité.

## 7. Entrée & barre de menus

```swift
MenuBarExtra { ContentView().environmentObject(state) }
label: { Image(systemName: state.isOn ? "hifispeaker.fill" : "hifispeaker") }
.menuBarExtraStyle(.window)
```

- `.window` : indispensable pour héberger le **slider** (le style `.menu` ne gère que des items).
- `AppDelegate.applicationDidFinishLaunching` → `NSApp.setActivationPolicy(.accessory)` : masque
  le Dock **même hors bundle** (`swift run`).

## 8. Bundle `.app`, ATS & signature (pièges)

L'API KEF est en **HTTP clair** → **App Transport Security** la bloque par défaut. Parade :
`NSAllowsLocalNetworking` dans [`Resources/Info.plist`](../Resources/Info.plist), **appliqué
uniquement dans un vrai bundle `.app`**.

[`Scripts/build-app.sh`](../Scripts/build-app.sh) :
```
swift build -c release
└─ assemble KefBar.app/Contents/{MacOS/KefBar, Info.plist}
└─ codesign --force --sign -   (signature ad-hoc → pas d'alerte Gatekeeper en local)
```

L'`Info.plist` porte aussi `LSUIElement = true` (pas de Dock) et
`NSLocalNetworkUsageDescription` (autorisation réseau local, macOS Sonoma+).

**Bug shell rencontré & corrigé** : `echo "… $APP…"` collait le caractère unicode `…` au nom
de variable (`unbound variable` sous `set -u`). Corrigé en bordant les variables : `${APP}`.

## 9. Limites et points à valider

L'app **compile et se package** mais n'a **pas été testée sur enceinte physique**. À vérifier :

1. **Now-playing** (`player:player/data`) : structure variable selon le service ; le parsing de
   `KefClient.nowPlaying()` peut nécessiter un ajustement de clés.
2. **Allumage** : KefBar écrit une source réelle (`wifi`) ; à confirmer selon modèle/firmware
   (variante `powerOn` possible — cf. [PROTOCOL A.4](PROTOCOL.md#a4-alimentation-et-source--un-seul-chemin)).
3. **HTTP/ATS** : si échec en `swift run`, passer par le bundle `.app`.
4. **Touches média** : le routage par macOS suppose que l'enceinte renvoie un now-playing
   exploitable (sources Wi-Fi/streaming). Sur une source sans métadonnées (TV, optique…), il
   n'y a pas de « piste » et KefBar relâche logiquement les touches. À confirmer sur matériel.

Détail complet et confiance par point : [VERIFICATION.md](VERIFICATION.md#3-ce-qui-na-pas-été-testé--à-valider-sur-matériel).

## 10. Pistes d'évolution (avec point d'entrée)

| Évolution | Où / comment |
|---|---|
| **Lectures parallèles** | Dans `refresh()`, remplacer les 6 `await` séquentiels par `async let` + `await` groupé. |
| ~~**Push temps réel**~~ ✅ | Fait — `runEventLoop()` s'abonne (`modifyQueue`) et enchaîne les long-polls (`pollQueue`) via `KefClient.subscribeToEvents()`/`pollEvents(...)` ([PROTOCOL A.8](PROTOCOL.md#a8-push-temps-réel-long-poll)). Repli polling si indisponible. |
| ~~**Position / progression**~~ ✅ | Fait — `playPosition()` (`playTime`) + durée du now-playing → barre de progression et position « En cours » macOS. |
| ~~**Multi-enceintes**~~ ✅ | Fait — `AppState.savedSpeakers: [Speaker]` + IP active, sélecteur dans l'en-tête. |
| ~~**Découverte auto**~~ ✅ | Fait — [`Discovery.swift`](../Sources/KefBar/Discovery.swift) scanne le LAN via sondes HTTP (plus fiable que Bonjour : ne remonte **que** des KEF). |
| ~~**Touches média (lecture)**~~ ✅ | Fait — [`NowPlayingCenter.swift`](../Sources/KefBar/NowPlayingCenter.swift) : play/pause, ⏮, ⏭ via le clavier (framework MediaPlayer, sans permission). |
| **Raccourcis clavier — volume** | monter/baisser le volume au clavier sans ouvrir le menu (les touches volume restent gérées par le Mac, pas l'enceinte). |
| **DSP/EQ** | exposer les réglages avancés sur les modèles compatibles. |
| **Polling permanent léger** | démarrer un poll lent au lancement pour que l'icône reflète l'état menu fermé. |

## 11. Construire et lancer

```bash
cd ~/KefBar
swift build                # compilation debug (vérif rapide)
./Scripts/build-app.sh     # bundle .app signé
open ./KefBar.app
# développement :
open Package.swift         # Xcode, ⌘R
```
