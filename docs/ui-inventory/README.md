# Inventaire des interfaces — Street Medics FR

Cartographie complète de l'application : **chaque écran capturé**, et pour chacun
**quel élément mène où**.

## Contenu

| Fichier | Rôle |
|---|---|
| `interfaces.json` | La cartographie complète, lisible par machine |
| `screenshots/` | 14 captures, une par écran (ou par état d'écran) |
| `README.md` | Ce fichier |

## Comment les captures ont été produites

Par le **moteur Flutter lui-même**, via `flutter test test/ui_inventory_test.dart`.

Pourquoi pas des captures du téléphone : piloter l'app au doigt sur l'appareil
est fragile — un tap qui rate ouvre une autre application, l'écran se verrouille,
l'animation décale la cible. Ici on monte l'app complète, on tape les **vrais
boutons par leur libellé**, et on écrit un PNG par écran. Le rendu est celui du
moteur Flutter, donc fidèle à ce que voit l'utilisateur.

Pour régénérer les captures après une modification d'interface :

```bash
cd /root/projects/street-medics-app
export PATH="$PATH:/root/tools/flutter/bin"
flutter test test/ui_inventory_test.dart
```

## Les écrans

| # | Écran | Fichier |
|---|---|---|
| 00 | Popup « Autorisations nécessaires » | `00_popup_autorisations.png` |
| 01 | Onglet SOS (haut) | `01_onglet_sos_haut.png` |
| 02 | Onglet SOS (bas) | `02_onglet_sos_bas.png` |
| 03 | Feuille « Appeler les urgences » | `03_appeler_urgences.png` |
| 04 | Onglet Carte — verrouillé (hors service) | `04_onglet_carte_verrouille.png` |
| 05 | Onglet Carte — medic en service | `05_onglet_carte_medic.png` |
| 06 | Dialogue « Engagement du street medic » | `06_engagement_medic.png` |
| 07 | Onglet Réglages (haut) | `07_onglet_reglages_haut.png` |
| 08 | Onglet Réglages (bas) | `08_onglet_reglages_bas.png` |
| 09 | Sélecteur de blessures — face | `09_selecteur_blessures_face.png` |
| 10 | Sélecteur de blessures — dos | `10_selecteur_blessures_dos.png` |
| 11 | Sélecteur — une zone marquée | `11_selecteur_blessure_marquee.png` |
| 12 | Feuille « Mes SOS en cours » | `12_liste_mes_sos.png` |
| 13 | Feuille détail d'un SOS (médic) | `13_detail_sos.png` |
| 14 | Feuille détail d'un medic | `14_detail_medic.png` |

## Limites (à lire avant de s'appuyer dessus)

- **La carte apparaît grise** : les tuiles OpenStreetMap ne se téléchargent pas
  dans l'environnement de test. La position des boutons est exacte, le fond
  cartographique ne l'est pas.
- **Deux feuilles sont reproduites depuis le code** (captures 13 et 14) : le
  détail d'un SOS et le détail d'un medic s'ouvrent normalement depuis un blip
  de la carte, donc inatteignables sans tuiles. Le contenu est identique (mêmes
  widgets, mêmes libellés), mais ce ne sont pas des captures d'un parcours réel.
- **Les messages temporaires** (confirmation d'envoi, erreur réseau) ne sont pas
  capturés : ils durent quelques secondes. Leur texte est dans
  `lib/l10n/app_fr.arb`.
- **La carte et les dialogues ne reflètent pas les données réelles** : les
  captures sont prises hors ligne, avec des listes vides ou pré-remplies.
