/// Premiers gestes à faire pour une blessure.
///
/// **Contenu provisoire (stub).** L'association des street medics doit envoyer
/// la liste réelle des conduites à tenir. En attendant, on affiche une consigne
/// générique et honnête plutôt qu'un contenu inventé : en situation d'urgence,
/// une indication fausse est plus dangereuse que pas d'indication du tout.
///
/// Pour remplacer : il suffit de compléter `kFirstAid`. Rien d'autre à toucher.
library;

/// Conduite à tenir pour un type de blessure.
class FirstAid {
  const FirstAid({
    required this.typeId,
    required this.stepsKey,
    this.urgent = false,
  });

  /// Identifiant du type de blessure (`wound`, `fracture`, `burn`, `other`).
  final String typeId;

  /// Clé de traduction de la liste d'étapes (voir `app_*.arb`).
  final String stepsKey;

  /// Vrai si la blessure impose d'appeler les secours sans attendre.
  final bool urgent;
}

/// Liste MINIMALE, en attendant celle du street medic.
///
/// Volontairement générique : les étapes rappellent les réflexes de base
/// (protéger, alerter, ne pas aggraver) sans se substituer à un avis médical.
const List<FirstAid> kFirstAid = [
  FirstAid(typeId: 'wound', stepsKey: 'aidWound', urgent: true),
  FirstAid(typeId: 'fracture', stepsKey: 'aidFracture'),
  FirstAid(typeId: 'burn', stepsKey: 'aidBurn', urgent: true),
  FirstAid(typeId: 'other', stepsKey: 'aidOther'),
];

/// Conduite à tenir pour un type donné (repli sur « autre »).
FirstAid firstAidFor(String typeId) => kFirstAid.firstWhere(
      (a) => a.typeId == typeId,
      orElse: () => kFirstAid.last,
    );

/// Marqueur : ce contenu est provisoire.
const bool kFirstAidIsStub = true;
