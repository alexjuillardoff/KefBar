# Traçabilité & preuves du protocole

Ce document indique **d'où vient chaque détail** du protocole et **avec quel niveau de
confiance**. Objectif : qu'on puisse re-vérifier chaque affirmation sans refaire l'enquête.

## Méthode

- **Gén. 1 (TCP/50001)** : le source de [`aiokef`](https://github.com/basnijholt/aiokef) a été
  **téléchargé et lu ligne par ligne** (`aiokef/aiokef.py`, branche `master`, 742 lignes).
  Les numéros de ligne ci-dessous renvoient à cette lecture. Recoupé avec `kefctl` (Perl) et
  `pykef` (Python).
- **Gén. 2 (HTTP/80)** : détails issus du source de
  [`pykefcontrol`](https://github.com/N0ciple/pykefcontrol) (`pykefcontrol/kef_connector.py`),
  **corroborés par plusieurs implémentations indépendantes** : `m-lange/kef_speaker`, le gist
  `aadje`, et le serveur `kef-mcp` (qui déclare ses payloads « vérifiés contre pykefcontrol »).
  Confiance élevée par recoupement, mais **pas** de lecture ligne-à-ligne avec n° de ligne ici.

## Échelle de confiance

| Niveau | Sens |
|---|---|
| 🟢 **Élevée** | Vérifié dans le code source (ligne citée) ou confirmé par ≥ 2 implémentations |
| 🟡 **Moyenne** | Une seule source, ou divergence entre implémentations |
| 🔴 **À valider** | Non testé sur matériel ; dépend du firmware |

---

## 1. Gén. 1 — `aiokef` (vérifié ligne par ligne)

| Affirmation | Preuve (extrait de `aiokef/aiokef.py`) | Ligne | Conf. |
|---|---|---|---|
| Port TCP = 50001 (défaut constructeur) | `port: int = 50001,` | 396 | 🟢 |
| 50001 documenté dans la docstring | `the default is 50001.` | ~371 | 🟢 |
| Socket TCP brut (pas HTTP) | `asyncio.open_connection(self.host, self.port, family=socket.AF_INET)` | 269-270 | 🟢 |
| Écriture en octets bruts | `self._writer.write(message)` / `await self._writer.drain()` | 303-304 | 🟢 |
| Lecture en octets bruts | `data = await self._reader.read(100)` | 313 | 🟢 |
| Constantes de framing | `_SET_START = ord("S")` / `_SET_MID = 129` / `_GET_END = 128` / `_GET_START = ord("G")` | 63-66 | 🟢 |
| GET = 3 octets `[G, sel, 128]` | `def _get(which): return bytes([_GET_START, which, _GET_END])` | 84 | 🟢 |
| SET = 4 octets `[S, sel, 129, val]` | `def _set(which): return lambda i: bytes([_SET_START, which, _SET_MID, i])` | 88 | 🟢 |
| Sélecteurs volume/source/transport | `_VOL = ord("%")` / `_SOURCE = ord("0")` / `_CONTROL = ord("1")` | 69-71 | 🟢 |
| Map des commandes | `"get_volume": _get(_VOL), "set_volume": _set(_VOL), "set_source": _set(_SOURCE), "get_source": _get(_SOURCE)` | — | 🟢 |
| Power off = source + 128 | `if state == "off": i += 128` | 436-437 | 🟢 |
| `turn_off` délègue à `set_source` | `await self.set_source(state.source, state="off")` | 709 | 🟢 |
| Mute = `vol % 128 + 128` | `await self._set_volume(int(volume) % 128 + 128)` | 671 | 🟢 |
| État muet si `vol >= 128` | `is_muted = volume >= 128` | 477 | 🟢 |
| Réponse SET OK | `FULL_RESPONSE_OK = bytes([82, 17, 255])` | 222 | 🟢 |
| Échelle volume 0–100 | `_VOLUME_SCALE = 100.0` | — | 🟢 |
| Codes d'entrée | `INPUT_SOURCES_20_MINUTES_LR = {'Bluetooth':9,'Bluetooth_paired':15,'Aux':10,'Opt':11,'Usb':12,'Wifi':2}` | — | 🟢 |

### Nuances relevées (gén. 1)

- 🟢 **Le « power » n'est pas une commande autonome** : on/off passe entièrement par l'octet de
  source (allumer = choisir une entrée, éteindre = même octet +128). La formulation « commande
  power » est donc inexacte pour ce protocole.
- 🟢 **Le « mute » non plus** : encodé dans l'octet de volume (`set_volume`).
- 🟡 **LSX gén. 1** : le README aiokef indique le protocole **testé sur LS50 Wireless**, la LSX
  étant listée comme supportée mais **non testée** par l'auteur.
- 🟡 **Octets finaux de `pykef`** : les trames pykef ont un octet additionnel (≠ checksum) que
  `aiokef`/`kefctl` n'ont pas et qui fonctionnent sans. Trame canonique = 3/4 octets.

---

## 2. Gén. 2 — `pykefcontrol` (corroboré par recoupement)

| Affirmation | Source | Conf. |
|---|---|---|
| HTTP en clair, port 80, base `http://<ip>/api/` | `getDataUrl = "http://"+host+"/api/getData"`, `setDataUrl = …/setData` (pykefcontrol) | 🟢 |
| `setData` en **POST** (firmwares récents) | pykefcontrol ; vérif. ponctuelle « requests.post setData » | 🟢 |
| Réponse = tableau JSON `[{...}]`, lu `[0]["type"]` | pykefcontrol ; m-lange | 🟢 |
| `speakerStatus` → `standby`/`powerOn` | `settings:/kef/host/speakerStatus`, `.status` lit `[0]["kefSpeakerStatus"]` | 🟢 |
| Power+source sur `settings:/kef/play/physicalSource` | pykefcontrol ; gist aadje | 🟢 |
| Valeurs source `standby/wifi/bluetooth/tv/optic/coaxial/analog` | pykefcontrol ; aadje | 🟢 |
| Volume `player:volume`, `i32_`, 0–100 | pykefcontrol ; m-lange | 🟢 |
| Transport `player:player/control`, `roles=activate`, `{"control":…}` | pykefcontrol ; m-lange | 🟢 |
| Now-playing `player:player/data`, parsing `trackRoles.*` | pykefcontrol ; m-lange | 🟢 |
| Événements `modifyQueue` / `pollQueue` + UUID | pykefcontrol (`json_output[1:-1]`) | 🟢 |
| Firmwares **très anciens** = GET-only | kef-mcp (« verified against LSX II / LS50 W II / LS60 ») | 🟡 |
| `i32_` parfois renvoyé en **chaîne** | gist aadje (`"i32_":"40"`) | 🟡 |
| Mute dédié `settings:/mediaPlayer/mute` (`bool_`) | gist aadje ; m-lange (pykefcontrol préfère le soft-mute) | 🟡 |
| Soft-mute (volume→0 + restauration) | pykefcontrol | 🟢 |
| Infos appareil (`primaryMacAddress`, `deviceName`, `releasetext`, `network:info`) | pykefcontrol ; hass-kef-connector | 🟢 |

### Limite de la vérification gén. 2

L'agent de vérification dédié a confirmé le **POST setData** mais n'a pas re-cité ligne par
ligne chaque chemin (résultat partiel). La confiance « élevée » repose donc sur la
**convergence de 4 implémentations indépendantes**, pas sur une relecture exhaustive du source
avec n° de ligne. Le seul point qu'il a explicitement signalé à surveiller : la **stratégie de
mute** (soft-mute volume 0 vs chemin dédié).

---

## 3. Ce qui N'A PAS été testé (🔴 à valider sur matériel)

| Élément | Risque | Où ajuster |
|---|---|---|
| **Parsing now-playing** | Structure variable selon le service (TIDAL/AirPlay/radio) ; des clés peuvent différer | [`KefClient.nowPlaying()`](../Sources/KefBar/KefClient.swift) |
| **Allumage** (écrire `wifi` vs état `powerOn`) | Comportement selon modèle/firmware | [`KefClient.powerOn(_:)`](../Sources/KefBar/KefClient.swift) |
| **GET vs POST** sur ton firmware précis | Très vieux firmware = GET-only | `KefClient.setData(...)` |
| **HTTP/ATS** en `swift run` | L'exception réseau local ne s'applique qu'en bundle `.app` | [`Resources/Info.plist`](../Resources/Info.plist) |
| **Mute** dédié vs soft-mute | KefBar fait du soft-mute ; OK en principe | `AppState.toggleMute()` |

Toute l'app **compile et se package** (`swift build` + bundle `.app` signé) mais **rien n'a
été exercé contre une enceinte physique**.

---

## 4. Dépôts de référence

| Génération | Dépôt | Fichier clé |
|---|---|---|
| Gén. 2 (HTTP) | `N0ciple/pykefcontrol` | `pykefcontrol/kef_connector.py` |
| Gén. 2 (HTTP) | `m-lange/kef_speaker` | `kef_connector.py` |
| Gén. 2 (HTTP) | gist `aadje` | `15945bc5a55035bc6a4f22270241b3f8` |
| Gén. 1 (TCP) | `basnijholt/aiokef` | `aiokef/aiokef.py` |
| Gén. 1 (TCP) | `kraih/kefctl` | `kefctl` (Perl) |
| Gén. 1 (TCP) | `Gronis/pykef` | `pykef/__init__.py` |
