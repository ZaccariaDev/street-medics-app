import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/app_localizations.dart';
import 'updater.dart';

/// Popup de mise à jour, affichée au démarrage si une version plus récente
/// est publiée. Bloquante uniquement si la mise à jour est marquée
/// obligatoire (correctif critique).
class UpdateDialog {
  static Future<void> maybeShow(BuildContext context) async {
    final latest = await Updater.check();
    if (latest == null) return;
    if (!context.mounted) return;

    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: !latest.mandatory,
      builder: (ctx) => PopScope(
        canPop: !latest.mandatory,
        child: AlertDialog(
          icon: const Icon(Icons.system_update, color: Colors.blue),
          title: Text(t.updateTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(latest.mandatory ? t.updateMandatory : t.updateBody),
              const SizedBox(height: 10),
              Text('${t.version} ${latest.versionName}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              if (latest.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(latest.notes),
              ],
            ],
          ),
          actions: [
            if (!latest.mandatory)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t.updateLater),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.download),
              label: Text(t.updateNow),
              onPressed: () async {
                // Pas de lien configuré : on ouvre la fiche Play Store.
                final url = latest.url.isNotEmpty
                    ? latest.url
                    : 'https://play.google.com/store/apps/details'
                        '?id=fr.streetmedics.street_medics_app';
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (ctx.mounted && !latest.mandatory) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}
