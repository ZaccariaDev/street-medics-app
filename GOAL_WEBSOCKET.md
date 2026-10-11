# GOAL IDÉAL — Migration WebSocket/SSE (scalabilité)

## Résultat final attendu

L'app utilise **PocketBase Realtime (WebSocket)** au lieu du polling REST pour les mises à jour de la carte et des alertes. Résultat : **-95% de requêtes serveur**, temps réel (~100ms), capacité 10 000+ utilisateurs simultanés sur un seul VPS.

## Contexte vérifié

- **Problème actuel** : chaque utilisateur poll le serveur toutes les 20s (carte) + 30s (position bg_service) → ~300 000 req/h pour 1000 utilisateurs
- **Solution** : PocketBase Realtime (WebSocket intégré) — le serveur pousse les changements uniquement quand quelque chose change
- **SDK PocketBase** : `client.realtime.subscribe()` déjà disponible dans le package `pocketbase: ^0.25.2`
- **bg_service** : tourne en isolate séparé, utilise `http.Client` directement (pas le SDK) → doit être migré aussi
- **Collections concernées** : `reports` (SOS), `medics` (positions)

## Décisions d'architecture

- **WebSocket pour la carte** : `client.realtime.subscribe('reports', ...)` + `client.realtime.subscribe('medics', ...)` → mise à jour instantanée des blips
- **bg_service** : passer de polling 30s → WebSocket aussi (ou garder polling mais avec backoff adaptatif)
- **Fallback** : si WebSocket échoue → retour au polling 20s (robustesse)
- **Géolocalisation** : le bg_service envoie la position toutes les 30s → passer à 60s + seulement si déplacement > 100m

## Périmètre et exclusions

- ✅ `pb_service.dart` — ajout `subscribeReports()`, `subscribeMedics()`, `unsubscribeAll()`
- ✅ `main.dart` — `MapTab` : remplacer `_refresh()` polling par WebSocket
- ✅ `bg_service.dart` — migrer le polling 30s → WebSocket ou backoff adaptatif
- ✅ `config.dart` — rien à changer
- ❌ Pas de changement de l'UI (les blips se mettent à jour instantanément, c'est tout)
- ❌ Pas de changement du protocole SOS/medics (mêmes collections, mêmes champs)

## Jalons et passes exécutables

### Jalon 1 — WebSocket côté client (carte)

- **P1** : `PbService.subscribeReports(callback)` — subscribe à la collection `reports`, appelle le callback à chaque create/update/delete
- **P2** : `PbService.subscribeMedics(callback)` — subscribe à la collection `medics`
- **P3** : `MapTab` : remplacer `_refresh()` polling par `subscribeReports` + `subscribeMedics` → setState direct
- **P4** : Supprimer `_autoTimer` (polling 20s) de `MapTab`
- **P5** : Test : envoyer un SOS depuis un autre appareil → le blip apparaît instantanément sur la carte

### Jalon 2 — bg_service migré

- **P1** : `bg_service.dart` : remplacer le polling 30s par WebSocket (ou backoff adaptatif 30s→120s)
- **P2** : Envoyer la position seulement si déplacement > 100m (géoloc)
- **P3** : Test : prendre le service → la position se met à jour sans spam serveur

### Jalon 3 — Fallback et robustesse

- **P1** : Si WebSocket se déconnecte → retour automatique au polling 20s
- **P2** : Reconnexion WebSocket automatique après 5s
- **P3** : Test : tuer le réseau → l'app passe en polling → le réseau revient → WebSocket se rétablit

### Jalon 4 — Validation finale

- **P1** : Test complet : 2 appareils, SOS en temps réel, prise de service, fin de service
- **P2** : Mesure : comparer le nombre de requêtes serveur avant/après (objectif : -95%)
- **P3** : APK installé et testé sur ton téléphone

## Critères d'acceptation

- Un SOS envoyé depuis un appareil apparaît **instantanément** sur la carte d'un autre (< 500ms)
- Le polling 20s de la carte est **supprimé**
- Le bg_service n'envoie la position que si déplacement > 100m
- Si WebSocket échoue → fallback polling automatique
- `flutter analyze` : aucune erreur
- APK installé et testé

## Boucle de travail et vérification

1. Relire l'état actuel et vérifier les prérequis
2. Choisir la prochaine action qui rapproche du résultat
3. Réaliser cette action dans son périmètre
4. Vérifier le comportement obtenu avec des contrôles proportionnés
5. Consigner le résultat observé, les limites et la prochaine action
6. Continuer automatiquement dans le périmètre autorisé

## Mémoire de progression et reprise

Maintenir un état durable et compact dans `PROGRESS.md` du projet.

## Conditions de fin, stagnation et intervention humaine

- **Fin** : les 4 jalons sont validés sur le téléphone
- **Stagnation** : si un jalon bloque plus de 3 passes sans progression, documenter et demander
- **Intervention humaine** : si le serveur PocketBase n'a pas Realtime d'actif, notifier l'utilisateur

## Limites d'effort

- Pas de budget de tokens explicite
- Pas de deadline stricte
- Priorité : Jalon 1 → Jalon 2 → Jalon 3 → Jalon 4
