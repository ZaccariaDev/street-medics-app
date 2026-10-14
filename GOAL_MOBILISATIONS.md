# GOAL MOBILISATIONS — Intégrer les lieux de mobilisation à risque

## Objectif
Afficher les lieux de mobilisation (manifs, ronds-points, raffineries, dépôts) issus de l'API 17octobregiletjaune.net sur la carte de l'app Street Medics.

## État
- [x] J1 — Récupération des données (MobilisationService)
- [x] J2 — Affichage sur la carte (markers, icônes)
- [x] J3 — Contrôle utilisateur (bouton toggle)

## Progression

### J1 — Récupération des données
- [x] P1 : Créer MobilisationService (fetch /api/lieux, /api/actions)
- [x] P2 : Parser les données en objets Dart
- [x] P3 : Gérer les erreurs (timeout, 404, format invalide)

### J2 — Affichage sur la carte
- [x] P4 : Ajouter les markers (couche distincte, icône orange)
- [x] P5 : Ajouter la légende (dans le détail du marker)

### J3 — Contrôle utilisateur
- [x] P6 : Bouton toggle on/off
- [x] P7 : Rafraîchissement à l'ouverture

## Blocages
- Aucun

## Prochaine action
- Ajouter un test unitaire pour le parsing de l'API
- Vérifier l'affichage sur le téléphone
