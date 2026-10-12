# Assets anatomiques — provenance et licence

## Fichiers

| Fichier | Source | Licence |
|---|---|---|
| `body_front.svg` | [Human silhouette gender neutral front.svg](https://commons.wikimedia.org/wiki/File:Human_silhouette_gender_neutral_front.svg) | **CC0** |
| `body_back.svg` | [Human silhouette gender neutral back.svg](https://commons.wikimedia.org/wiki/File:Human_silhouette_gender_neutral_back.svg) | **CC0** |

**Auteur** : Sebastian Wallroth (Wikimedia Commons)
**Licence** : Creative Commons Zero — dédié au domaine public.
Aucune attribution n'est légalement requise ; elle est conservée ici par
courtoisie et pour la traçabilité.

## Pourquoi ces fichiers

Première version : silhouette dessinée en polygones dans `body_map.dart`.
Résultat rejeté par l'utilisateur — aspect schématique et anguleux, pas
crédible comme représentation d'un corps humain.

Ces SVG sont de vraies silhouettes humaines, asexuées, avec des proportions
correctes et une distinction nette face/dos (sillon fessier, talons visibles
de dos). Le corps est un **contour plein** (`<path>` unique), ce qui permet de
le teinter et de le rendre semi-transparent à la volée.

## Comment ils sont utilisés

- Rendu par `flutter_svg` (à ajouter), teinté et semi-transparent.
- Les **zones cliquables** restent des polygones invisibles définis dans
  `body_map.dart`, superposés au SVG. Cette séparation permet d'avoir une
  belle image *et* un hit-testing exact, sans dépendre du découpage du SVG.
- Les **blessures** sont dessinées par-dessus, en couleur pleine — comme la
  lésion violette de l'illustration de référence.

## Contrainte de proportions

Les deux SVG n'ont pas exactement la même hauteur (1204 vs 1190 px) : les
zones cliquables doivent être définies **par vue**, pas partagées, sinon elles
se décalent sur l'une des deux.
