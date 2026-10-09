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
| **SOS** | Envoie la position GPS + description dans la collection `reports`. Bouton secondaire : prise de service street medic (collection `medics`). |
| **Carte** | OpenStreetMap (tuiles OSM). Affiche les SOS (rouge), les medics (vert) et votre position (bleu). Bouton rafraîchir. |
| **Réglages** | URL du serveur (persistée), test de connexion, création/connexion de compte. |

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
