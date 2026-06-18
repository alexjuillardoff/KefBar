# 🟢 Guide de démarrage — pour débutants

Ce guide vous accompagne **pas à pas**, sans jargon, de zéro jusqu'à votre premier
réglage de volume depuis la barre de menus. Comptez **10 minutes**.

> Vous cherchez juste les commandes ? Voir le [README](../README.md).
> *Looking for the English version? The README has an [English section](../README.md#-english).*

---

## 1. C'est quoi KefBar ?

Une petite icône 🔊 qui s'installe **en haut à droite de votre écran Mac** (la « barre de
menus », à côté de l'horloge et du Wi-Fi). En cliquant dessus, vous contrôlez vos enceintes
**KEF Wi-Fi** : volume, marche/arrêt, source, lecture… sans sortir votre téléphone.

✅ Fonctionne avec les enceintes **KEF de 2ᵉ génération** : **LSX II, LS50 Wireless II,
LS60 Wireless, KEF XIO**.
❌ Ne fonctionne **pas** avec les anciennes (LSX, LS50 Wireless 1ʳᵉ génération).

---

## 2. Ce qu'il vous faut (checklist)

- [ ] Un **Mac** sous **macOS 13 (Ventura)** ou plus récent.
      *(Pomme  → « À propos de ce Mac » pour vérifier la version.)*
- [ ] Vos enceintes KEF **allumées et connectées au même Wi-Fi** que le Mac.
- [ ] L'**adresse IP** de vos enceintes (on la trouve à l'étape 3).
- [ ] **5 minutes** pour installer les outils de développement Apple (gratuit, étape 4).

---

## 3. Trouver l'adresse IP de vos enceintes

L'adresse IP ressemble à `192.168.1.42`. Deux façons de la trouver :

**Méthode simple — via l'app KEF Connect (sur votre téléphone) :**
1. Ouvrez l'app **KEF Connect**.
2. Allez dans **Réglages** (⚙️) → choisissez votre enceinte → **Infos**.
3. Notez la ligne **Adresse IP**.

**Méthode alternative — via votre box internet :**
1. Connectez-vous à l'interface de votre box (souvent `192.168.1.1` dans le navigateur).
2. Cherchez la liste des **appareils connectés** : votre enceinte y apparaît (nom type
   « KEF LS50 » ou « LSXII »). Notez son IP.

> 💡 **Conseil important :** dans les réglages de votre box, **réservez une IP fixe**
> (« bail statique » / « DHCP réservé ») pour votre enceinte. Sinon l'IP peut changer
> et il faudra la ressaisir dans KefBar.

---

## 4. Installer les outils Apple (une seule fois)

KefBar se construit à partir de son code source. Pour cela, le Mac a besoin des **outils
de développement en ligne de commande** d'Apple (gratuits).

1. Ouvrez l'app **Terminal** (⌘ + Espace, tapez « Terminal », Entrée).
2. Copiez-collez cette commande et appuyez sur Entrée :
   ```bash
   xcode-select --install
   ```
3. Une fenêtre s'ouvre : cliquez sur **Installer** et acceptez. Patientez quelques minutes.

> Si vous avez déjà **Xcode** installé, cette étape est déjà faite.

---

## 5. Télécharger et construire l'app

Toujours dans le **Terminal**, copiez-collez ces trois lignes, une par une :

```bash
git clone https://github.com/alexjuillardoff/KefBar.git
cd KefBar
./Scripts/build-app.sh
```

- La 1ʳᵉ ligne télécharge le projet.
- La 2ᵉ entre dans le dossier.
- La 3ᵉ **fabrique l'application** `KefBar.app` (ça prend ~1 minute).

Quand c'est fini, ouvrez l'app :

```bash
open ./KefBar.app
```

> 📦 Vous pouvez ensuite **glisser `KefBar.app` dans votre dossier Applications** pour
> la garder à portée de main.

---

## 6. « macOS n'a pas pu vérifier l'app » — c'est normal

Comme l'app n'est pas distribuée par l'App Store, macOS affiche un avertissement au premier
lancement. C'est attendu pour un projet open-source. Pour l'autoriser :

1. **Clic droit** (ou Ctrl + clic) sur `KefBar.app` → **Ouvrir**.
2. Dans la fenêtre, cliquez à nouveau sur **Ouvrir**.

Vous ne le ferez **qu'une seule fois**. Ensuite l'app s'ouvre normalement.

---

## 7. Premier réglage : entrer l'IP

1. L'icône 🔊 apparaît **en haut à droite** de l'écran. Cliquez dessus.
2. Cliquez sur l'icône **⚙️** (réglages).
3. Saisissez l'**adresse IP** notée à l'étape 3 (ex. `192.168.1.42`).
4. Validez. 🎉 Le volume, la source et le titre en cours doivent apparaître.

---

## 8. Au quotidien

Cliquez sur l'icône 🔊 pour :

- 🔈 **glisser le volume** ou couper le son ;
- ⏻ **allumer / mettre en veille** les enceintes ;
- 🔀 **changer de source** (Wi-Fi, Bluetooth, TV/HDMI, Optique, Coaxial, Aux) ;
- ⏯️ **lecture / pause**, piste **suivante / précédente** ;
- 🎵 voir le **titre, l'artiste et la pochette** en cours.

### Lancer KefBar automatiquement au démarrage

Réglages système → **Général** → **Ouverture** → **Ouvrir à la connexion** →
bouton **+** → choisissez `KefBar.app`. L'app sera là à chaque démarrage du Mac.

---

## 9. Dépannage (FAQ)

**❓ L'icône n'apparaît pas / pas dans le Dock.**
C'est voulu : KefBar vit **uniquement dans la barre de menus** (en haut), jamais dans le
Dock. Regardez en haut à droite, près de l'horloge.

**❓ « Aucune connexion » ou rien ne réagit.**
- Vérifiez que l'enceinte est **allumée** et sur le **même Wi-Fi** que le Mac.
- Revérifiez l'**IP** (étape 3) — elle a peut-être changé. Ressaisissez-la dans ⚙️.
- Testez la connexion dans le Terminal (remplacez l'IP) :
  ```bash
  curl "http://192.168.1.42/api/getData?path=player:volume&roles=value"
  ```
  Si ça renvoie du texte JSON, l'enceinte répond bien.

**❓ Ça marchait, puis plus rien.**
L'IP de l'enceinte a sans doute changé. **Réservez une IP fixe** dans votre box (étape 3, conseil).

**❓ Après une mise à jour des enceintes, certaines fonctions buguent.**
L'API KEF n'est pas officielle : une mise à jour de firmware peut la modifier. C'est une
limite connue (voir l'[avertissement](../README.md#-disclaimer--avertissement)).

**❓ Je ne suis pas à l'aise avec le Terminal.**
Tout se résume à **copier-coller** les commandes des étapes 4 et 5, une par une, en appuyant
sur Entrée. Rien d'autre à taper.

---

Un souci, une idée ? Ouvrez une **[issue sur GitHub](https://github.com/alexjuillardoff/KefBar/issues)**.
