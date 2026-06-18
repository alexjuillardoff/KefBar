<div align="center">

# 🔊 KefBar

**Control your KEF Wi-Fi speakers from the macOS menu bar.**
**Pilotez vos enceintes KEF Wi-Fi depuis la barre de menus macOS.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A tiny, native **macOS menu bar app** to control **KEF 2nd-generation Wi-Fi speakers** —
**LSX II, LS50 Wireless II, LS60 Wireless, KEF XIO** — over their local HTTP/JSON API.
No KEF Connect app, no cloud, no account: everything stays on your local network.

[English](#-english) · [Français](#-français) · [Documentation](docs/README.md) · [Step-by-step guide](docs/GUIDE.md)

</div>

---

## 🇬🇧 English

### Why KefBar?

The official **KEF Connect** app is mobile-only and there is **no official desktop app or
public API**. KefBar gives Mac users a lightweight alternative: a menu-bar icon that lets you
change volume, switch sources and control playback on your KEF speakers without leaving your
keyboard — using the same undocumented local API that the KEF Connect app uses under the hood.

### Features

- 🔍 **Auto-discovery** — scan your network to find KEF speakers automatically (no IP hunting)
- 🔀 **Multiple speakers** — save several speakers and switch between them from the menu bar
- ✏️ **Manual IP** — add a speaker by typing its address, too
- 🔈 **Volume** — full-width slider (debounce + haptic feedback) framed by −/+ buttons; below it a speaker icon that mutes on click and the level as an **editable percentage** (type a value, or ↑/↓ arrows for ±1)
- ⏻ **Power on / standby**
- 🎛️ **Source selector** — shortcut buttons for Wi-Fi, Bluetooth, TV/HDMI, Optical, Coaxial, Aux
- ⏯️ **Transport** — play / pause, next / previous track
- 🔁 **Play mode** — cycle repeat-all / repeat-one / shuffle from the transport row
- 🔒 **Volume limit** — the slider respects the speaker's maximum-volume setting; −/+ buttons step by 1
- 🎛️ **DSP / EQ** *(read-only)* — shows desk/wall mode, phase correction, high-pass, sub out, bass & treble from `kef:eqProfile/v2` (writing is rejected by the speaker — see below)
- ⏲️ **Sleep timer** — auto power-off after 15 / 30 / 45 / 60 / 90 min
- 🗒️ **Play queue** *(best-effort)* — upcoming tracks, shown in advanced settings
- ⌨️ **Media keys** — the Mac's physical play/pause, ⏮/⏭ keys control the speaker; playback also shows up in Control Center
- 🎵 **Now playing** — album artwork plus title, artist and album that **scroll** when too long (hover to pause), and a **progress bar** (elapsed / total)
- 🔄 **Real-time updates** — subscribes to the speaker's event stream (long-poll) for near-instant refresh, with a polling fallback
- 🚀 **Launch at login** — optional, via `SMAppService`
- 🪶 **No Dock icon** — lives quietly in the menu bar (accessory app)

> ⚠️ Verified on an LSX II: **DSP is read-only** — the speaker rejects writes to
> `kef:eqProfile/v2` (HTTP 401), so KefBar only displays it. The **play-mode** button is
> disabled while nothing is playing (the speaker refuses mode writes without an active
> session). *Best-effort* features (play queue, notifications) hide when empty. See
> [docs/PROTOCOL.md](docs/PROTOCOL.md) §A.11–A.12.

> 💡 DHCP-friendly: speakers are remembered by their **MAC address**, so if a speaker's IP
> changes, a rescan finds it again and updates the stored address automatically.

### Supported speakers

| Generation | Models | Supported |
|---|---|---|
| **2nd gen (W2 platform)** | LSX II, LS50 Wireless II, LS60 Wireless, KEF XIO | ✅ yes |
| 1st gen | LSX, LS50 Wireless | ❌ no (different protocol — see [aiokef](https://github.com/basnijholt/aiokef) / [kefctl](https://github.com/kraih/kefctl)) |

### Requirements

- macOS 13 Ventura or newer
- Xcode 15+ / Swift 5.9+ toolchain (to build from source)
- Your Mac and the speaker on the **same Wi-Fi network**
- The speaker's IP is found for you by the built-in **network scan** — or enter it manually
  (KEF Connect app → Settings → your speaker → Info → IP address).

### Quick start

```bash
git clone https://github.com/alexjuillardoff/KefBar.git
cd KefBar
./Scripts/build-app.sh
open ./KefBar.app
```

On first launch, click **Scan the network** to detect your speakers automatically — or click
the ⚙️ icon to add one by IP. Got several KEF speakers? Add them all and pick the active one
from the menu-bar title.

> 👉 New to building Mac apps? Follow the friendly **[step-by-step guide](docs/GUIDE.md)**.

---

## 🇫🇷 Français

Petite app **barre de menus macOS** (Swift / SwiftUI) pour piloter des enceintes
**KEF Wi-Fi de 2ᵉ génération** — **LSX II, LS50 Wireless II, LS60, XIO** — via leur
API locale HTTP/JSON. Pas d'app KEF Connect, pas de cloud, pas de compte : tout reste
sur votre réseau local.

> Pour les enceintes de **1ʳᵉ génération** (LSX, LS50 Wireless), le protocole est
> différent (socket TCP binaire sur le port 50001). Ce projet ne les gère pas — voir
> [aiokef](https://github.com/basnijholt/aiokef) ou [kefctl](https://github.com/kraih/kefctl).

> 📚 **Documentation complète dans [`docs/`](docs/README.md)** : guide pas à pas pour
> débutants ([GUIDE](docs/GUIDE.md)), enquête sur les API KEF ([RESEARCH](docs/RESEARCH.md)),
> référence exhaustive du protocole ([PROTOCOL](docs/PROTOCOL.md)), traçabilité des preuves
> ([VERIFICATION](docs/VERIFICATION.md)), architecture interne ([ARCHITECTURE](docs/ARCHITECTURE.md)).

### Fonctionnalités

- 🔍 **Découverte automatique** : scan du réseau pour trouver les enceintes KEF (plus besoin de chercher l'IP)
- 🔀 **Plusieurs enceintes** : enregistre-les toutes et bascule de l'une à l'autre depuis la barre de menus
- ✏️ **IP manuelle** : tu peux aussi saisir l'adresse à la main
- Volume : slider pleine largeur (anti-rebond + retour haptique) encadré des boutons −/+ ; en dessous, une icône haut-parleur qui coupe le son au clic et le niveau **en % éditable** (saisie directe, ou flèches ↑/↓ pour ±1)
- Marche / arrêt (veille)
- Sélection de source : boutons-raccourcis Wi-Fi, Bluetooth, TV/HDMI, Optique, Coaxial, Aux
- Lecture / pause, piste suivante / précédente
- 🔁 **Mode de lecture** : bouton unique répéter tout / répéter la piste / aléatoire dans le transport
- 🔒 **Limite de volume** : le slider respecte le plafond réglé sur l'enceinte ; boutons −/+ par pas de 1
- 🎛️ **DSP / EQ** *(lecture seule)* : affiche mode bureau/mural, correction de phase, filtre passe-haut, sortie caisson, graves & aigus (`kef:eqProfile/v2`) — l'enceinte refuse l'écriture (voir ci-dessous)
- ⏲️ **Minuterie de veille** : extinction automatique après 15 / 30 / 45 / 60 / 90 min
- 🗒️ **File d'attente** *(best-effort)* : pistes à venir, dans les réglages avancés
- ⌨️ **Touches média du clavier** : les touches lecture/pause, ⏮/⏭ du Mac pilotent l'enceinte ; la lecture apparaît aussi dans le Centre de contrôle
- Pochette, puis titre, artiste et album qui **défilent** s'ils sont trop longs (pause au survol), et **barre de progression** (temps écoulé / total) en cours de lecture
- Mise à jour **temps réel** : abonnement au flux d'évènements de l'enceinte (long-poll), réveil quasi instantané, avec repli sur un sondage périodique
- 🚀 **Lancement au démarrage** : optionnel, via `SMAppService`
- 🏷️ **Barre de menus personnalisable** : choisis l'affichage (icône, texte libre, ou les deux) et le texte montré en haut de l'écran, dans les Paramètres
- Pas d'icône dans le Dock (app accessoire)

> ⚠️ Vérifié sur une LSX II : le **DSP est en lecture seule** — l'enceinte refuse l'écriture sur
> `kef:eqProfile/v2` (HTTP 401), KefBar se contente de l'afficher. Le bouton de **mode de
> lecture** est désactivé tant que rien ne joue (l'enceinte refuse d'écrire le mode sans session
> active). Les fonctions *best-effort* (file d'attente, notifications) se masquent si vides. Cf.
> [docs/PROTOCOL.md](docs/PROTOCOL.md) §A.11–A.12.

> 💡 Compatible DHCP : chaque enceinte est mémorisée par son **adresse MAC**. Si son IP change,
> un nouveau scan la retrouve et met l'adresse à jour automatiquement.

### Prérequis

- macOS 13 Ventura ou plus récent
- Xcode 15+ / toolchain Swift 5.9+
- L'enceinte et le Mac sur le **même réseau Wi-Fi**
- L'IP de l'enceinte est trouvée pour toi par le **scan réseau** intégré — ou saisis-la à la main
  (app KEF Connect → Réglages → enceinte → Infos → Adresse IP).

> 🟢 **Débutant ?** Le **[guide pas à pas](docs/GUIDE.md)** explique tout, sans jargon,
> de l'installation jusqu'au premier réglage de volume.

### Lancer

#### Option A — bundle .app (recommandé, le plus fiable)

```bash
cd KefBar
./Scripts/build-app.sh
open ./KefBar.app
```

Le script compile en release et fabrique un vrai `KefBar.app` avec l'`Info.plist`
(masquage du Dock + exception réseau local indispensable pour le HTTP en clair).

#### Option B — Xcode

```bash
open Package.swift   # ouvre le package dans Xcode, puis ⌘R
```

#### Option C — exécution rapide en dev

```bash
swift run KefBar
```

> ⚠️ En `swift run` (sans bundle), l'exception `NSAllowsLocalNetworking` n'est pas
> appliquée : si les requêtes HTTP sont bloquées, utilise l'option A.

Au premier lancement, clique sur **Scanner le réseau** pour détecter tes enceintes
automatiquement — ou sur l'icône ⚙️ pour en ajouter une par IP. Plusieurs enceintes KEF ?
Ajoute-les toutes et choisis l'active depuis le titre dans la barre de menus.

### Architecture

| Fichier | Rôle |
|---|---|
| `KefClient.swift` | Couche réseau : implémente le protocole HTTP/JSON KEF (getData/setData) |
| `Discovery.swift` | Scan du réseau local pour découvrir les enceintes KEF (sondes HTTP concurrentes) |
| `AppState.swift`  | État observable + actions + flux d'évènements temps réel + position + liste d'enceintes & scan |
| `NowPlayingCenter.swift` | Touches média du clavier (framework MediaPlayer) + intégration « En cours de lecture » macOS |
| `Models.swift`    | `Source`, `MenuBarStyle`, `Speaker`, `NowPlaying`, erreurs |
| `ContentView.swift` | UI du lecteur (slider, transport, sources, power, réglages avancés) |
| `SettingsView.swift` | Écran dédié des réglages (enceintes, apparence de la barre de menus, démarrage) |
| `KefBarApp.swift` | Point d'entrée `MenuBarExtra` (label personnalisable) + politique d'activation accessoire |

### Le protocole (résumé)

API non officielle, rétro-ingénieriée depuis l'app KEF Connect
(réf. [pykefcontrol](https://github.com/N0ciple/pykefcontrol)). HTTP simple, port 80,
sans TLS ni auth.

- Lecture : `GET http://<ip>/api/getData?path=<path>&roles=value` → `[{...}]`
- Écriture : `POST http://<ip>/api/setData` body `{"path":...,"roles":"value","value":{...}}`

| Action | path | valeur |
|---|---|---|
| Volume (0–100) | `player:volume` | `{"type":"i32_","i32_":40}` |
| Power / source | `settings:/kef/play/physicalSource` | `{"type":"kefPhysicalSource","kefPhysicalSource":"wifi"}` (`standby` = veille) |
| Lire l'état power | `settings:/kef/host/speakerStatus` | → `standby` / `powerOn` |
| Transport | `player:player/control` (`roles=activate`) | `{"control":"pause"}` / `"next"` / `"previous"` |
| Now-playing | `player:player/data` | titre, métadonnées, `icon` (pochette), `state`, durée |
| Position | `player:player/data/playTime` | → `{"type":"i64_","i64_":...}` (ms) |
| Mode de lecture | `settings:/mediaPlayer/playMode` | type `playerPlayMode` (écriture refusée hors lecture) |
| Volume max / pas | `settings:/kef/host/maximumVolume` · `…/volumeStep` (`i16_`) | `i32_` / `i16_` (lecture) |
| DSP / EQ | `kef:eqProfile/v2` | objet `kefEqProfileV2` — **lecture seule** (écriture 401) |

> Temps réel : abonnement via `POST /api/event/modifyQueue` puis long-poll
> `GET /api/event/pollQueue?queueId=<uuid>&timeout=10` (cf. [docs/PROTOCOL.md](docs/PROTOCOL.md)
> §A.8). Modèle hybride : l'évènement réveille, les accesseurs typés font foi.

---

## ⚠️ Disclaimer / Avertissement

This project uses an **unofficial, undocumented local API** that is **not endorsed by KEF**.
A firmware update may change or break its behaviour at any time. For personal use on your
local network. KefBar is an independent project and is **not affiliated with KEF** or GP Acoustics.

API non documentée et non garantie par KEF : une mise à jour de firmware peut en modifier le
comportement. Usage personnel sur réseau local. Projet indépendant, **non affilié à KEF**.

## 📄 License

[MIT](LICENSE) © [Alexis Juillard](https://github.com/alexjuillardoff)

<sub>Keywords: KEF, KEF Connect, KEF Wireless, KEF LSX II, KEF LS50 Wireless II, KEF LS60,
KEF XIO, macOS menu bar app, Swift, SwiftUI, speaker control, volume control, KEF API,
local HTTP API, audio, hi-fi, Wi-Fi speakers.</sub>
