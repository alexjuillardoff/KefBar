# Ce que j'ai appris sur les enceintes KEF

Synthèse détaillée de l'enquête : possibilité de piloter des enceintes KEF Wi-Fi, et comment.
Recherche multi-sources, avec vérification des détails de protocole dans le code des
bibliothèques existantes (voir [VERIFICATION.md](VERIFICATION.md)).

---

## 1. KEF ne fournit aucune API officielle

- Pas de `developer.kef.com`, pas d'organisation GitHub KEF, pas de spécification publique,
  pas de SDK. Les pages support KEF ne proposent que le téléchargement des apps et des FAQ.
- Toutes les bibliothèques de contrôle sont **rétro-ingénieriées** en capturant le trafic
  entre l'app mobile officielle (KEF Connect / KEF Control) et les enceintes.
- L'auteur de `kefctl` : _« À ma connaissance il n'existe aucune documentation du protocole de
  contrôle KEF. Chaque fonction a dû être rétro-ingénieriée en capturant le trafic réseau de
  l'app KEF Control. »_

### Ce que KEF supporte *officiellement* (mais ce n'est pas une API pour app maison)

**a) Protocoles standards intégrés au firmware** (modèles gén. 2) :

| Protocole | Usage | Multiroom |
|---|---|---|
| AirPlay 2 | streaming Apple | ✅ |
| Google Chromecast / Cast | streaming Android/Chrome | ✅ |
| Roon Ready | écosystème Roon | ✅ |
| Spotify Connect | via l'app Spotify | — |
| TIDAL Connect | via l'app TIDAL | — |
| Bluetooth | appairage direct | — |

Audio haute résolution jusqu'à **24 bit / 384 kHz**, **MQA**, **DSD**. Streaming intégré dans
l'app KEF Connect : TIDAL, Amazon Music, Qobuz, Deezer, radio internet, podcasts.

**b) Drivers domotique professionnels** — KEF délègue à son partenaire **Intrinsic Dev** ;
les PDF officiels KEF pointent vers `intrinsicdev.com`.

| Système | Plateforme |
|---|---|
| Control4 | driver « W2 Media » (ajoute la navigation de contenu) |
| Crestron Home, ELAN, RTI | drivers « W2 Control » (entrée/volume/power/zone) |
| Savant | driver dédié |

Précisions : les drivers **W2 Control** (ELAN, RTI) offrent commutation d'entrée, volume et
power pour LS50 W II / LSX II / LS60 ; ils **ne pilotent pas** le streaming (géré par l'app).
Pour la **gén. 1 (LSX)**, le contrôle IP expose Input Select, Volume +/−, Mute toggle et
Wake-On-LAN. **Prérequis firmware ≥ V1.8** sur LS50 Wireless II.

**Conclusion** : pour une app personnelle, la seule voie réaliste est l'**API locale
rétro-ingénieriée**. Sans danger (réseau local, ton matériel) mais **non garanti** : un
firmware peut casser un endpoint.

---

## 2. Deux générations, deux protocoles incompatibles

Point structurant. **Aucune bibliothèque ne couvre les deux** — d'où la coupure de l'écosystème.

| | **Gén. 1** | **Gén. 2 (« W2 »)** |
|---|---|---|
| Modèles | LSX, LS50 Wireless | LSX II, LSX II LT, LS50 Wireless II, LS60, XIO |
| App mobile | KEF **Control** | KEF **Connect** |
| Transport | Socket **TCP brut binaire** | **HTTP/JSON** type REST |
| Port | **50001** | **80** (HTTP clair, sans TLS ni auth) |
| Biblio. de référence | `aiokef`, `kefctl`, `pykef` | `pykefcontrol` |
| Particularités | 1 connexion socket à la fois ; allumage souvent impossible (interface réseau coupée en veille) ; ~20 s de boot | API simple, idéale pour une app |

> **KefBar cible la gén. 2.** Détail complet des deux protocoles dans [PROTOCOL.md](PROTOCOL.md).

### Identifier sa génération

- App **KEF Connect** (pas « KEF Control ») → gén. 2.
- Entrée **HDMI** (LS50 W II / LS60) ou **coaxiale** → gén. 2.
- « II » / « 2 » dans le nom → gén. 2.

---

## 3. L'écosystème open-source (la « doc » de facto)

État ≈ mi-2026. Étoiles/versions indicatives.

### Gén. 2 — HTTP/JSON

| Projet | Langage / Licence | Modèles | Opérations | Version / activité |
|---|---|---|---|---|
| [N0ciple/pykefcontrol](https://github.com/N0ciple/pykefcontrol) | Python / MIT | LS50W II, LSX II, LS60 | power, source (wifi/bt/tv/optical/coaxial/analog), play/pause, next/prev, volume, mute, now-playing, infos, polling. Classes `KefConnector` (sync) + `KefAsyncConnector` (async) | **v0.9.3 (2026-05)**, ~49★, actif |
| [N0ciple/hass-kef-connector](https://github.com/N0ciple/hass-kef-connector) | Python / Apache-2.0 | LSX II LT, LSX II, LS50W II, LS60, XIO | media_player HA (volume, source, lecture), HACS | **v0.6.5 (2026-05)**, ~30★, actif |
| [amebalabs/Kefir](https://github.com/amebalabs/Kefir) | **Swift** / MIT | LSX II, LS50W II, LS60 | **app barre de menus macOS** : volume, power, source, now-playing + pochette, mini-player, raccourcis globaux, multi-enceintes | **v1.1.0 (2026-05)**, ~11★ |
| [amebalabs/KefirCLI](https://github.com/amebalabs/KefirCLI) | Swift / MIT | LSX II, LS50W II, LS60 | CLI + TUI temps réel, profils, Homebrew (Swift 6.1+/macOS 10.15+) | **v1.1.1 (2025-06)**, ~2★ |
| [m-lange/kef_speaker](https://github.com/m-lange/kef_speaker) | Python | LSX II | intégration HA (media_player + config flow) ; bon parsing now-playing | petit, ~0★ |
| [JesalR/kef_control](https://github.com/JesalR/kef_control) | Python / MIT | LSX II (LS50W II/LS60 non testés) | media_player minimal via pykefcontrol | petit |
| [gist aadje](https://gist.github.com/aadje/15945bc5a55035bc6a4f22270241b3f8) | script | gén. 2 | documente bien les payloads (qualifie l'API de « mal conçue ») | — |
| [jhnvz/homebridge-kef](https://github.com/jhnvz/homebridge-kef) | TypeScript / Apache-2.0 | KEF (HomeKit) | volume, source, état lecture, transport — **« UNDER DEVELOPMENT »** | embryonnaire |

### Gén. 1 — TCP binaire

| Projet | Langage / Licence | Modèles | Notes | Activité |
|---|---|---|---|---|
| [basnijholt/aiokef](https://github.com/basnijholt/aiokef) | Python / MIT | LS50W (testé), LSX (non testé) | **référence async** ; sous-tend l'intégration HA `kef` ; **DSP complet** (desk/wall, treble, HP, sub) | v0.2.17 (2020-10), ~41★, inactif |
| [kraih/kefctl](https://github.com/kraih/kefctl) | Perl / Artistic-2.0 | LSX, LS50W (fw 4.1) | CLI sans dépendances ; **meilleure doc du bitfield** ; companion `kefdsp` ; découverte UPnP | ~61★, 60 commits, **non maintenu** |
| [Gronis/pykef](https://github.com/Gronis/pykef) | Python / MIT | LS50W, LSX | l'original ; **archivé** (2020-03), renvoie vers aiokef | ~17★ |
| [HA `kef`](https://www.home-assistant.io/integrations/kef/) | Python | LS50W, LSX | intégration officielle (sur aiokef) ; **services DSP** (mode, desk/wall dB, treble, HP, sub) ; marquée **Legacy** | core |
| [patrickdmiller/kef-wireless-js](https://github.com/patrickdmiller/kef-wireless-js) | Node / npm | LS50W (v1) | `setVolume`, `muteToggle`, `cycleSource`, events | v1.0.4 (2020-07) |
| [patrickdmiller/streamdeck-kef](https://github.com/patrickdmiller/streamdeck-kef) | JS | LS50 v1 | plugin Elgato Stream Deck (volume, power) | 2022-12 |
| [oko/kefctl](https://github.com/oko/kefctl) | Rust / MIT | LSX | CLI + crate `libkef` + `kefdisc` (SSDP) | embryonnaire |
| [jaksonlin/go-kefctl](https://github.com/jaksonlin/go-kefctl) | Go / MIT | LSX | port Go de kefctl | embryonnaire |
| [proflylab/kef-control](https://github.com/proflylab/kef-control) | JS/Vue / MIT | LSX | GUI **system-tray** Win/Linux/macOS (Electron) | v1.0.2 (2021-12), ~6★ |
| [TuutTuutJonas/kef-desktop-controller](https://github.com/TuutTuutJonas/kef-desktop-controller) | TS/Vue / Electron | LSX (LS50 « devrait marcher ») | GUI desktop, mode menu-bar prévu | v1.0.0 (2020-10), ~6★ |

### À retenir

- **Pas de binding openHAB dédié** : on appelle `kefctl` via le binding Exec.
- Les projets les plus **actifs** (mi-2026) : `pykefcontrol`/`hass-kef-connector` et
  `Kefir`/`KefirCLI`. Les piliers gén. 1 (`aiokef`, `pykef`, `kefctl`) sont stables mais peu
  maintenus.
- **`amebalabs/Kefir`** fait déjà exactement ce que vise KefBar (app menu-bar Swift, gén. 2) :
  à étudier/forker en priorité.

---

## 4. Construire une app barre de menus macOS

- **Natif Swift (choix de KefBar)** :
  - `MenuBarExtra` (SwiftUI, **macOS 13 Ventura+**) — moderne, peu de code. Style **`.window`**
    requis pour héberger un **slider** (le style `.menu` se limite aux items).
  - `NSStatusItem` / `NSStatusBar` (AppKit, depuis macOS 11/12) pour plus de compat.
  - `LSUIElement = YES` ou `NSApp.setActivationPolicy(.accessory)` → **pas d'icône Dock**.
  - Réseau : `URLSession` (HTTP, gén. 2) ou framework `Network`/`NWConnection` (TCP, gén. 1).
  - **ATS** : le HTTP en clair vers le LAN exige `NSAllowsLocalNetworking` dans l'Info.plist.
- **Découverte LAN** : pas de service Bonjour propre à KEF. Les enceintes s'annoncent en
  AirPlay (`_airplay._tcp`), Chromecast (`_googlecast._tcp`, port **8009**), UPnP/SSDP. Le plus
  simple/robuste : **IP fixe** saisie une fois (réservation DHCP).
- **Alternatives plus légères** :
  - [SwiftBar](https://github.com/swiftbar/SwiftBar) — un script bash + `curl` devient une icône
    de menu (prototype en minutes, macOS 10.15+).
  - Hammerspoon (Lua), Tauri (~2–10 Mo) ou Electron (~150 Mo).

---

## 5. Sources principales

- Protocole gén. 2 : <https://github.com/N0ciple/pykefcontrol> (`pykefcontrol/kef_connector.py`)
- Protocole gén. 1 : <https://github.com/basnijholt/aiokef> (`aiokef/aiokef.py`),
  <https://github.com/kraih/kefctl>
- Intégration Home Assistant : <https://www.home-assistant.io/integrations/kef/>
- Intégration tierce officielle : <https://assets.kef.com/pdf_doc/LS50WII/Drivers_for_Home_Automation_Control_System.pdf>,
  <https://www.intrinsicdev.com/>
- App Swift de référence : <https://github.com/amebalabs/Kefir>
- macOS : <https://developer.apple.com/documentation/SwiftUI/MenuBarExtra>
- Détail des preuves : [VERIFICATION.md](VERIFICATION.md)
