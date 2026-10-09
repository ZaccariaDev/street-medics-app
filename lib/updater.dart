import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';

/// Dernière version publiée, telle que décrite par la collection
/// `app_release` du serveur PocketBase.
class ReleaseInfo {
  const ReleaseInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.mandatory,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final String url;
  final bool mandatory;
  final String notes;

  static ReleaseInfo fromJson(Map<String, dynamic> j) => ReleaseInfo(
        versionCode: (j['versionCode'] as num?)?.toInt() ?? 0,
        versionName: j['versionName']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        mandatory: j['mandatory'] == true,
        notes: j['notes']?.toString() ?? '',
      );
}

/// Vérifie si une mise à jour est disponible.
///
/// Compare le `versionCode` installé (lu dans le manifeste Android via
/// `package_info_plus`) au `versionCode` publié dans la collection
/// `app_release`. Le serveur ne peut pas décider à notre place : la
/// comparaison est faite ici.
class Updater {
  /// Renvoie la nouvelle version si elle est plus récente, sinon null.
  static Future<ReleaseInfo?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;

      final base = AppConfig.serverUrl;
      if (base.isEmpty) return null;

      final res = await http
          .get(Uri.parse('$base/api/collections/app_release/records'
              '?perPage=1&sort=-versionCode'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final items = (jsonDecode(res.body)['items'] as List?) ?? [];
      if (items.isEmpty) return null;

      final latest = ReleaseInfo.fromJson(items.first as Map<String, dynamic>);
      if (latest.versionCode > installed) return latest;
      return null;
    } catch (_) {
      // Pas de réseau, serveur injoignable… : on ne bloque jamais l'app.
      return null;
    }
  }
}
