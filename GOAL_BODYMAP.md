# GOAL IDÉAL — Sélecteur de blessures sur silhouette (avec zoom)

## Résultat final attendu

Chaque SOS peut porter une **description visuelle de la victime** : une
silhouette asexuée semi-transparente, en deux vues (face / dos). On touche une
partie du corps, **la vue zoome dessus** pour viser précisément, on choisit le
type de blessure, et le marquage apparaît dans la liste des SOS — ce qui permet
de distinguer plusieurs signalements d'un coup d'œil.

## Contexte vérifié

- Aucune lib graphique dans le projet (`flutter_svg` absent) → silhouette
  dessinée en **`CustomPaint`** : chaque zone est nativement cliquable, sans
  dépendance nouvelle.
- `reports` possède déjà un champ `position` de type **json** → les blessures
  suivront le même modèle (pas de nouveau type de champ).
- `main.dart` fait **1767 lignes** → le sélecteur ira dans un **fichier
  séparé** (`lib/body_map.dart`), pas dans `main.dart`.
- La popup « Mes SOS en cours » existe (`_showMySosSheet`, main.dart:573) →
  c'est là que le marquage doit s'afficher.
- Les migrations serveur utilisent `collection.fields.addAt(n, new Field({...}))`.
- 17 tests passent actuellement ; `flutter analyze` est propre.

## Décisions actées (réponses de l'utilisateur)

| Point | Décision |
|---|---|
| Dos | **Deux vues**, bouton pour basculer face ↔ dos |
| Emplacement | **Silhouette réduite** dans l'onglet SOS, agrandie en la touchant |
| Types de blessure | **Minimal en attendant** la liste du street medic |
| Zoom | **Toucher une partie du corps zoome dessus** |

## Le parcours cible

```
[Onglet SOS]
  silhouette réduite ──tap──> plein écran
                                   │
                              tap "bras" ──> ZOOM animé sur le bras
                                                  │
                                          sous-zones fines visibles
                                          (épaule, bras, coude,
                                           avant-bras, main)
                                                  │
                                          tap "avant-bras" + type
                                                  │
                                          marquage enregistré
                                                  │
                                          retour auto à la vue d'ensemble
```

Tant qu'on ne touche pas la silhouette, **le SOS reste à 1 appui**.

## Contraintes et invariants

- Le SOS simple **ne doit pas gagner un seul clic** (exigence déjà exprimée).
- Pas de nouvelle dépendance graphique si `CustomPaint` suffit.
- Silhouette **asexuée, indéfinissable** — aucun trait genré.
- Traductions dans les 23 langues, comme le reste de l'app.
- `flutter analyze` propre + les 17 tests existants restent verts.

## Architecture technique du zoom

Le point délicat est le **hit-testing sous transformation**. Approche retenue :

- La silhouette est définie dans un **espace logique normalisé** (0..1), stable.
- Le zoom est un `Matrix4` appliqué au rendu (`Transform`), animé par un
  `AnimationController` centré sur le **centroïde de la zone touchée**.
- Les taps sont convertis de l'espace écran vers l'espace logique via
  l'**inverse de la matrice** — ainsi la détection de zone reste exacte à
  n'importe quel niveau de zoom.
- Sortie du zoom : bouton retour, tap hors du corps, ou fin de saisie.

Cette séparation (logique stable / rendu transformé) évite le piège classique
du hit-testing qui se décale dès que l'échelle change.

## Jalons

### J1 — Silhouette dessinée, deux vues, zones cliquables
Dessin `CustomPaint` asexué semi-transparent. Vue de face : tête, épaule G/D,
buste, bras G/D, avant-bras G/D, main G/D, ventre/bassin, cuisse G/D,
jambe G/D, pied G/D. Vue de dos : nuque, épaules, dos, reins, fesses, arrière
des cuisses/jambes.
**Preuve** : capture des deux vues, test unitaire de détection de zone.

### J2 — Zoom animé sur la zone touchée
Toucher une zone zoome dessus (animation fluide, centrée sur la zone). Les
sous-zones fines deviennent visibles et cliquables. Retour à la vue d'ensemble.
**Preuve** : captures avant/pendant/après le zoom ; test unitaire vérifiant que
le hit-testing reste exact après transformation.

### J3 — Types de blessure (liste minimale)
Rangée de pastilles : **plaie, fracture, brûlure, autre**. La liste vit dans une
**constante unique** (`kBruiseTypes`) pour être remplacée en une ligne quand le
street medic enverra la sienne.
**Preuve** : capture d'une zone marquée avec son type.

### J4 — Intégration au formulaire SOS
Silhouette réduite dans l'onglet SOS, agrandissable. Le marquage est attaché au
SOS envoyé. **Sans interaction avec la silhouette, le parcours reste identique.**
**Preuve** : SOS sans blessure (1 appui) et SOS avec blessures, les deux
enregistrés correctement.

### J5 — Stockage serveur
Migration ajoutant un champ `injuries` (json) à `reports` :
`{ view: "front"|"back", zones: [{ zone, type }] }`. Rétrocompatible : les SOS
existants ont un champ vide.
**Preuve** : migration déployée, SOS avec blessures relu via l'API.

### J6 — Affichage dans la liste des SOS (but final)
Dans la popup « Mes SOS en cours » et au détail d'un blip : résumé visuel des
blessures (mini-silhouette ou pastilles). C'est ce qui permet de différencier
plusieurs SOS.
**Preuve** : capture de la popup avec 3 SOS aux blessures distinctes.

### J7 — Validation terrain
Sur le téléphone : 3 SOS avec 3 marquages différents, vérifiés dans la liste.
**Preuve** : captures + vérification serveur.

## Points encore ouverts

1. **Liste de blessures du street medic** — attendue. En attendant : plaie,
   fracture, brûlure, autre, isolées dans une constante.
2. **Granularité des zones** : 19 zones proposées. Le zoom permet d'affiner
   sans surcharger la vue d'ensemble — à calibrer au J2.

## Boucle de travail et vérification

Une passe = un jalon. À chaque passe : relire l'état, implémenter, vérifier par
une preuve réelle (capture d'écran, test, vérification serveur), consigner,
continuer. Contrôle de non-régression à chaque jalon.

**Règle de preuve** : ne jamais déclarer une capacité opérationnelle sur la
seule base de sa présence dans le code ou d'un test isolé. Indiquer ce qui est
implémenté, testé localement, testé en intégration, ou non vérifié.

## Conditions de fin

- Les 7 jalons ont chacun une preuve observée.
- Le parcours SOS simple n'a pas gagné de clic (vérifié sur téléphone).
- `flutter analyze` propre, tests verts.
- APK installé et parcours complet validé sur le téléphone.
