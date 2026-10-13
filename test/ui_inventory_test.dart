// Inventaire des interfaces : capture CHAQUE ecran via le moteur Flutter.
//
// Pourquoi un test plutot que des taps ADB : piloter l'app au doigt sur le
// telephone est fragile (un tap qui rate ouvre une autre app, l'ecran se
// verrouille, l'animation decale la cible). Ici on monte l'app complete, on
// tape les VRAIS boutons par leur libelle, et on ecrit un PNG par ecran.
// Le rendu est celui du moteur Flutter — donc fidele a ce que voit
// l'utilisateur, sans dependre d'un doigt ni d'un ecran allume.
//
// Usage : flutter test test/ui_inventory_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:street_medics_app/body_map_view.dart';
import 'package:street_medics_app/config.dart';
import 'package:street_medics_app/main.dart';

const String kOut =
    '/root/projects/street-medics-app/docs/ui-inventory/screenshots';

/// Canaux natifs utilises par l'app : absents en test, ils font echouer le
/// test avec un MissingPluginException des le demarrage. On les neutralise.
const List<String> _nativeChannels = [
  'plugins.flutter.io/path_provider',
  'flutter_foreground_task/methods',
  'flutter.baseflow.com/geolocator',
  'flutter.baseflow.com/permissions/methods',
  'com.peerwaya.flutter.mobile.number',
  'dev.fluttercommunity.plus/package_info',
  'dexterous.com/flutter/local_notifications',
];

void stubNativeChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _nativeChannels) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async {
        // Reponses plausibles plutot que null : certaines API attendent un
        // type precis (int, Map) et planteraient sur null.
        switch (call.method) {
          case 'getApplicationCacheDirectory':
          case 'getTemporaryDirectory':
          case 'getApplicationDocumentsDirectory':
            return Directory.systemTemp.path;
          case 'checkNotificationPermission':
          case 'checkExactAlarmPermission':
            return 1; // accorde
          case 'getAll':
            return <String, dynamic>{
              'appName': 'Street Medics',
              'packageName': 'fr.streetmedics.street_medics_app',
              'version': '1.4.0',
              'buildNumber': '17',
            };
          case 'getMobileNumber':
            return null;
          default:
            return null;
        }
      },
    );
  }
}

/// Monte l'app complete, avec l'etat voulu (en service ou non).
Future<void> mountApp(WidgetTester tester,
    {bool onDuty = false, Map<String, Object> extra = const {}}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  SharedPreferences.setMockInitialValues({
    // `device_id` est OBLIGATOIRE : sans lui, AppConfig.load() appelle un
    // canal natif qui ne repond jamais en test et fige le test.
    'device_id': 'dev-test',
    'flutter.on_duty': onDuty,
    // L'app est FRANCAISE : on force la locale, sinon le test tourne en
    // anglais et les libelles recherches ne correspondent pas.
    'app_lang': 'fr',
    ...extra,
  });
  await AppConfig.load();
  await tester.pumpWidget(const RepaintBoundary(
    key: ValueKey('capture'),
    child: StreetMedicsApp(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // La popup « Autorisations nécessaires » s'ouvre au demarrage et masque
  // tout : on la capture a part, puis on la ferme.
  if (!extra.containsKey('keepPerms')) {
    final later = find.text('Plus tard');
    if (later.evaluate().isNotEmpty) {
      await tester.tap(later.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
}

/// Capture l'ecran courant dans un PNG.
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

/// Ouvre un onglet par son index.
Future<void> tab(WidgetTester tester, int i) async {
  final nav = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
  nav.onTap!(i);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Fait defiler l'ecran vers le bas (les onglets debordent du cadre).
///
/// Les onglets n'utilisent pas tous le meme conteneur (SOS = Column dans un
/// SingleChildScrollView, Reglages = ListView) : on cherche celui qui est la.
Future<void> scrollDown(WidgetTester tester, [double dy = -400]) async {
  final target = find.byType(ListView).evaluate().isNotEmpty
      ? find.byType(ListView).first
      : find.byType(SingleChildScrollView).first;
  await tester.drag(target, Offset(0, dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tape le premier widget dont le texte correspond, en le rendant visible.
Future<bool> tapText(WidgetTester tester, String label,
    {bool scroll = true}) async {
  final f = find.text(label);
  if (f.evaluate().isEmpty) return false;
  if (scroll) {
    await tester.ensureVisible(f.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return true;
}

/// Charge une VRAIE police : sans cela le harnais de test dessine chaque
/// glyphe en bloc noir, et les captures sont illisibles.
Future<void> loadRealFonts() async {
  final loader = FontLoader('Roboto');
  for (final name in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf',
      'Roboto-Medium.ttf']) {
    final f = File('/root/tools/flutter/bin/cache/artifacts/'
        'material_fonts/$name');
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

void main() {
  setUp(stubNativeChannels);
  setUpAll(loadRealFonts);

  testWidgets('00 popup Autorisations necessaires', (tester) async {
    await mountApp(tester, extra: const {'keepPerms': 1});
    await shoot(tester, '00_popup_autorisations');
  });

  testWidgets('01 onglet SOS (haut)', (tester) async {
    await mountApp(tester);
    await shoot(tester, '01_onglet_sos_haut');
  });

  testWidgets('02 onglet SOS (bas)', (tester) async {
    await mountApp(tester);
    await scrollDown(tester, -300);
    await shoot(tester, '02_onglet_sos_bas');
  });

  testWidgets('03 feuille Appeler les urgences', (tester) async {
    await mountApp(tester);
    final ok = await tapText(tester, 'Appeler les urgences');
    expect(ok, isTrue, reason: '"Appeler les urgences" introuvable');
    await tester.pumpAndSettle();
    await shoot(tester, '03_appeler_urgences');
  });

  testWidgets('04 onglet Carte verrouille (hors service)', (tester) async {
    await mountApp(tester, onDuty: false);
    await tab(tester, 1);
    await shoot(tester, '04_onglet_carte_verrouille');
  });

  testWidgets('05 onglet Carte medic en service', (tester) async {
    await mountApp(tester, onDuty: true);
    await tab(tester, 1);
    await shoot(tester, '05_onglet_carte_medic');
  });

  testWidgets('06 dialogue Engagement du street medic', (tester) async {
    // Le bouton « Devenir street medic » est dans l'ONGLET SOS (pas la Carte) :
    // il faut faire defiler pour l'atteindre.
    await mountApp(tester, onDuty: false);
    final ok = await tapText(tester, 'Devenir street medic');
    expect(ok, isTrue, reason: '"Devenir street medic" introuvable');
    await tester.pumpAndSettle();
    await shoot(tester, '06_engagement_medic');
  });

  testWidgets('07 onglet Reglages (haut)', (tester) async {
    await mountApp(tester);
    await tab(tester, 3);
    await shoot(tester, '07_onglet_reglages_haut');
  });

  testWidgets('08 onglet Reglages (bas)', (tester) async {
    await mountApp(tester);
    await tab(tester, 3);
    await scrollDown(tester, -400);
    await shoot(tester, '08_onglet_reglages_bas');
  });

  testWidgets('16 onglet Bonnes pratiques (coming soon)', (tester) async {
    await mountApp(tester);
    await tab(tester, 2);
    await shoot(tester, '16_onglet_bonnes_pratiques');
  });

  testWidgets('09 selecteur de blessures (face)', (tester) async {
    await mountApp(tester);
    final ok = await tapText(tester, 'Blessures');
    expect(ok, isTrue, reason: 'la carte "Blessures" est introuvable');
    await tester.pumpAndSettle();
    await shoot(tester, '09_selecteur_blessures_face');
  });

  testWidgets('10 selecteur de blessures (dos)', (tester) async {
    await mountApp(tester);
    await tapText(tester, 'Blessures');
    await tester.pumpAndSettle();
    final ok = await tapText(tester, 'Dos', scroll: false);
    expect(ok, isTrue, reason: 'le segment "Dos" est introuvable');
    await tester.pumpAndSettle();
    await shoot(tester, '10_selecteur_blessures_dos');
  });

  testWidgets('12 liste Mes SOS en cours', (tester) async {
    // On pre-remplit la liste locale de signalements : l'app ouvre alors le
    // compteur, sans dependre du reseau (qui renvoie 400 en test).
    await mountApp(tester, extra: const {
      'my_reports': '["id-a","id-b","id-c"]',
    });
    final ok = await tapText(tester, 'Mes SOS en cours',
        scroll: false);
    if (!ok) {
      // Le compteur s'affiche sous le bouton SOS : on le cherche par motif.
      final f = find.textContaining('SOS en cours');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
    }
    await tester.pumpAndSettle();
    await shoot(tester, '12_liste_mes_sos');
  });

  testWidgets('11 selecteur avec une blessure marquee', (tester) async {
    await mountApp(tester);
    await tapText(tester, 'Blessures');
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(BodyMapView));
    // Tape sur le buste (centre haut de la silhouette).
    await tester.tapAt(Offset(box.center.dx, box.top + box.height * 0.30));
    // Le double-tap retarde le tap simple : on laisse le delai s'ecouler.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    await shoot(tester, '11_selecteur_blessure_marquee');
  });
}
