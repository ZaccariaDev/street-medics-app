# Publier Street Medics sur le Play Store

Ce guide couvre la mise en ligne **et** les mises à jour suivantes.

## 1. Prérequis (une seule fois)

- **Compte Google Play Console** — 25 $ une fois, sur
  https://play.google.com/console
- **Politique de confidentialité** — obligatoire. À héberger (GitHub Pages,
  un dossier sur le serveur…). L'app collecte la position et un numéro de
  téléphone optionnel.
- **Fiche de sécurité des données** (Data safety) — à remplir dans la console :
  déclarer la collecte de la **position** et du **numéro de téléphone**.
- **Classification de contenu** — l'app est un outil d'urgence : à remplir
  honnêtement (pas de contenu violent, mais usage médical).

## 2. Signature

Le keystore a été généré dans `/root/keys/street-medics-upload.jks`, et
`android/key.properties` contient ses identifiants.

> **⚠️ SAUVEGARDE OBLIGATOIRE.** Copie le `.jks` **et** le mot de passe
> (`/root/keys/PASSWORD.txt`) dans un endroit sûr. Si tu les perds, tu ne
> pourras **plus jamais** publier de mise à jour de cette app.

Les deux fichiers sont exclus de git (`.gitignore`). Ne les commite jamais.

Empreinte de la clé (à conserver, utile en cas de litige Play) :

```
SHA-256: fefc91925fe935cbd2a3a96c93ec36ad876c51dbcaaf05b132a18bf1f05d624b
SHA-1  : 897f6501aea1fef4b4af6426168684d4ce77db9b
```

> Note : Google recommande **Play App Signing** (Google conserve la clé de
> signature finale). Active-le dans la console : c'est la clé ci-dessus qui
> devient la « clé de téléversement », et Google gère le reste.

## 3. Construire l'AAB

Le Play Store n'accepte que le format **AAB** (Android App Bundle).

```bash
cd /root/projects/street-medics-app
export PATH="$PATH:/root/tools/flutter/bin"
export ANDROID_HOME=/usr/lib/android-sdk
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

## 4. Mettre à jour l'app (le cas courant)

Tout est scripté :

```bash
cd /root/projects/street-medics-app
PB_PASSWORD='<mot de passe superuser PocketBase>' \
  ./tools/release.sh 1.0.1 "Correction du suivi en arrière-plan"
```

Ce que fait le script :

1. incrémente le `versionCode` dans `pubspec.yaml` (**obligatoire** : Android
   refuse d'installer une mise à jour dont le code n'a pas augmenté) ;
2. construit l'AAB signé ;
3. déclare la version sur le serveur (collection `app_release`).

Ensuite : **Play Console → Production → Créer une release → téléverser l'AAB**.
Google relaie la mise à jour aux appareils automatiquement.

### Mise à jour obligatoire

Pour forcer les utilisateurs à mettre à jour (correctif critique) :

```bash
PB_PASSWORD='...' ./tools/release.sh 1.0.2 "Correctif critique" --mandatory
```

L'app affiche alors une popup **non fermable** avec le bouton « Mettre à jour ».

## 5. Comment la mise à jour arrive à l'utilisateur

Deux canaux, complémentaires :

| Canal | Délai | Qui décide |
|---|---|---|
| **Play Store** | quelques heures à 2 jours | Google, automatiquement |
| **Popup dans l'app** | immédiat | toi, via `app_release` |

L'app vérifie au démarrage le `versionCode` publié dans `app_release` et, si
le sien est inférieur, propose une popup avec un bouton « Mettre à jour » qui
ouvre la fiche Play Store. C'est un **compliment** au Play Store : utile pour
prévenir d'un correctif important sans attendre le déploiement Google.

Un bouton **Vérifier les mises à jour** est aussi disponible dans les Réglages,
avec le numéro de version installée affiché.

## 6. Remplir la fiche Play Store

- **Nom** : Street Medics
- **Description courte** : alerte les street medics à proximité en cas d'urgence
- **Catégorie** : Médical (ou Santé et remise en forme)
- **Captures d'écran** : au moins 2 (téléphone). Prends-les sur un appareil réel.
- **Icône** : 512×512 PNG. L'icône actuelle est celle de Flutter, à remplacer.
- **Bannière** : 1024×500 PNG.

## 7. Points de vigilance (examen Play)

Google examine les apps qui touchent à la **santé** et à la **localisation en
arrière-plan**. Attends-toi à des questions. Prépare :

1. **Pourquoi la localisation en arrière-plan ?** → « suivi de la position du
   secouriste pendant son service, pour que les personnes en détresse voient
   les medics disponibles ». Montre la vidéo de démonstration si demandé.
2. **Pourquoi le service de premier plan ?** → même raison ; une notification
   permanente est visible pendant tout le service.
3. **Sécurité des données** → la position est envoyée au serveur auto-hébergé
   de l'organisation, pas revendue.
4. **Usage médical** → l'app **ne remplace pas** les secours. Le message
   d'engagement le rappelle, et le bouton « Appeler les urgences » est présent
   sur les deux écrans principaux. Insiste là-dessus.

## 8. Avant de publier : à faire

- [ ] **Durcir les règles PocketBase** — actuellement `reports` et `medics`
      sont en lecture **et écriture** publiques : n'importe qui peut modifier
      ou supprimer les signalements. À restreindre avant toute vraie mise en
      ligne.
- [ ] Remplacer l'icône Flutter par une vraie icône.
- [ ] Héberger la politique de confidentialité et coller son URL.
- [ ] Vérifier le nom du serveur par défaut dans `lib/config.dart` (c'est
      actuellement l'adresse de **test**).
