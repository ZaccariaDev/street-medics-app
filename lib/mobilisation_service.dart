import 'dart:convert';
import 'dart:io';

/// Service de récupération des lieux de mobilisation depuis l'API externe.
///
/// Source : https://17octobregiletjaune.net/api/lieux
/// Données statiques (mise à jour 14-15 sept 2026)
/// API en lecture seule, pas d'authentification requise.
class MobilisationService {
  static const String _baseUrl = 'https://17octobregiletjaune.net';
  static const Duration _timeout = Duration(seconds: 10);

  /// Récupère les lieux de mobilisation.
  ///
  /// Retourne une liste de [Mobilisation] ou vide en cas d'erreur.
  static Future<List<Mobilisation>> fetchLieux() async {
    try {
      final client = HttpClient()..connectionTimeout = _timeout;
      final req = await client.getUrl(Uri.parse('$_baseUrl/api/lieux'));
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        client.close();
        return [];
      }
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      client.close();
      return _parseLieux(body);
    } catch (_) {
      // Timeout, erreur réseau, format invalide : on retourne vide
      // pour ne pas bloquer l'affichage de la carte.
      return [];
    }
  }

  /// Parse la réponse JSON de l'API.
  ///
  /// Format attendu : `{"lieux": [[id, type, lat, lng, nom, adresse, ville, cp, dept, heure, ...], ...]}`
  static List<Mobilisation> _parseLieux(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final lieux = data['lieux'] as List<dynamic>? ?? [];
      return lieux.map((e) {
        final list = e as List<dynamic>;
        return Mobilisation(
          id: list[0] as int,
          type: list[1] as String? ?? '',
          lat: (list[2] as num).toDouble(),
          lng: (list[3] as num).toDouble(),
          nom: list[4] as String? ?? '',
          adresse: list[5] as String? ?? '',
          ville: list[6] as String? ?? '',
          codePostal: list[7] as String? ?? '',
          departement: list[8] as String? ?? '',
          heure: list[9] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

/// Un lieu de mobilisation (manif, rond-point, etc.).
class Mobilisation {
  const Mobilisation({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.nom,
    required this.adresse,
    required this.ville,
    required this.codePostal,
    required this.departement,
    required this.heure,
  });

  final int id;
  final String type;
  final double lat;
  final double lng;
  final String nom;
  final String adresse;
  final String ville;
  final String codePostal;
  final String departement;
  final String heure;

  /// Libellé affiché sur la carte.
  String get label {
    final parts = <String>[];
    if (nom.isNotEmpty) parts.add(nom);
    if (ville.isNotEmpty) parts.add(ville);
    if (heure.isNotEmpty) parts.add(heure);
    return parts.join(' · ');
  }

  /// Icône selon le type de mobilisation.
  String get iconEmoji {
    switch (type) {
      case 'manif':
        return '✊';
      case 'rassemblement':
        return '📢';
      case 'blocage':
        return '🚧';
      default:
        return '📍';
    }
  }
}
