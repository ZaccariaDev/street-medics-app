# Street Medics FR — Application

Application mobile Flutter d'urgence pour **street medics** : envoi de position
SOS, carte OpenStreetMap des SOS et des medics en service.

Backend : [PocketBase](https://pocketbase.io) auto-hébergé (dépôt séparé
`street-medics-server`).

## Principe d'architecture

- L'app est un **client réseau pur** : elle parle au serveur PocketBase par une
  **URL configurable** (onglet *Réglages*), via HTTP(S).
- **Aucune adresse `localhost`** ni dépendance à un tunnel dans le code.
- `adb` ne sert **qu'au développement** : installer l'APK et lire les logs. Une
  fois l'app finie, elle n'utilise ni `adb` ni `adb reverse` — le test final se
  fait par le réseau réel (URL publique du serveur).

## Fonctionnalités

| Onglet | Rôle |
|---|---|
| **SOS** | Envoie la position GPS + description dans `reports`. Prise / fin de service street medic (`medics`). |
| **Carte** | OpenStreetMap. Marqueurs **cliquables** : SOS (rouge = ouvert, orange = pris en charge, gris = résolu) et medics (vert). Fiche au tap avec **Prendre en charge** / **Résolu**. Bouton **Ma position** (recentre et zoome sur la rue). Rafraîchissement auto toutes les 20 s. |
| **Réglages** | URL du serveur (persistée), test de connexion, **langue** (langue du téléphone par défaut), **rayon d'alerte**, **nom de street medic**, compte. |

## Permissions

L'app demande les autorisations à **deux moments** :

1. **Au premier lancement** — boîte « Autorisations nécessaires » listant :
   notifications, localisation, localisation « toujours » (arrière-plan),
   exemption d'optimisation batterie.
2. **À la prise de service** — si une autorisation manque (surtout la
   localisation « toujours », indispensable au suivi app fermée), la boîte
   réapparaît avec le texte adapté et **uniquement les éléments manquants**.

Le bouton **Autoriser** déclenche les demandes système dans l'ordre
(notifications → localisation → localisation toujours → batterie). Sur
Android 11+, la localisation « toujours » n'existe que dans les réglages de
l'app : l'app ouvre directement l'écran concerné. Code : `lib/perms.dart`.

## Comptes et lecture protégée

La **lecture** des signalements et des medics exige un **compte** (les règles
du serveur vérifient `@request.auth.id != ""`). Sans compte, on peut envoyer
un SOS mais pas voir la carte.

- **Inscription / connexion** dans l'onglet Réglages, section *Compte street
  medic*. La session est **persistée 30 jours** : on ne se reconnecte pas à
  chaque lancement.
- L'onglet **Plan** est grisé (cadenas) tant qu'on n'est pas **à la fois**
  en service et connecté.
- L'écriture d'un SOS reste **publique** : une personne en détresse ne doit
  pas avoir à créer un compte pour appeler à l'aide.

## Durcissement des règles

Les règles PocketBase ont été resserrées (voir `HARDENING.md` du dépôt
serveur) : suppression interdite, création d'un SOS limitée au statut `open`,
modification limitée aux transitions de statut, fiche medic liée au
`deviceId`, et **lecture réservée aux comptes**.

## Mise à jour de l'app

L'app est **publiable sur le Play Store** et **mettable à jour** :

- **Release signée** : le keystore et `android/key.properties` sont prêts
  (jamais commités). L'AAB Play Store se construit avec
  `flutter build appbundle --release`.
- **Versioning** : `pubspec.yaml` porte `version: 1.0.0+1` (nom + code). Le
  code doit **strictement augmenter** à chaque release.
- **Détection de mise à jour** : au démarrage, l'app compare son `versionCode`
  à celui publié dans la collection `app_release` du serveur et affiche une
  popup (bloquante si `mandatory`). Bouton **Vérifier les mises à jour** dans
  les Réglages.
- **Publication en une commande** :
  `PB_PASSWORD=... ./tools/release.sh 1.0.1 "notes"`

Voir **[PUBLISHING.md](PUBLISHING.md)** pour le guide complet Play Store.

## Itinéraire vers un SOS
Quand un street medic **accepte d'aider**, l'app ouvre directement le choix de
l'application de navigation : **Google Maps**, **Waze**, ou une autre app
installée (Organic Maps, OSMAnd…). La destination est déjà remplie, c'est
l'app choisie qui calcule le **trajet le plus court** et guide le medic.

Le bouton **Trajet le plus court vers le SOS** reste accessible depuis la fiche
du signalement. La distance approximative (à vol d'oiseau) est affichée.

## Langues

**24 langues**, sélectionnées automatiquement d'après la langue du téléphone
(anglais par défaut, surcharge manuelle possible dans les Réglages) :
en, fr, ar, bn, de, el, es, fa, he, hi, id, it, ja, ko, nl, pl, pt, ro, ru, sw,
tr, uk, vi, zh. Source : `lib/l10n/app_<code>.arb` (généré par `flutter gen-l10n`).

## Appel des urgences (monde entier)

Bouton **Appeler les urgences** (onglet SOS + carte) : propose les numéros du
pays courant d'après les **données AOSP officielles** (227 pays/territoires),
avec le service associé (tous services, ambulance, police, pompiers) et repli
sur le 112. Source : `lib/emergency_numbers.dart` (généré depuis
`packages/services/Telephony/ecc`).

## Service d'arrière-plan (medic en service)

Quand le medic prend le service, un **service de premier plan** démarre :

- le medic peut **fermer l'app** : le service continue ;
- la **position est mise à jour toutes les 30 s** côté serveur ;
- dès qu'un SOS apparaît dans le **rayon d'alerte** (réglable, 0,5–50 km), le
  medic reçoit une **notification + un son d'alarme distinctif**
  (`android/app/src/main/res/raw/alarm.mp3`, généré, libre de droits).

Le service s'arrête avec **Terminer mon service**.


## Workflow medics

1. Le medic prend le service (onglet SOS) : une fiche `medics` est créée/mise à
   jour, identifiée par un `deviceId` persistant — **pas de doublon** à chaque
   prise de service.
2. Un SOS apparaît sur la carte (pastille rouge). Le medic tape dessus.
3. **Prendre en charge** → le SOS passe en `claimed` (pastille orange) avec le
   nom du medic ; **Résolu** → `resolved` (pastille grise).

## Configuration

Dans l'app : onglet **Réglages** → *URL du serveur* → par ex.
`http://<ip-serveur>:8090` ou `https://votre-domaine` → **Tester**.

L'URL est persistée sur l'appareil (`shared_preferences`) ; le client PocketBase
est reconstruit à chaud quand elle change.

## Build (ligne de commande)

```bash
export PATH="$PATH:/root/tools/flutter/bin"
export ANDROID_HOME=/usr/lib/android-sdk
flutter pub get
flutter analyze
flutter test
flutter build apk --debug     # -> build/app/outputs/flutter-apk/app-debug.apk
```

## Installation sur l'appareil (dev)

```bash
adb connect <host>:<port>          # ou 127.0.0.1:5555 si tunnel adb
adb push build/app/outputs/flutter-apk/app-debug.apk /data/local/tmp/app.apk
adb shell "pm install -r /data/local/tmp/app.apk"   # pm install, plus fiable sur MIUI
```

## Dépendances notables

- `pocketbase` — client PocketBase
- `flutter_map` 8.x + `latlong2` — carte OpenStreetMap (OSM uniquement)
- `geolocator` — position GPS (la permission est demandée via geolocator, pas de
  `permission_handler` : ce dernier exige `compileSdk 37`)
- `shared_preferences` — persistance de l'URL serveur
