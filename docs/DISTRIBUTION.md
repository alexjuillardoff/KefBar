# Distribution — signature & notarisation

Pour qu'un `KefBar.app` téléchargé s'ouvre **sans aucun avertissement** chez tous les
utilisateurs, il doit être **signé Developer ID** puis **notarisé par Apple**. Sans cela,
macOS affiche « Apple n'a pas pu confirmer que KefBar ne contenait pas de logiciel
malveillant » (et sur macOS 15 Sequoia, le contournement « clic droit → Ouvrir » a disparu).

Le script [`Scripts/notarize-app.sh`](../Scripts/notarize-app.sh) automatise tout une fois
le compte configuré. Voici le **setup initial** (à faire une seule fois).

## Pré-requis

- Compte **Apple Developer Program** (99 $/an).
- Xcode installé (fournit `notarytool` et `stapler`).

## 1. Créer le certificat « Developer ID Application »

Le plus simple, via Xcode :

1. **Xcode → Settings → Accounts**, connectez votre identifiant Apple Developer.
2. Sélectionnez votre équipe → **Manage Certificates…**
3. Bouton **+** → **Developer ID Application**.

Le certificat et sa clé privée arrivent dans le trousseau. Vérification :

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Vous devez voir une ligne du type
`Developer ID Application: Alexis Juillard (XXXXXXXXXX)` — le code entre parenthèses est
votre **Team ID**.

> La création d'un certificat *Developer ID* exige d'être **Account Holder** de l'équipe.

## 2. Créer un mot de passe spécifique à l'app

Sur [appleid.apple.com](https://appleid.apple.com) → **Connexion et sécurité → Mots de
passe pour les apps** → générez-en un (ex. « notarytool »). Notez-le.

## 3. Enregistrer le profil notarytool

Une seule fois, stocke les identifiants dans le trousseau sous le nom `KefBarNotary` :

```bash
xcrun notarytool store-credentials "KefBarNotary" \
  --apple-id "votre-identifiant@apple.com" \
  --team-id "XXXXXXXXXX" \
  --password "xxxx-xxxx-xxxx-xxxx"   # le mot de passe spécifique de l'étape 2
```

## 4. Builder, signer, notariser, agrafer

```bash
./Scripts/notarize-app.sh
```

Le script : compile l'universel, signe en **hardened runtime + timestamp**, envoie à Apple,
attend le verdict, **agrafe** le ticket sur le `.app`, puis produit `KefBar.zip`.

## 5. Publier

```bash
gh release upload v0.1 KefBar.zip --clobber
```

Le `.app` agrafé s'ouvre désormais d'un simple double-clic chez tout le monde — plus aucun
avertissement Gatekeeper.

## Vérifier

```bash
spctl --assess --type execute --verbose=4 KefBar.app   # doit dire : accepted / Notarized Developer ID
xcrun stapler validate KefBar.app                      # doit dire : The validate action worked!
```
