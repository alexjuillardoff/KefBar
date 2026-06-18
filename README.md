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
- 🔈 **Volume + mute** — smooth slider with debounce
- ⏻ **Power on / standby**
- 🎛️ **Source selector** — Wi-Fi, Bluetooth, TV/HDMI, Optical, Coaxial, Aux
- ⏯️ **Transport** — play / pause, next / previous track
- 🎵 **Now playing** — title, artist and album artwork
- 🔄 **Auto-refresh** every 3 seconds
- 🪶 **No Dock icon** — lives quietly in the menu bar (accessory app)

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
- Volume + mute (slider, anti-rebond)
- Marche / arrêt (veille)
- Sélection de source : Wi-Fi, Bluetooth, TV/HDMI, Optique, Coaxial, Aux
- Lecture / pause, piste suivante / précédente
- Titre, artiste et pochette en cours de lecture
- Rafraîchissement périodique (3 s)
- Pas d'icône dans le Dock (app accessoire)

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
| `AppState.swift`  | État observable + actions + polling + liste d'enceintes & scan |
| `Models.swift`    | `Source`, `Speaker`, `NowPlaying`, erreurs |
| `ContentView.swift` | UI du menu (gestion des enceintes, slider, transport, sources, power) |
| `KefBarApp.swift` | Point d'entrée `MenuBarExtra` + politique d'activation accessoire |

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
| Now-playing | `player:player/data` | titre, métadonnées, `icon` (pochette), `state` |

> Bonus non implémenté ici : push temps réel via `POST /api/event/modifyQueue`
> puis long-poll `GET /api/event/pollQueue?queueId=<uuid>&timeout=10`.

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
