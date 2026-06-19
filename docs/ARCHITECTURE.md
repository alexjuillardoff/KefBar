# Architecture de KefBar — détaillée

Comment l'app est structurée et fonctionne, du réseau jusqu'à l'UI. Signatures exactes,
modèle de concurrence, séquencement, pièges, et points d'extension.

---

## 1. Vue d'ensemble & dépendances

Quatre couches + un module transverse :

```
┌─────────────────────────────────────────────┐
│  KefBarApp        @main, AppDelegate          │  crée AppState + MenuBarController
├─────────────────────────────────────────────┤
│  MenuBarController  NSStatusItem + NSPopover  │  AppKit : barre de menus (texte + boutons)
├─────────────────────────────────────────────┤
│  ContentView      UI SwiftUI (le popover)     │  lit AppState, déclenche ses méthodes
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
KefBarApp ──▶ MenuBarController ──▶ ContentView ──▶ AppState ──▶ KefClient ──▶ URLSession
                  │                     │              │  │         │
                  │                     │              │  └──▶ NowPlayingCenter ──▶ MediaPlayer
                  └─────────────────────┴──────────────┴────────────┴──▶ Models
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
| [`Discovery.swift`](../Sources/KefBar/Discovery.swift) | Scan actif du sous-réseau (`getifaddrs` + sondes `KefClient.identify()` concurrentes) pour les enceintes **réveillées**, **et** résolution d'endpoint (`resolveEndpoint` : endpoints connus puis **scan de ports** `poll` groupé) pour retrouver le port de l'API. Pur, sans dépendance UI. |
| [`BonjourDiscovery.swift`](../Sources/KefBar/BonjourDiscovery.swift) | **Complément Bonjour** du scan actif. Parcourt `_airplay._tcp`, résout le TXT, filtre `manufacturer=KEF`, et renvoie nom + MAC (`deviceid`) + IPv4. Repère l'enceinte **même en veille** (API port-80 endormie), là où le scan actif échoue. `@MainActor`. |
| [`AppState.swift`](../Sources/KefBar/AppState.swift) | `@MainActor ObservableObject` : état `@Published`, orchestration async, polling, debounce, **liste d'enceintes** + scan, persistance (IP active + enceintes). Détient le `NowPlayingCenter`. |
| [`NowPlayingCenter.swift`](../Sources/KefBar/NowPlayingCenter.swift) | `@MainActor`. Pont vers **MediaPlayer** : reçoit les **touches média** physiques (`MPRemoteCommandCenter`) et publie la lecture en cours (`MPNowPlayingInfoCenter`) — ce qui fait de l'app l'application « En cours de lecture » du système, condition pour recevoir ces touches. Aucune dépendance UI/réseau. |
| [`Models.swift`](../Sources/KefBar/Models.swift) | `Source` (enum + libellés FR + SF Symbols), `Speaker` (enceinte connue, identité par MAC), `PlayMode` (cycle répétition/aléatoire), `QueueItem`, `NowPlaying`, `KefError`. |
| [`ContentView.swift`](../Sources/KefBar/ContentView.swift) | UI déclarative du **lecteur** : en-tête (enceinte, IP, point d'état, bouton allumer/éteindre), **sélecteur de source en boutons-raccourcis carrés** (icône + libellé `shortName`, taille calculée pour paver la largeur), now-playing (pochette + titre/artiste/album **défilants**, pause au survol — `MarqueeText`), barre de progression **interactive** (`SeekBar` — clic/glissement → seek), transport (Boucle à gauche, puis précédent/pause/suivant), volume (slider pleine largeur + boutons −/+ par pas de 1, puis icône haut-parleur/muet + niveau **en % éditable** au clavier — `VolumeField`), **réglages avancés** (DSP, minuterie de veille, file d'attente), pied (Paramètres + Quitter). Route vers `SettingsView` quand les réglages sont ouverts (ou tant qu'aucune enceinte n'existe). Inclut les vues utilitaires `SeekBar` (barre de progression cliquable/glissable), `MarqueeText`, `VolumeField`, et **`MenuBarTitle`** (texte à chasse fixe qui défile dans la barre de menus). |
| [`SettingsView.swift`](../Sources/KefBar/SettingsView.swift) | **Écran dédié des réglages**, affiché à la place du lecteur : gestion des enceintes (liste, scan réseau, ajout par IP), **personnalisation complète de la barre de menus** (bascules indépendantes : icône, titre, artiste, timecode, et boutons marche/arrêt, précédent, lecture/pause, suivant, muet), lancement au démarrage. Bouton « Terminé » pour revenir (masqué tant qu'aucune enceinte n'est enregistrée). |
| [`MenuBarController.swift`](../Sources/KefBar/MenuBarController.swift) | **Propriétaire AppKit de la barre de menus.** Un `NSStatusItem` héberge une vue SwiftUI `MenuBarRootView` (texte **et boutons cliquables** aux actions distinctes), et un `NSPopover` présente `ContentView`. Remplace `MenuBarExtra`, dont le label est une zone de clic unique incapable d'héberger plusieurs boutons. Pilote `popoverAppeared()`/`popoverDisappeared()`. |
| [`KefBarApp.swift`](../Sources/KefBar/KefBarApp.swift) | `@main`, scène `Settings` vide (pas de fenêtre principale). `@MainActor AppDelegate` crée l'`AppState` partagé + le `MenuBarController` et applique `setActivationPolicy(.accessory)`. |

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
| Seek (**non vérifié**) | `seek(toMs:) async throws` | `player:player/control` forme étendue `{"control":"seek","i64_":<ms>}` |
| Now-playing | `nowPlaying() async throws -> NowPlaying?` | `player:player/data` (titre/artiste/album/pochette + **durée** best-effort) |
| Position | `playPosition() async throws -> Int` | `player:player/data/playTime` (`i64_`, ms) |
| Nom appareil | `deviceName() async throws -> String?` | `settings:/deviceName` |
| Volume max / pas | `maximumVolume()` / `volumeStep() async throws -> Int?` | `settings:/kef/host/maximumVolume` · `…/volumeStep` (`i16_`) |
| Mode lecture (lire/écrire) | `playMode()` / `setPlayMode(_:) async throws` | `settings:/mediaPlayer/playMode` (type `playerPlayMode` ; écriture refusée hors lecture) |
| DSP (**lecture seule**) | `eqProfile() async throws -> [String: Any]?` | `kef:eqProfile/v2` — écriture 401 ([PROTOCOL A.12](PROTOCOL.md#a12-dsp--profil-eq--kefeqprofilev2-lecture-seule)) |
| File d'attente | `playQueue() async throws -> [QueueItem]` | `playlists:pq/getitems` (`roles=rows`, vide = `[null]`) |
| Notifications | `notifications() async throws -> [String]` | `notifications:/display/queue` (`roles=rows`) |
| Évènements (s'abonner) | `subscribeToEvents() async throws -> String` | `POST /api/event/modifyQueue` → UUID de file |
| Évènements (attendre) | `pollEvents(queueId:timeout:) async throws -> Bool` | `GET /api/event/pollQueue` (long-poll) |

> Lecture **`rows`** : `getDataArray(path:roles:)` (privée) renvoie **tout** le tableau de
> réponse (en ne gardant que les objets — une file vide vaut `[null]`), contrairement à
> `getData` qui n'en prend que le premier objet. Helpers tolérants : `string(_:)` (chaîne
> typée), `typedObject(_:)` (objet typé + son `type`), `anyInt(_:)` (entier quelle que soit la
> largeur — `i16_`/`i32_`/`i64_`… ; nécessaire car `volumeStep` arrive en `i16_`).

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
| `playMode` | `PlayMode` | `private(set)` — répétition / aléatoire |
| `maxVolume` | `Int` | `private(set)` — plafond du slider (les boutons −/+ vont par pas de 1) |
| `eqAvailable`, `eqDeskMode`, `eqWallMode`, `eqPhaseCorrection`, `eqHighPassMode`, `eqSubwooferOut` | `Bool` | `private(set)` — miroirs DSP **lecture seule** |
| `eqProfileName` | `String?` | `private(set)` — nom du profil DSP |
| `eqBassExtension` / `eqTrebleAmount` | `String` / `Int` | `private(set)` — graves (`standard`/`less`/`extra`) · aigus |
| `queue` | `[QueueItem]` | `private(set)` — best-effort |
| `notifications` | `[String]` | `private(set)` — best-effort |
| `sleepTimerEnd` | `Date?` | `private(set)` — heure d'extinction programmée |
| `launchAtLogin` | `Bool` | lecture/écriture (didSet → `SMAppService`) |

État privé : `client: KefClient?`, `lastSource: Source`, `previousVolume: Int = 20`,
`eventTask`, `positionTask`, `volumeSendTask`, `coverURLShown`/`coverTask`, profil DSP brut
(`eqType`/`eqValue`), caches par enceinte (`volumeConfigLoaded`/`eqLoaded`), `sleepTask`. Clés
de persistance : `"kef.host"` + `"kef.speakers"` (UserDefaults). `launchAtLogin` n'est pas
persisté dans UserDefaults : il **reflète** l'état réel du login item (`SMAppService.mainApp.status`).

Actions : `refresh()`, `startEventStream()`, `stopEventStream()`, `startPositionTicker()`,
`stopPositionTicker()`, `setVolume(_:)`, `nudgeVolume(up:)` (±1), `toggleMute()`, `togglePower()`,
`select(_:)`, `playPause()`, `next()`, `previous()`, `seek(toMs:)` (optimiste + anti-rebond
150 ms, comme le volume), `cyclePlayMode()`, `refreshEQ()` (lecture seule), `refreshQueue()`,
`refreshNotifications()`, `startSleepTimer(minutes:)`, `cancelSleepTimer()`.

> **Configuration peu changeante** (plafond de volume, profil DSP) : lue **une seule fois
> par enceinte** en fin de `refresh()` (`loadSpeakerConfigIfNeeded()`, drapeaux
> `volumeConfigLoaded`/`eqLoaded` remis à zéro au changement d'`host` par `resetPerSpeakerState()`).
> File d'attente et notifications : chargées **à la demande** (ouverture du panneau « Réglages
> avancés »), pour ne pas alourdir le rafraîchissement.

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

`refresh()` enchaîne des **lectures séquentielles** (les 3 premières font foi pour
« joignable » ; les suivantes sont optionnelles en `try?`) :

```
refresh()
 ├─▶ isPoweredOn()    GET speakerStatus      (try   — échec ⇒ catch global)
 ├─▶ volume()         GET player:volume      (try)
 ├─▶ currentSource()  GET physicalSource     (try)
 ├─▶ nowPlaying()     GET player:player/data (try? — optionnel, n'invalide rien)
 ├─▶ deviceName()     GET settings:/deviceName (try? — optionnel)
 ├─▶ playPosition()   GET player/data/playTime (try? — optionnel)
 └─▶ playMode()       GET mediaPlayer/playMode (try? — optionnel)
        ▼
   met à jour les @Published ⇒ SwiftUI redessine
        ▼
   loadSpeakerConfigIfNeeded()  ⇒ 1ʳᵉ fois/enceinte : maxVolume, eqProfile
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
1. clamp 0–100 ; si le cran change, joue un **retour haptique** (`hapticTick()`,
   `NSHapticFeedbackManager` motif `.levelChange` — silencieux sans trackpad Force Touch) ;
2. si > 0, met à jour `previousVolume` ;
3. écrit `volume` **immédiatement** (l'UI suit le doigt sans latence réseau) ;
4. **annule** la `volumeSendTask` précédente, en programme une nouvelle qui `sleep(150 ms)`
   puis envoie `client.setVolume`.

> Le haptique ne se déclenche qu'au changement effectif de cran : il accompagne le drag du
> slider et les boutons −/+ / muet (qui passent tous par `setVolume`), pas les mises à jour
> issues du rafraîchissement (qui écrivent `volume` directement).

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
   commandes seek/skip avant/arrière sont **désactivées**, mais `changePlaybackPositionCommand`
   est **active** : le scrubber de la pastille « En cours de lecture » déplace la tête de lecture
   via `onSeek` → `AppState.seek(toMs:)` (seek best-effort, cf. KefClient — non vérifié matériel).
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
2. **`AsyncImage` peu fiable dans le popover de la barre de menus.** L'image se charge correctement via
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

### Découverte réseau (`Discovery.swift` + `BonjourDiscovery.swift`)

**Deux sources fusionnées par MAC**, lancées en parallèle dans `AppState.scan()` :

```
scan actif (Discovery)                 group de tâches (fenêtre glissante, 64 en vol)
 ├─ getifaddrs() → interfaces en*       ┌─────────────────────────────────────────┐
 │   privées, actives, non-loopback     │ KefClient(ip, timeout: 1,5 s).identify() │
 ├─ adresse & masque → plage d'hôtes    │  └─ getData speakerStatus (propre à KEF) │
 └─ /24 typique = 254 IP (cap 1024)     │     hit ⇒ + deviceName + macAddress      │
                                        └─────────────────────────────────────────┘
                                                  ▼  enceintes RÉVEILLÉES (port 80)
Bonjour (BonjourDiscovery)
 └─ _airplay._tcp → résout TXT          ┌─────────────────────────────────────────┐
     manufacturer=KEF ? (filtre)        │ deviceid (MAC) + model (nom) + IPv4      │
                                        └─────────────────────────────────────────┘
                                                  ▼  enceintes MÊME EN VEILLE
                              mergeDiscovery (dédup par macKey) → AppState.discovered
```

- **Pourquoi le complément Bonjour ?** Une enceinte en **veille endort son API HTTP** : le port 80
  expire (timeout), donc le scan actif ne la voit plus du tout — symptôme « ne trouve plus
  l'enceinte ». Mais elle **reste annoncée en AirPlay** ; son TXT porte `manufacturer=KEF`,
  `model` et `deviceid` (la MAC). Le filtre `manufacturer=KEF` écarte Apple TV / HomePod /
  Chromecast (l'objection initiale à Bonjour). Bonjour donne donc l'enceinte **et son identité
  stable** même injoignable, ce qui permet de la reconnecter dès son réveil.
- **Pourquoi garder aussi le scan actif ?** Le chemin `speakerStatus` confirme une vraie KEF
  réveillée et fournit son nom/MAC depuis l'appareil ; il reste la source faisant foi quand
  l'enceinte répond. Les deux sont fusionnés par `mergeDiscovery`, le scan actif primant sur
  l'hôte/nom en cas de doublon (port-80 confirmé).
- **Concurrence** : `withTaskGroup` en fenêtre glissante de 64 sondes (< limite de descripteurs
  macOS). Un /24 se scanne en quelques secondes ; la progression `0…1` alimente `scanProgress`.

### Multi-enceintes & identité

`AppState.savedSpeakers: [Speaker]` ; l'enceinte active est celle dont `host == kef.host`.
`Speaker.id = mac ?? host` : la **MAC** sert d'identité stable. Conséquence concrète — si une
enceinte change d'IP (DHCP), un scan la retrouve par sa MAC et `applyScanResults` **met à jour
son IP** (et suit l'enceinte active si c'est elle). À défaut de MAC, l'IP fait office d'identité.
La même MAC arrive sous deux formats selon la source (`primaryMacAddress` en port-80 vs `deviceid`
Bonjour) : on compare donc toujours via `Speaker.macKey` (minuscules, séparateurs retirés), jamais
le champ `mac` brut.

### Endpoint de l'API & reconnexion automatique

Chaque `Speaker` mémorise l'**endpoint** résolu de son API (`scheme` + `port`, exposé via
`Speaker.endpoint`) ; `AppState.makeClient(for:)` en fait un `KefClient` ciblant directement ce
transport. La résolution (`Discovery.resolveEndpoint`) essaie d'abord les endpoints connus
(`https:4430`, `http:80`), puis **balaie les ports** de l'enceinte (`openPorts`, 1…10000, `poll`
groupé) et teste l'API KEF sur chaque port ouvert — ce qui rend l'app robuste à un futur
déplacement de l'API (comme `http:80` → `https:4430` en 2024).

Quand l'enceinte active devient **injoignable**, la boucle d'évènements appelle
`recoverConnectionIfDue()` (throttle à **backoff exponentiel**, 20 s → 5 min, réarmé dès qu'on
est joignable) : (1) re-résoudre l'endpoint sur l'IP courante (le port a pu bouger), sinon
(2) **redécouvrir par MAC** (Bonjour + scan) pour suivre un changement d'IP DHCP, puis re-résoudre.

## 7. Entrée & barre de menus

L'app **n'a pas de fenêtre principale** : `KefBarApp` ne déclare qu'une scène `Settings` vide,
et tout vit dans la barre de menus, gérée en **AppKit** par `MenuBarController`.

```swift
// KefBarApp : @MainActor AppDelegate
state = AppState()
menuBar = MenuBarController(state: state)      // NSStatusItem + NSPopover
NSApp.setActivationPolicy(.accessory)          // pas d'icône Dock, même hors bundle
```

**Pourquoi pas `MenuBarExtra` ?** Son label est une **zone de clic unique** qui ne fait
qu'ouvrir le popover : impossible d'y mettre plusieurs boutons aux actions distinctes. Pour de
vrais contrôles cliquables dans la barre de menus, on pose une vue SwiftUI (`MenuBarRootView`)
dans le bouton d'un `NSStatusItem` (calée sur ses bords par autolayout ⇒ largeur intrinsèque),
et on présente `ContentView` dans un `NSPopover` (`.transient`) ouvert/fermé à la demande.

- **Customisation « de A à Z »** : chaque élément a une bascule persistée (`AppState.MenuBarFlag`) —
  texte (`menuBarShowIcon`/`Title`/`Artist`/`Timecode`) et boutons (`menuBarShowPower`/`Previous`/
  `PlayPause`/`Next`/`Mute`). `menuBarFullText` compose `Titre — Artiste · position / durée` à
  partir des éléments textuels activés. L'icône s'affiche **d'office** si aucun texte n'est visible,
  pour garder un point d'accès au popover.
- **Défilement (marquee) fluide** : sous `menuBarMaxChars` (28) le texte est affiché tel quel ;
  au-delà, la vue `MenuBarTitle` le fait **glisser pixel par pixel** dans une fenêtre clippée de
  largeur fixe (deux copies espacées d'un écart, bouclage sans couture). Le texte est en **chasse
  fixe** : la largeur du caractère est connue (mesurée via `NSFont`), donc le clip et la boucle
  sont exacts. `menuBarScrollTask` avance `menuBarScrollOffset` en **points** (~30 pts/s à ~30 fps,
  purement local) ; la vue reboucle l'offset par modulo.
- **Suivi popover fermé** : normalement le flux d'évènements (`menuBarNeedsLiveState`) et le
  compteur de position (`menuBarNeedsPosition`, pour le timecode) ne tournent que popover ouvert.
  Dès qu'un élément de la barre de menus reflète l'état live (texte ou boutons lecture/muet/power),
  `updateLiveTracking` les maintient actifs **même popover fermé**. `MenuBarController` appelle
  `popoverAppeared()`/`popoverDisappeared()` ; `updateLiveTracking` pilote aussi `menuBarScrollTask`
  et reste idempotent (ne relance pas ce qui tourne déjà).
- Le slider du popover impose toujours un `NSPopover` (style « fenêtre »), pas un menu d'items.

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
5. **Mode de lecture** (`settings:/mediaPlayer/playMode`) ✅ lecture vérifiée (type
   `playerPlayMode`). **Écriture refusée hors lecture (HTTP 401)** → bouton désactivé tant que
   rien ne joue ; les libellés des modes ≠ `normal` restent à confirmer (cf.
   [PROTOCOL A.11](PROTOCOL.md#a11-mode-de-lecture-file-dattente--notifications)).
6. **DSP / `kef:eqProfile/v2`** ✅ lecture vérifiée (chemin/type/clés réels). **Écriture
   impossible** par cette voie (HTTP 401, objet complet *ou* partiel ; feuilles inexistantes)
   → KefBar **affiche** le DSP en **lecture seule**. Le mécanisme d'écriture de KEF Connect
   reste à percer (cf. [PROTOCOL A.12](PROTOCOL.md#a12-dsp--profil-eq--kefeqprofilev2-lecture-seule)).
7. **File d'attente / notifications** (`roles=rows`) ✅ chemins valides ; **vide = `[null]`**.
   Parsing défensif (objets seulement), affichage masqué si rien d'exploitable. Le rendu d'une
   file **non vide** reste à voir en lecture réelle.
8. **Lancement au démarrage** : `SMAppService.mainApp` exige le **bundle `.app`** (un
   `CFBundleIdentifier`) ; sans lui (`swift run`), l'enregistrement échoue proprement et
   l'interrupteur se resynchronise sur l'état réel.

Détail complet et confiance par point : [VERIFICATION.md](VERIFICATION.md#3-ce-qui-na-pas-été-testé--à-valider-sur-matériel).

## 10. Pistes d'évolution (avec point d'entrée)

| Évolution | Où / comment |
|---|---|
| **Lectures parallèles** | Dans `refresh()`, remplacer les 6 `await` séquentiels par `async let` + `await` groupé. |
| ~~**Push temps réel**~~ ✅ | Fait — `runEventLoop()` s'abonne (`modifyQueue`) et enchaîne les long-polls (`pollQueue`) via `KefClient.subscribeToEvents()`/`pollEvents(...)` ([PROTOCOL A.8](PROTOCOL.md#a8-push-temps-réel-long-poll)). Repli polling si indisponible. |
| ~~**Position / progression**~~ ✅ | Fait — `playPosition()` (`playTime`) + durée du now-playing → barre de progression et position « En cours » macOS. **Barre interactive** : clic/glissement → `seek(toMs:)` (commande `seek` best-effort, non vérifiée matériel) ; scrubber « En cours » macOS également actif. |
| ~~**Multi-enceintes**~~ ✅ | Fait — `AppState.savedSpeakers: [Speaker]` + IP active, sélecteur dans l'en-tête. |
| ~~**Découverte auto**~~ ✅ | Fait — [`Discovery.swift`](../Sources/KefBar/Discovery.swift) scanne le LAN via sondes HTTP, **complété par** [`BonjourDiscovery.swift`](../Sources/KefBar/BonjourDiscovery.swift) (`_airplay._tcp`, filtre `manufacturer=KEF`) qui repère aussi l'enceinte **en veille** (port 80 endormi). Fusion par MAC dans `mergeDiscovery`. |
| ~~**Résolution de port / reconnexion auto**~~ ✅ | Fait — `Discovery.resolveEndpoint` (endpoints connus puis **scan de ports** `poll` groupé) mémorise `scheme`/`port` sur le `Speaker` ; `AppState.recoverConnectionIfDue()` reconnecte tout seul (backoff) sur port déplacé ou IP DHCP changée. |
| ~~**Touches média (lecture)**~~ ✅ | Fait — [`NowPlayingCenter.swift`](../Sources/KefBar/NowPlayingCenter.swift) : play/pause, ⏮, ⏭ via le clavier (framework MediaPlayer, sans permission). |
| ~~**Mode de lecture (repeat/shuffle)**~~ ✅ | Fait — `cyclePlayMode()` (`settings:/mediaPlayer/playMode`), bouton unique dans le transport ([PROTOCOL A.11](PROTOCOL.md#a11-mode-de-lecture-file-dattente--notifications)). |
| ~~**Limite de volume**~~ ✅ | Fait — `maximumVolume()` borne le slider (les boutons −/+ vont par pas de 1). |
| **DSP/EQ** ✅ lecture / ❌ écriture | Fait en **lecture seule** — affichage du profil (`kef:eqProfile/v2`). L'écriture est refusée (HTTP 401) : reste à rétro-ingénierier le mécanisme de KEF Connect ([PROTOCOL A.12](PROTOCOL.md#a12-dsp--profil-eq--kefeqprofilev2-lecture-seule)). |
| ~~**Minuterie de veille**~~ ✅ | Fait — `startSleepTimer(minutes:)` programme un `powerOff()` différé (côté app). |
| ~~**File d'attente**~~ ✅ | Fait (best-effort) — `playQueue()` (`playlists:pq/getitems`, `rows`), liste dans les réglages avancés. |
| ~~**Lancement au démarrage**~~ ✅ | Fait — interrupteur `launchAtLogin` via `SMAppService.mainApp` (bundle requis). |
| **Raccourcis clavier — volume** | monter/baisser le volume au clavier sans ouvrir le menu (les touches volume restent gérées par le Mac, pas l'enceinte). |
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
