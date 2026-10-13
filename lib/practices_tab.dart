import 'package:flutter/material.dart';

/// Onglet « Bonnes pratiques » — grisé, en attente du contenu.
///
/// L'utilisateur a demandé un 4ème onglet avant les Réglages. Pour l'instant
/// il est désactivé (grisé) avec une banderole « Coming Soon » : pas de
/// contenu à afficher, mais l'emplacement est réservé.
class PracticesTab extends StatelessWidget {
  const PracticesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book,
              size: 64,
              color: scheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Bonnes pratiques',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 24),
            // Banderole « Coming Soon »
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hourglass_empty,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Coming Soon',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Conseils et gestes de premiers secours',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
