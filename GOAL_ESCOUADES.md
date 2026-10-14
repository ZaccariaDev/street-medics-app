# GOAL — Fermeture app + Escouades + API Mobilisations

## État réel (honnête)

### ✅ Vérifié
- Analyze propre
- 97/97 tests passent
- Filtre réseau (SocketException, DNS, timeout) — ne remonte plus sur Discord

### 🔧 Code écrit (non testé sur appareil)
1. **Fermeture app** : WidgetsBindingObserver + timer 30s → setMedicOffDuty + log
2. **Choix escouade** : UI RadioListTile dans le dialogue d'engagement
3. **Logique escouade** : PbService.createSquad/joinSquad/leaveSquad/findOpenSquad + migration serveur + branchement _goOnDuty/_goOffDuty
4. **API mobilisations** : MobilisationService + markers orange + bouton toggle

### ⏳ Reste à faire
- Tester sur le téléphone (éteint pour le moment)
- Vérifier que le serveur PocketBase a bien la collection squads (migration à appliquer par l'utilisateur)
- Analysier l'historique Discord #app-errors (délégation en arrière-blind)
- Bump version + build AAB une fois validé

## Serveur (à déployer par l'utilisateur)
- Migration : `pb_migrations/1791823000_squads_collection.js` (création collection squads)

## Prochaine action
Attendre le téléphone allumé OU l'analyse Discord pour conclure
