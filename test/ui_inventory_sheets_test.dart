// Captures des deux feuilles atteignables seulement depuis un blip de carte.
//
// Ces feuilles s'ouvrent depuis un marqueur de la carte. Les tuiles OSM ne se
// telechargent pas dans l'environnement de test, donc on ne peut pas les
// atteindre en tapant la carte. On reproduit donc leur CONTENU a l'identique
// (memes widgets, memes libelles) pour les capturer.
//
// Ces captures sont declarees comme telles dans interfaces.json : elles
// refletent le code, pas un parcours utilisateur reel.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/l10n/app_localizations.dart';

const String kOut =
    '/root/projects/street-medics-app/docs/ui-inventory/screenshots';

Future<void> loadRealFonts() async {
  final loader = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Medium.ttf'
  ]) {
    final f =
        File('/root/tools/flutter/bin/cache/artifacts/material_fonts/$name');
    if (f.existsSync()) {
      loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    }
  }
  await loader.load();
  final icons = File('/root/tools/flutter/bin/cache/artifacts/'
      'material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final il = FontLoader('MaterialIcons')
      ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()));
    await il.load();
  }
}

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$kOut/$name.png');
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('CAPTURE $name.png (${f.lengthSync()} octets)');
  });
}

Widget host(Widget child) => RepaintBoundary(
      key: const ValueKey('capture'),
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Align(alignment: Alignment.bottomCenter,
            child: child)),
      ),
    );

void main() {
  setUpAll(loadRealFonts);

  testWidgets('feuille detail d\'un SOS', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final t = await AppLocalizations.delegate.load(const Locale('fr'));
    await tester.pumpWidget(host(Builder(builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('SOS',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          const Text('Femme à terre, saignement à la jambe',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          const Text('48.85661, 2.35222',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(t.statusOpen,
              style: const TextStyle(
                  color: Colors.orange, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.blue),
              icon: const Icon(Icons.directions),
              label: Text(t.shortestRoute),
              onPressed: () {},
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(Icons.phone),
              label: Text(t.callVictim),
              onPressed: () {},
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.check),
              label: Text(t.takeCharge), onPressed: () {})),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.done_all),
              label: Text(t.resolvedBtn), onPressed: () {})),
          ]),
        ],
      ),
    ))));
    await tester.pump();
    await shoot(tester, '13_detail_sos');
  });

  testWidgets('feuille detail d\'un medic', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.medical_services, color: Colors.green),
            SizedBox(width: 8),
            Text('Street medic',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          SizedBox(height: 12),
          Text('Camille', style: TextStyle(fontSize: 16)),
          SizedBox(height: 8),
          Text('48.85700, 2.35100', style: TextStyle(color: Colors.grey)),
        ],
      ),
    )));
    await tester.pump();
    await shoot(tester, '14_detail_medic');
  });
}
