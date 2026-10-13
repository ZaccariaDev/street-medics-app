// Capture de l'ecran de confirmation apres envoi d'un SOS, avec blessures.
//
// Cet ecran est un AlertDialog ouvert par l'onglet SOS. On reproduit son
// contenu a l'identique (memes widgets, memes libelles) pour le capturer,
// car il n'apparait qu'apres un envoi reseau reussi (impossible en test).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:street_medics_app/body_map.dart';
import 'package:street_medics_app/first_aid.dart';
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

void main() {
  setUpAll(loadRealFonts);

  testWidgets('ecran de confirmation apres envoi du SOS', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final t = await AppLocalizations.delegate.load(const Locale('fr'));

    // Deux blessures, pour montrer deux blocs de premiers gestes.
    const injuries = [
      Injury(zoneId: 'head', typeId: 'wound'),
      Injury(zoneId: 'leg_l', typeId: 'fracture'),
    ];

    List<String> steps(String raw) => raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String aidFor(String key) {
      switch (key) {
        case 'aidWound':
          return t.aidWound;
        case 'aidFracture':
          return t.aidFracture;
        case 'aidBurn':
          return t.aidBurn;
        default:
          return t.aidOther;
      }
    }

    String zoneLabel(String id) {
      switch (id) {
        case 'head':
          return t.zoneHead;
        case 'leg_l':
          return t.zoneLegs;
        case 'chest':
          return t.zoneChest;
        default:
          return id;
      }
    }

    String typeLabel(String id) {
      switch (id) {
        case 'wound':
          return t.injuryWound;
        case 'fracture':
          return t.injuryFracture;
        case 'burn':
          return t.injuryBurn;
        default:
          return t.injuryOther;
      }
    }

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('capture'),
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black26,
          body: Center(
            child: AlertDialog(
              icon: const Icon(Icons.check_circle,
                  color: Colors.green, size: 40),
              title: Text(t.sosSentTitle, textAlign: TextAlign.center),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.sosSentBody),
                    const SizedBox(height: 16),
                    Text(t.whatToDo,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final inj in injuries) ...[
                      Row(children: [
                        Icon(
                          firstAidFor(inj.typeId).urgent
                              ? Icons.priority_high
                              : Icons.info_outline,
                          size: 18,
                          color: firstAidFor(inj.typeId).urgent
                              ? Colors.red
                              : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${zoneLabel(inj.zoneId)} · '
                            '${typeLabel(inj.typeId)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      for (final s in steps(aidFor(firstAidFor(inj.typeId).stepsKey)))
                        Padding(
                          padding: const EdgeInsets.only(left: 24, bottom: 2),
                          child: Text('• $s'),
                        ),
                      const SizedBox(height: 10),
                    ],
                    if (kFirstAidIsStub)
                      Text(t.aidStubNote,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              actions: [
                FilledButton(onPressed: () {}, child: Text(t.close)),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await shoot(tester, '15_confirmation_sos_envoye');
  });
}
