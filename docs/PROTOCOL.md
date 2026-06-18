# Référence du protocole KEF (local) — exhaustive

Protocole **non officiel**, rétro-ingénierié depuis les apps mobiles KEF. Les détails de la
**gén. 1** sont vérifiés ligne par ligne dans `aiokef/aiokef.py` ; ceux de la **gén. 2**
proviennent du source de `pykefcontrol` et sont corroborés par plusieurs implémentations
indépendantes (`m-lange/kef_speaker`, gist `aadje`, `kef-mcp`). Le détail des preuves est
dans [VERIFICATION.md](VERIFICATION.md).

> ⚠️ Non documenté et non garanti par KEF. Un firmware peut en modifier le comportement.
> Les niveaux de confiance par affirmation sont indiqués dans [VERIFICATION.md](VERIFICATION.md).

**Sommaire**
- [Partie A — Gén. 2 (HTTP/JSON, port 80)](#partie-a--génération-2--w2--http--json)
- [Partie B — Gén. 1 (TCP binaire, port 50001)](#partie-b--génération-1--tcp-binaire-port-50001)

---

# Partie A — Génération 2 (« W2 ») : HTTP / JSON

**Modèles** : LSX II, LSX II LT, LS50 Wireless II, LS60, XIO.
Identifiants/alias internes (pykefcontrol) : `LS50WII` (alias `LS50W2`), `LSXII` (`LSX2`),
`LSXIILT` (`LSX2LT`), `LS60`, `XIO`.
**Implémenté par KefBar** dans [`KefClient.swift`](../Sources/KefBar/KefClient.swift).

## A.1 Transport HTTP — détails exacts

| Propriété | Valeur |
|---|---|
| Schéma | `http://` (clair, **pas de TLS**) |
| Hôte | IP LAN de l'enceinte |
| Port | **80** (implicite) |
| Authentification | **aucune** |
| Base d'URL | `http://<ip>/api/` |
| Lecture | `GET /api/getData` |
| Écriture | `POST /api/setData` (firmwares récents) |
| Abonnement événements | `POST /api/event/modifyQueue` |
| Long-poll événements | `GET /api/event/pollQueue` |

- `pykefcontrol` construit littéralement `getDataUrl = "http://" + host + "/api/getData"` et
  `setDataUrl = "http://" + host + "/api/setData"`.
- **GET vs POST selon le firmware** : sur les modèles récents (LS50WII, LSXII, LSXIILT, LS60),
  `setData` est un **POST** avec body JSON. Sur firmwares **très anciens**, l'écriture se
  faisait en **GET** avec la valeur JSON encodée (stringifiée) dans la query string.
  `kef-mcp` précise : _« formats vérifiés contre les firmwares LSX II / LS50 W II / LS60, les
  très vieux firmwares étant GET-only »_. **KefBar utilise POST.**
- Particularité observée : `m-lange/kef_speaker` envoie même le `getData` avec un **body JSON**
  `{"path": path, "roles": "value"}` (inhabituel pour un GET). KefBar préfère les **query params**.

### Forme exacte des requêtes

**Lecture (GET, query params) :**
```
GET /api/getData?path=player:volume&roles=value HTTP/1.1
Host: <ip>
```

**Lecture (forme alternative GET + body, vue chez m-lange) :**
```
GET /api/getData
Content-Type: application/json

{"path": "player:volume", "roles": "value"}
```

**Écriture (POST) :**
```
POST /api/setData HTTP/1.1
Host: <ip>
Content-Type: application/json

{"path":"player:volume","roles":"value","value":{"type":"i32_","i32_":40}}
```

**Écriture (forme GET héritée, firmwares très anciens) :**
```
GET /api/setData?path=settings:/kef/play/physicalSource&roles=value&value={"type":"kefPhysicalSource","kefPhysicalSource":"coaxial"}
```

## A.2 Enveloppe de réponse

Toute lecture renvoie un **tableau JSON à un seul élément**, dont l'objet porte le couple
`type` + valeur typée. `pykefcontrol` lit `json_output[0]["<type>"]`.

```json
[ { "type": "i32_", "i32_": 40 } ]
```

### Types de valeur (wrappers)

| `type` | Sens | Lu / écrit comme | Exemple complet |
|---|---|---|---|
| `i32_` | entier 32 bits | nombre (parfois **chaîne** `"40"` selon firmware) | `{"type":"i32_","i32_":40}` |
| `i64_` | entier 64 bits | nombre | position de lecture en ms |
| `bool_` | booléen | `true`/`false` | `{"type":"bool_","bool_":true}` |
| `string_` | chaîne | texte | `{"type":"string_","string_":"Salon"}` |
| `kefPhysicalSource` | source + power | chaîne d'énumération | `{"type":"kefPhysicalSource","kefPhysicalSource":"wifi"}` |
| `kefSpeakerStatus` | état d'alimentation | `"standby"` / `"powerOn"` | `{"type":"kefSpeakerStatus","kefSpeakerStatus":"powerOn"}` |

> ⚠️ **Robustesse** : le gist `aadje` montre `i32_` parfois renvoyé/attendu en **chaîne**
> (`"i32_":"40"`). `KefClient` lit donc l'entier de façon tolérante
> (`NSNumber` **ou** `String`). Voir [`KefClient.int(_:)`](../Sources/KefBar/KefClient.swift).

## A.3 Table complète des chemins (`path`)

| Fonction | `path` | `roles` | Valeur écrite / réponse lue |
|---|---|---|---|
| **Volume** (0–100) | `player:volume` | `value` | écrit `i32_` ; lit `[{"type":"i32_","i32_":40}]` |
| **Source + allumage** | `settings:/kef/play/physicalSource` | `value` | `kefPhysicalSource` (voir A.4) |
| **État alimentation (lecture)** | `settings:/kef/host/speakerStatus` | `value` | `[{"type":"kefSpeakerStatus","kefSpeakerStatus":"powerOn"}]` |
| **Mute** | `settings:/mediaPlayer/mute` | `value` | `bool_` |
| **Transport** | `player:player/control` | **`activate`** | `{"control":"pause"\|"next"\|"previous"}` |
| **Lecture en cours** | `player:player/data` | `value` | objet imbriqué (voir A.5) |
| **Position de lecture** | `player:player/data/playTime` | `value` | `i64_` en ms (voir A.5) |
| Mode lecture (repeat/shuffle) | `settings:/mediaPlayer/playMode` | `value` | — |
| Volume max | `settings:/kef/host/maximumVolume` | `value` | `i32_` (lecture) |
| Limite de volume | `settings:/kef/host/volumeLimit` | `value` | `i32_` (lecture) |
| Pas de volume | `settings:/kef/host/volumeStep` | `value` | `i32_` (lecture) |
| Nom de l'appareil | `settings:/deviceName` | `value` | `string_` |
| Adresse MAC | `settings:/system/primaryMacAddress` | `value` | `string_` |
| Version firmware | `settings:/releasetext` | `value` | `string_` |
| Profil EQ | `kef:eqProfile` | `value` | objet |
| Infos réseau | `network:info` | `value` | objet imbriqué (wifi/IP) |

> ⚠️ Le **transport** utilise `roles=activate`, **pas** `value`. C'est la seule opération
> dans ce cas.

## A.4 Alimentation et source : un seul chemin

`settings:/kef/play/physicalSource` choisit la source **et** gère l'allumage/extinction.

| Valeur `kefPhysicalSource` | Entrée |
|---|---|
| `standby` | **veille (= éteint)** |
| `wifi` | Wi-Fi / réseau |
| `bluetooth` | Bluetooth |
| `tv` | TV / HDMI ARC |
| `optic` | optique (TOSLINK) |
| `coaxial` | coaxial numérique |
| `analog` | entrée analogique / Aux |

Sémantique précise (d'après `pykefcontrol`) :

- **Éteindre** : `shutdown()` écrit `physicalSource = "standby"`.
- **Allumer** : deux variantes équivalentes —
  1. `power_on()` écrit l'état `"powerOn"` ;
  2. écrire directement une source réelle (p.ex. `wifi`) allume **et** sélectionne l'entrée.
  **KefBar** utilise la variante 2 (écrit la dernière source connue, `wifi` par défaut).
- **Lire** l'alimentation : via `settings:/kef/host/speakerStatus` (≠ du chemin d'écriture).
  La propriété `.status` de pykefcontrol lit `json_output[0]["kefSpeakerStatus"]`.

## A.5 Lecture en cours (`player:player/data`) — structure complète

Objet imbriqué (le plus variable : dépend du service — TIDAL, AirPlay, radio…). Champs et
parsing exact d'après `pykefcontrol` / `m-lange` :

```jsonc
{
  "state": "playing",                 // "playing" | "paused" | "stopped"
  "trackRoles": {
    "title": "Titre du morceau",      // → title
    "icon": "http://.../cover.jpg",   // → cover_url (URL de pochette)
    "mediaData": {
      "metaData": {
        "artist": "Artiste",          // → artist
        "album": "Album",             // → album
        "albumArtist": "…",           // → album_artist
        "serviceID": "…"              // identifiant du service source
      },
      "resources": [
        { "mimeType": "audio/…" }     // type média (parsé par m-lange)
      ]
    }
  },
  "mediaRoles": { /* … */ }
}
```

Correspondance de parsing (`pykefcontrol`) :

| Donnée | Chemin dans l'objet |
|---|---|
| Titre | `trackRoles.title` |
| Artiste | `trackRoles.mediaData.metaData.artist` |
| Album | `trackRoles.mediaData.metaData.album` |
| Artiste de l'album | `trackRoles.mediaData.metaData.albumArtist` |
| Pochette (URL) | `trackRoles.icon` |
| En lecture ? | `state == "playing"` |

Position / durée : `player:player/data/playTime` renvoie un `i64_` en **millisecondes** ;
un champ de durée accompagne la métadonnée. **KefBar** lit la position via
[`KefClient.playPosition()`](../Sources/KefBar/KefClient.swift) et extrait la durée dans
`nowPlaying()` de façon défensive : `status.duration` → `metaData.duration` →
`mediaData.activeResource.duration` → `mediaData.resources[0].duration` (best-effort,
l'emplacement dépend du service).

> **Vérifié sur matériel (LSX II, source Wi-Fi / TIDAL Connect)** : la durée fiable est
> `status.duration` (ms, p.ex. `210346`) ; `metaData` **ne contient pas** de `duration` pour
> TIDAL — elle est dans `status`, `mediaData.activeResource` et chaque `mediaData.resources[]`.
> À noter : la charge utile contient des **échappements non standard** (`\?`, `\=` dans
> `prePlayPath`/`context`) ; `JSONSerialization` (Foundation) les tolère, mais des parseurs
> stricts (p.ex. `jq`) les rejettent.

> **KefBar** parse `title`, `artist`, `album`, `icon`, `state` de façon défensive
> (cf. [`KefClient.nowPlaying()`](../Sources/KefBar/KefClient.swift)). C'est le point le plus
> susceptible de varier selon le firmware/service — voir
> [ARCHITECTURE.md §6](ARCHITECTURE.md#6-limites-et-points-à-valider).

## A.6 Mute : deux méthodes

1. **Chemin dédié** :
   `POST /api/setData` `{"path":"settings:/mediaPlayer/mute","roles":"value","value":{"type":"bool_","bool_":true}}`.
2. **« Soft mute »** (employé par `pykefcontrol` **et par KefBar**) : mémoriser `previous_volume`,
   écrire `player:volume = 0`, puis restaurer. Indépendant du firmware. `pykefcontrol`
   n'utilise **pas** le chemin `mute` dédié.

## A.7 Correspondance méthode ↔ endpoint (modèle `pykefcontrol`)

| Méthode (pykefcontrol) | Opération HTTP |
|---|---|
| `.status` (get) | `getData settings:/kef/host/speakerStatus` |
| `power_on()` | `setData physicalSource` → `"powerOn"` |
| `shutdown()` | `setData physicalSource` → `"standby"` |
| `.source` (get/set) | `getData`/`setData settings:/kef/play/physicalSource` |
| `.volume` (get/set) | `getData`/`setData player:volume` (`i32_`) |
| `mute()` / `unmute()` | `setData player:volume` (0 / `previous_volume`) |
| `toggle_play_pause()` | `setData player:player/control activate {"control":"pause"}` |
| `next_track()` | `… {"control":"next"}` |
| `previous_track()` | `… {"control":"previous"}` |
| `.song_information` | `getData player:player/data` (parse trackRoles) |
| `.mac_address` | `getData settings:/system/primaryMacAddress` |
| `poll_speaker(timeout, poll_song_status)` | cycle `modifyQueue` + `pollQueue` (A.8) |

> `m-lange` montre une forme étendue de commande de transport :
> `{"control":"<cmd>", "<type>":"<value>"}` pour les commandes paramétrées.

## A.8 Push temps réel (long-poll)

Alternative au polling : s'abonner aux changements d'état. **Implémenté par KefBar**
(`KefClient.subscribeToEvents()` / `pollEvents(queueId:timeout:)`, orchestré par
`AppState.runEventLoop()` — cf. [ARCHITECTURE.md](ARCHITECTURE.md)). KefBar emploie un modèle
**hybride** : l'évènement sert de signal de réveil, puis les valeurs faisant foi sont relues via
les accesseurs typés (robuste vis-à-vis de la forme exacte des éléments renvoyés). Repli sur un
rafraîchissement périodique si les évènements échouent (firmware ancien, file expirée).

1. **S'abonner** — `POST http://<ip>/api/event/modifyQueue`, body exact observé :
   ```json
   {
     "subscribe": [
       { "path": "player:volume", "type": "itemWithValue" },
       { "path": "player:player/data", "type": "itemWithValue" },
       { "path": "settings:/mediaPlayer/playMode", "type": "itemWithValue" },
       { "path": "settings:/kef/host/maximumVolume", "type": "itemWithValue" },
       { "path": "settings:/deviceName", "type": "itemWithValue" },
       { "path": "network:info", "type": "itemWithValue" },
       { "path": "kef:eqProfile", "type": "itemWithValue" },
       { "path": "playlists:pq/getitems", "type": "rows" },
       { "path": "notifications:/display/queue", "type": "rows" }
     ],
     "unsubscribe": []
   }
   ```
   → la réponse est un **UUID de file entre guillemets** ; `pykefcontrol` retire les guillemets
   via `json_output[1:-1]`.
2. **Poller** — `GET http://<ip>/api/event/pollQueue?queueId=<uuid>&timeout=10`
   bloque jusqu'à `timeout` secondes et renvoie les éléments modifiés. `pykefcontrol` expose
   ceci comme `poll_speaker(timeout=10, poll_song_status=False)`.

## A.9 Comportements & cas limites

- **Type `subscribe`** : `itemWithValue` pour une valeur scalaire ; `rows` pour une liste
  (playlists, file de notifications).
- **`i32_` en chaîne** : tolérer les deux formes en lecture.
- **Pas d'auth/TLS** : quiconque sur le LAN peut piloter l'enceinte ; à garder en tête.
- **Veille** : lire volume/source pendant la veille peut renvoyer `standby` — KefBar ignore
  alors la mise à jour de la source pour ne pas écraser la dernière source réelle connue.

## A.10 Exemples concrets

### curl

```bash
IP=192.168.1.42

# Lire le volume
curl "http://$IP/api/getData?path=player:volume&roles=value"
# → [{"type":"i32_","i32_":40}]

# Lire l'état d'alimentation
curl "http://$IP/api/getData?path=settings:/kef/host/speakerStatus&roles=value"
# → [{"type":"kefSpeakerStatus","kefSpeakerStatus":"powerOn"}]

# Régler le volume à 25
curl -X POST "http://$IP/api/setData" -H 'Content-Type: application/json' \
  -d '{"path":"player:volume","roles":"value","value":{"type":"i32_","i32_":25}}'

# Éteindre (veille)
curl -X POST "http://$IP/api/setData" -H 'Content-Type: application/json' \
  -d '{"path":"settings:/kef/play/physicalSource","roles":"value","value":{"type":"kefPhysicalSource","kefPhysicalSource":"standby"}}'

# Allumer + sélectionner l'optique
curl -X POST "http://$IP/api/setData" -H 'Content-Type: application/json' \
  -d '{"path":"settings:/kef/play/physicalSource","roles":"value","value":{"type":"kefPhysicalSource","kefPhysicalSource":"optic"}}'

# Play / pause
curl -X POST "http://$IP/api/setData" -H 'Content-Type: application/json' \
  -d '{"path":"player:player/control","roles":"activate","value":{"control":"pause"}}'

# Now-playing
curl "http://$IP/api/getData?path=player:player/data&roles=value"
```

### Swift (extrait de `KefClient.swift`)

```swift
func setVolume(_ value: Int) async throws {
    let clamped = max(0, min(100, value))
    try await setData(path: "player:volume",
                      value: ["type": "i32_", "i32_": clamped])
}

func setSource(_ source: Source) async throws {
    try await setData(path: "settings:/kef/play/physicalSource",
                      value: ["type": "kefPhysicalSource", "kefPhysicalSource": source.apiValue])
}
```

---

# Partie B — Génération 1 : TCP binaire (port 50001)

**Modèles** : LSX, LS50 Wireless (1ʳᵉ gén). **Non géré par KefBar** — documenté pour
référence. **Vérifié ligne par ligne** dans `aiokef/aiokef.py` (voir
[VERIFICATION.md](VERIFICATION.md)), recoupé avec `kefctl` (Perl) et `pykef` (Python).

## B.1 Transport — détails exacts

| Propriété | Valeur | Preuve |
|---|---|---|
| Transport | **TCP brut** (socket flux, pas de HTTP/JSON) | `asyncio.open_connection(host, port, family=socket.AF_INET)` |
| Port | **50001** | `port: int = 50001` (constructeur, l. 396) |
| Connexions simultanées | **une seule** | l'enceinte n'accepte qu'un socket |
| Écriture | octets bruts | `writer.write(message)` + `await writer.drain()` (l. 303-304) |
| Lecture | octets bruts | `data = await reader.read(100)` (l. 313) |
| Pas d'auth/TLS | — | — |

## B.2 Cadre des messages (framing)

| Sens | Trame (octets) | Constantes aiokef |
|---|---|---|
| **GET** | `[0x47, registre, 0x80]` | `_GET_START=ord("G")=71`, `_GET_END=128` |
| **SET** | `[0x53, registre, 0x81, valeur]` | `_SET_START=ord("S")=83`, `_SET_MID=129` |
| Réponse **SET** OK | `[82, 17, 255]` (`0x52 0x11 0xFF`) | `FULL_RESPONSE_OK = bytes([82, 17, 255])` ; `_RESPONSE_OK = 17` |
| Réponse **GET** | valeur dans le **4ᵉ octet** | kefctl lit `substr($res, 3, 1)` |

Builders (aiokef) :
```python
def _get(which): return bytes([_GET_START, which, _GET_END])        # 3 octets
def _set(which): return lambda i: bytes([_SET_START, which, _SET_MID, i])  # 4 octets
```
Dispatch des réponses par `message[0] == ord("G")` / `ord("S")`.

## B.3 Registres

| Registre | Octet | Fonction | Constante aiokef |
|---|---|---|---|
| Volume | `0x25` (`'%'` = 37) | 0–100 ; **+128 = mute** | `_VOL = ord("%")` |
| Source/power | `0x30` (`'0'` = 48) | bitfield (B.4) | `_SOURCE = ord("0")` |
| Transport | `0x31` (`'1'` = 49) | play/pause/next/prev | `_CONTROL = ord("1")` |
| DSP — mode | `0x27` (39) | desk/wall/phase/HP/sub | `_MODE` |
| DSP — desk dB | `0x28` (40) | | `_DESK_DB` |
| DSP — wall dB | `0x29` (41) | | `_WALL_DB` |
| DSP — treble dB | `0x2A` (42) | | `_TREBLE_DB` |
| DSP — high-pass Hz | `0x2B` (43) | | `_HIGH_HZ` |
| DSP — low-pass Hz | `0x2C` (44) | | `_LOW_HZ` |
| DSP — sub dB | `0x2D` (45) | | `_SUB_DB` |

## B.4 Octet source/power (registre `0x30`) — bitfield complet

L'octet encode quatre champs (lecture MSB-first ; valeurs additives) :

| Champ | Poids | Détail |
|---|---|---|
| **Power** | `128` | 0 = allumé, 1 = **éteint** |
| **Inversion L/R** | `64` | 0 = L primaire, +64 = R primaire |
| **Veille** | `16` / `32` | +0 = 20 min, +16 = 60 min, +32 = jamais |
| **Entrée** | nibble bas | code 0–15 (ci-dessous) |

Codes d'entrée (nibble bas) :

| Entrée | Code | Binaire |
|---|---|---|
| Wi-Fi | 2 | `0010` |
| Bluetooth | 9 | `1001` |
| Aux | 10 | `1010` |
| Optique | 11 | `1011` |
| USB | 12 | `1100` |
| Bluetooth non appairé | 15 | `1111` (lecture seule) |

**Valeur finale = power + inversion + veille + code entrée.**

Exemples vérifiés (valeurs codées en dur par `pykef`, variante 60 min / L) :

| Commande | Octet | Décomposition |
|---|---|---|
| Wi-Fi | `0x12` = 18 | 16 (60 min) + 2 (wifi) |
| Bluetooth | `0x19` = 25 | 16 + 9 |
| Aux | `0x1A` = 26 | 16 + 10 |
| Optique | `0x1B` = 27 | 16 + 11 |
| USB | `0x1C` = 28 | 16 + 12 |
| **Éteindre** (depuis optique) | `0x9B` = 155 | 128 (off) + 16 + 11 |

> aiokef génère ces valeurs arithmétiquement : `INPUT_SOURCES_20_MINUTES_LR = {Wifi:2,
> Bluetooth:9, Bluetooth_paired:15, Aux:10, Opt:11, Usb:12}`, puis `code + i*16` pour la veille
> `[20, 60, None]`, et `(LR, LR+64)` pour L/R. Échelle volume : `_VOLUME_SCALE = 100.0`.

## B.5 Alimentation : pas de commande dédiée

- **Allumer** : `turn_on()` → `set_source(source, state="on")` (sélectionne une entrée, bit
  power à 0). Boucle de **20 tentatives × 1 s** (« le démarrage peut prendre 20 s »).
- **Éteindre** : `turn_off()` → `set_source(state.source, state="off")` avec `i += 128`.

### Pièges matériels (gén. 1)

- L'allumage TCP **ne marche pas** sur les LS50 Wireless d'origine : l'enceinte **coupe son
  interface réseau** en veille. Il faut les électroniques récentes (n° de série postérieur à
  `LS50W13074K24L/R2G`). La LSX, elle, s'allume.
- **Bug firmware** : `kefctl` bascule la veille de 20 → 60 min (`'00'` → `'01'`) **avant**
  d'éteindre, pour éviter de crasher le serveur de contrôle de l'enceinte.

## B.6 Mute (registre volume `0x25`)

Pas de commande mute dédiée : le bit 7 du volume porte le mute.

| Action | Octet de valeur | aiokef |
|---|---|---|
| Mute | `volume % 128 + 128` | `mute()` (l. 671) |
| Unmute | `volume % 128` | `unmute()` (l. 675) |
| État muet ? | `volume >= 128` | `is_muted = volume >= 128` (l. 477) |

## B.7 Transport (registre `0x31`)

| Action | Trame | kefctl |
|---|---|---|
| Play/Pause | `[0x53,0x31,0x81,0x81]` | `$PLAY="\x53\x31\x81\x81"` |
| Suivant | `[0x53,0x31,0x81,0x82]` | `$NEXT="\x53\x31\x81\x82"` |
| Précédent | `[0x53,0x31,0x81,0x83]` | `$PREV="\x53\x31\x81\x83"` |

> aiokef : `set_play_pause=_set(_CONTROL)(129)` (128 marche aussi), `next_track=…(130)`,
> `prev_track=…(131)`.

## B.8 Exemples (octets)

```text
Get volume     : 47 25 80                 → réponse : .. .. .. <vol>
Set volume 40  : 53 25 81 28              (0x28 = 40)
Mute (vol=40)  : 53 25 81 A8              (40 + 128 = 168 = 0xA8)
Get source     : 47 30 80
Set Wi-Fi 60min: 53 30 81 12
Power off      : 53 30 81 9B              (source courante + 128)
Next track     : 53 31 81 82
→ SET OK       : 52 11 FF
```

## B.9 Avertissement de précision (pykef)

Les commandes codées en dur de `pykef` comportent un **octet final supplémentaire**
(p.ex. Wi-Fi = `bytes([0x53,0x30,0x81,0x12,0x82])`, volume = `[0x53,0x25,0x81,vol,0x1A]`,
GET volume = `[0x47,0x25,0x80,0x6C]`). Ces octets **ne sont pas un checksum** : `aiokef` et
`kefctl` fonctionnent sans eux. La trame canonique est donc **3 octets (GET)** / **4 octets
(SET)** ; l'octet additionnel de pykef est probablement un artefact de capture. *(confiance :
moyenne — voir [VERIFICATION.md](VERIFICATION.md))*

## B.10 Intégration Swift possible (non fournie)

Le framework **`Network`** (`NWConnection` en `.tcp`) permet d'ouvrir le socket 50001,
d'écrire les `Data([0x53, …])` et de lire la réponse. KefBar ne l'implémente pas (cible
gén. 2 uniquement).
