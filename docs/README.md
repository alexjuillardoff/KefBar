# Documentation KefBar

Documentation complète du projet **KefBar** — une app barre de menus macOS pour piloter
des enceintes KEF Wi-Fi.

Ce dossier raconte **ce qui a été fait**, **ce qui a été appris** sur les enceintes KEF,
et **comment tout fonctionne** (de l'octet réseau jusqu'au SwiftUI).

## Sommaire

| Document | Contenu |
|---|---|
| [GUIDE.md](GUIDE.md) | **Guide pas à pas pour débutants** : installation et premier usage expliqués sans jargon, en 10 minutes. À lire en premier si vous n'êtes pas développeur. |
| [RESEARCH.md](RESEARCH.md) | **Ce que j'ai appris** : enquête sur les API KEF, les deux générations d'enceintes, l'absence d'API officielle, l'écosystème open-source (tableau comparatif détaillé), l'intégration officielle, les approches macOS. Avec sources. |
| [PROTOCOL.md](PROTOCOL.md) | **Référence exhaustive du protocole** : l'API locale HTTP/JSON (gén. 2) et le protocole binaire TCP (gén. 1), endpoint par endpoint, réponses JSON complètes, séquences d'octets, exemples `curl` et Swift. |
| [VERIFICATION.md](VERIFICATION.md) | **Traçabilité & preuves** : d'où vient chaque détail du protocole (fichier + ligne + extrait de code), niveaux de confiance, et ce qui n'a pas été testé. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | **Comment l'app fonctionne** : couches, signatures exactes, modèle de concurrence, séquencement, mécanismes (debounce, machine d'état), pièges, et points d'extension. |

Pour l'installation et l'usage, voir le [README principal](../README.md).

---

## 1. Le problème de départ

> « J'ai des enceintes KEF connectées au Wi-Fi. Je voudrais créer un logiciel macOS pour
> les piloter via la barre de menus. Est-ce possible ? Quelle API ? Docs constructeur ?
> Système de communication locale ? »

La réponse courte : **oui, c'est faisable**, mais KEF ne fournit **aucune API officielle**.
Le pilotage passe par une **API locale non documentée**, rétro-ingénieriée depuis l'app
mobile KEF Connect. Et surtout, il existe **deux protocoles totalement différents** selon
la génération des enceintes.

## 2. Ce qui a été construit

Une app macOS native (**Swift / SwiftUI**) vivant dans la barre de menus, ciblant les
enceintes KEF de **2ᵉ génération** (LSX II, LS50 Wireless II, LS60, XIO) via leur API
HTTP/JSON locale.

Fonctions : volume + mute, marche/arrêt (veille), sélection de source, transport
(play/pause, suivant/précédent), pilotage par les **touches média du clavier** (+ intégration
« En cours de lecture » macOS), affichage de la lecture en cours (titre/artiste/pochette),
rafraîchissement automatique.

```
KefBar/
├── Package.swift              # manifeste SwiftPM (exécutable, macOS 13+)
├── README.md                  # installation & usage
├── Sources/KefBar/
│   ├── KefBarApp.swift        # point d'entrée : MenuBarExtra + app accessoire
│   ├── ContentView.swift      # UI du menu (slider, transport, sources, power)
│   ├── AppState.swift         # état observable + actions + flux d'évènements temps réel
│   ├── NowPlayingCenter.swift # touches média clavier + « En cours de lecture » macOS
│   ├── KefClient.swift        # couche réseau : LE protocole KEF
│   └── Models.swift           # Source, NowPlaying, erreurs
├── Resources/Info.plist       # bundle : Dock masqué + exception réseau local
├── Scripts/build-app.sh       # packaging en .app signée ad-hoc
└── docs/                      # ← vous êtes ici
```

## 3. Méthode

Les détails du protocole n'étant pas documentés par KEF, ils ont été **établis puis
vérifiés directement dans le code source** des bibliothèques open-source de référence :

- **Gén. 2 (HTTP/JSON)** : vérifié contre [`pykefcontrol`](https://github.com/N0ciple/pykefcontrol)
  et corroboré par `m-lange/kef_speaker`, le gist `aadje`, et `kef-mcp`.
- **Gén. 1 (TCP binaire)** : vérifié ligne par ligne contre le source de
  [`aiokef`](https://github.com/basnijholt/aiokef) (port 50001, trames `bytes([...])`).

Puis l'implémentation Swift a été **compilée et packagée avec succès** (`swift build` +
bundle `.app` signé). Elle n'a en revanche **pas été testée contre une enceinte physique**
— voir les réserves dans [ARCHITECTURE.md](ARCHITECTURE.md#limites-et-points-à-valider).

## 4. État du projet

| | |
|---|---|
| Compile (`swift build`) | ✅ |
| Bundle `.app` (`Scripts/build-app.sh`) | ✅ signé ad-hoc, `LSUIElement` actif |
| Testé sur enceinte réelle | ⚠️ non — à valider |
| Génération ciblée | KEF gén. 2 (W2 : LSX II / LS50 W II / LS60 / XIO) |
| macOS minimum | 13 Ventura |
