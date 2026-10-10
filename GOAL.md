# GOAL IDÉAL — Authentification automatique + token persistant

## Résultat final attendu

Chaque appareil s'authentifie automatiquement auprès de PocketBase au démarrage
(token enregistré localement, re-login sans aucune saisie), l'identité `deviceId`
persiste, toutes les requêtes serveur sont authentifiées, et le serveur peut
servir de table de routage (idée de Rickie) via `request.auth.id`.

## Contexte vérifié

- La collection `users` (auth) existe déjà dans PocketBase mais n'est pas utilisée
  (`PbService` ne fait pas d'auth)
- `f51ab2d` a supprimé l'inscription/connexion manuelle ; `02a7bd3` avait une session
  persistée 30j (même approche, à réintroduire automatiquement)
- `deviceId` est déjà l'identité locale (fiche `medics`, règles serveur PocketBase
  l'exigent)
- `bg_service` tourne selon deviceId (mode medic) ou `patientReportId` (mode patient)
- The store `medics` has a `deviceId` field used by `_findMedicByDevice`

## Décisions d'architecture (hypothèses identifiées)

- **A (recommandée)** : `deviceId` reste l'identité métier ; le token auth est une
  couche d'accès serveur. Le compte est auto-généré :
  `email = dev-{deviceId}@streetmedics.local`, mot de passe aléatoire (32 octets
  base64) stocké dans `SharedPreferences` au premier lancement
- **Option non retenue** : remplacer `deviceId` par l'user ID PocketBase partout —
  trop invasif (règles serveur, bg_service, deviceId existant)

## Périmètre et exclusions

- ✅ Client Flutter (PbService, AppConfig, écran Réglages : indicateur « Connecté »)
- ✅ Config serveur PocketBase (API rules : exiger auth sur `medics`/`reports`,
  champ `authId` dans `medics`)
- ❌ Pas de nouvelle UI de login (le compte est invisible pour l'utilisateur)
- ❌ Pas de changement du protocole carte temps réel
- ❌ Pas de chiffrement du stockage local (limite acceptable, notée)

## Jalons et passes exécutables

### Jalon 1 — Auto-auth au démarrage

- **P1** : `PbService.ensureAuth()` : tente `authWithPassword` avec les identifiants
  stockés ; si 404 → `collection('users').create()` + sauvegarde des creds ;
  retourne le token
- **P2** : Appeler `ensureAuth()` depuis `AppConfig.load()` ou `main()` avant tout
  appel API
- **P3** : `AppConfig` : clés `_authEmail`, `_authPassword` dans
  `SharedPreferences`, getters/setters

### Jalon 2 — Persistance de session 30j

- **P1** : À chaque démarrage : si token présent → `authRefresh` (silencieux) ;
  si expiré → re-login auto
- **P2** : Après chaque requête 401 (retry HTTP) → forcer re-login et réessayer
- **P3** : Test : kill process + relaunch → toujours authentifié, pas de doublon
  de compte

### Jalon 3 — Routage serveur

- **P1** : Ajouter `authId` (lecture seule) dans la fiche `medics`, rempli à la
  prise de service avec `pb.authStore.model.id`
- **P2** : API rules serveur : `medics`/`reports` exigent `request.auth.id != ''`
- **P3** : Test : un token révoqué ne peut plus écrire

### Jalon 4 — Validation sur téléphone

- Prise de service → blip, hors service → suppression, reprise → 1 seul blip,
  kill+relaunch → auth auto

## Critères d'acceptation

- Démarrage → auth en < 2 s sans saisie
- Kill/relaunch → toujours authentifié, aucun compte dupliqué
- Analyse Flutter : aucune erreur
- APK installé et parcours complet validé sur ton téléphone

## Boucle de travail et vérification

1. Relire l'état actuel et vérifier les prérequis pertinents
2. Choisir la prochaine action qui rapproche du résultat
3. Réaliser cette action dans son périmètre
4. Vérifier le comportement obtenu avec des contrôles proportionnés
5. Consigner le résultat observé, les limites et la prochaine action
6. Continuer automatiquement dans le périmètre autorisé

## Mémoire de progression et reprise

Maintenir un état durable et compact dans `PROGRESS.md` du projet :
- objectif accepté
- jalon et passe en cours
- résultats validés et preuves
- décisions structurantes
- blocages et tentatives effectuées
- prochaine action précise

## Conditions de fin, stagnation et intervention humaine

- **Fin** : les 4 jalons sont validés sur le téléphone
- **Stagnation** : si un jalon bloque plus de 3 passes sans progression, documenter
  le blocage et demander une décision humaine
- **Intervention humaine** : si la config serveur PocketBase est inaccessible, notifier
  l'utilisateur et attendre ses instructions

## Limites d'effort

- Pas de budget de tokens explicite demandé
- Pas de deadline stricte
- Priorité : Jalon 1 → Jalon 2 → Jalon 3 → Jalon 4
