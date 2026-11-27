// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_mein_telefon/app.dart';
import 'package:rosenweg_mein_telefon/attrappe.dart';
import 'package:rosenweg_mein_telefon/daten.dart';
import 'package:rosenweg_mein_telefon/seiten/haupt.dart';

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  Future<Attrappe> zeigen(
    WidgetTester t,
    Size groesse, {
    List<String> gruppen = const ['stweg3-eigentuemer'],
    bool mitNummer = true,
    bool darfGeteilt = true,
    bool geteilt = false,
    void Function(Attrappe a)? vorher,
  }) async {
    t.view.physicalSize = groesse;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final a = Attrappe(gruppen: gruppen, mitNummer: mitNummer, darfGeteilt: darfGeteilt);
    vorher?.call(a);
    final s = RosenwegSitzung(appAngaben, transport: a);
    await s.starten();
    s.geteiltesTelefon = geteilt;
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => Haupt(sitzung: s, anlage: a)));
    await t.pumpAndSettle();
    return a;
  }

  /// Timer der Seiten (QR-Uhr, Nachladen, Klingeln) vor Testende abbauen.
  Future<void> ende(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 61));
  }

  Future<void> zu(WidgetTester t, String bereich) async {
    await t.tap(find.text(bereich).last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  ButtonStyleButton speichern(WidgetTester t) => t.widget<ButtonStyleButton>(find.byKey(const Key('speichern')));

  testWidgets('Handy: Navigation unten, Nummer und Erreichbarkeit aus der Anlage', (t) async {
    final a = await zeigen(t, const Size(412, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('300107'), findsOneWidget);
    expect(find.text('Erika Muster · Haus 9, Wohnung 3.2'), findsOneWidget);
    // Stand der Anlage: weiterleiten nach 20 s, Voicemail an; ungeaendert = Speichern aus
    expect(find.byKey(const Key('ziel')), findsOneWidget);
    expect(find.byKey(const Key('sekunden')), findsOneWidget);
    expect(speichern(t).onPressed, isNull);
    expect(find.text('Alle Handys'), findsNothing);
    expect(a.anfragen.any((r) => r.pfad == '/api/telefon/ich'), isTrue);
    await ende(t);
  });

  testWidgets('Erreichbarkeit: Ziel fehlt → Hinweis am Feld; dann speichern', (t) async {
    final a = await zeigen(t, const Size(412, 1600));
    await t.tap(find.text('Immer weiterleiten'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sekunden')), findsNothing, reason: 'Sekunden nur bei „wenn ich nicht abnehme“');
    await t.enterText(find.byKey(const Key('ziel')), '');
    await t.pumpAndSettle();
    await t.tap(find.text('Speichern'));
    await t.pumpAndSettle();
    expect(find.text('Bitte die Nummer angeben, an die weitergeleitet wird.'), findsOneWidget);
    expect(a.anfragen.where((r) => r.methode == 'PUT'), isEmpty);

    await t.enterText(find.byKey(const Key('ziel')), 'abc');
    await t.pumpAndSettle();
    await t.tap(find.text('Speichern'));
    await t.pumpAndSettle();
    expect(find.textContaining('Zielnummer ungültig'), findsOneWidget, reason: 'Fehler der Anlage am Feld');

    await t.enterText(find.byKey(const Key('ziel')), '079 000 00 01');
    await t.pumpAndSettle();
    await t.tap(find.text('Speichern'));
    await t.pumpAndSettle();
    final put = a.anfragen.lastWhere((r) => r.methode == 'PUT');
    expect(put.pfad, '/api/telefon/ich/erreichbarkeit');
    expect((put.koerper as Map)['weiterleitung'], 'immer');
    expect((put.koerper as Map)['ziel'], '079 000 00 01');
    expect(find.text('Gespeichert – gilt ab dem nächsten Anruf.'), findsOneWidget);
    // neu geladen: wieder ungeaendert
    expect(speichern(t).onPressed, isNull);
    await ende(t);
  });

  testWidgets('Ohne Rosenweg-Nummer: Hinweis statt Einstellungen', (t) async {
    await zeigen(t, const Size(412, 900), mitNummer: false);
    expect(find.text('Noch keine Rosenweg-Nummer'), findsOneWidget);
    expect(find.text('Erreichbarkeit'), findsNothing);
    await ende(t);
  });

  testWidgets('Geräte: geteiltes Telefon, Handys je einmal, alle Apps eines Handys abmelden', (t) async {
    final a = await zeigen(t, const Size(412, 1600));
    await zu(t, 'Geräte');
    await t.pumpAndSettle();
    expect(find.text('Telefon Waschküche Haus 9'), findsOneWidget);
    expect(find.text('Pixel 8'), findsOneWidget, reason: 'Telefon, Messenger und Salz auf einem Handy');
    expect(find.text('3 Apps'), findsOneWidget);
    expect(find.text('iPad Küche'), findsOneWidget);
    expect(find.text('Rosenweg Telefon'), findsOneWidget);
    expect(find.text('Rosenweg Messenger'), findsOneWidget);

    await t.tap(find.text('Alle Apps auf diesem Handy abmelden'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Abmelden'));
    await t.pumpAndSettle();
    final del = a.anfragen.where((r) => r.methode == 'DELETE').map((r) => r.pfad).toList();
    expect(del, containsAll(['/api/telefon/privat/4', '/api/messenger/zugaenge/12', '/api/apps/sitzungen/as_aaaaaaaaaaaaaaaa']));
    expect(find.text('Pixel 8'), findsNothing);
    expect(find.text('iPad Küche'), findsOneWidget);
    await ende(t);
  });

  testWidgets('Geräte: geteiltes Telefon klingeln lassen und abmelden', (t) async {
    final a = await zeigen(t, const Size(412, 1200));
    await zu(t, 'Geräte');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Klingeln lassen (Telefon verlegt?)'));
    await t.pump();
    expect(a.anfragen.last.pfad, '/api/telefon/2041/suchen');
    expect(find.textContaining('klingelt jetzt'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Gefunden um'), findsOneWidget);

    await t.tap(find.descendant(of: find.byKey(const Key('geteilt-2041')), matching: find.text('Abmelden')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Abmelden'));
    await t.pumpAndSettle();
    expect(a.anfragen.any((r) => r.methode == 'POST' && r.pfad == '/api/telefon/2041/abmelden'), isTrue);
    expect(find.text('Telefon Waschküche Haus 9'), findsNothing);
    await ende(t);
  });

  testWidgets('Anmelde-QR: geteiltes Telefon, dann App; meldet, wenn eine App ihn eingelöst hat', (t) async {
    final a = await zeigen(t, const Size(412, 900));
    await zu(t, 'Anmelde-QR');
    expect(find.byType(QrImageView), findsOneWidget);
    expect(a.anfragen.last.pfad, '/api/telefon/ausweis');
    expect(find.textContaining('gültig noch'), findsOneWidget);

    await t.tap(find.text('App auf eigenem Handy'));
    await t.pump();
    await t.pump();
    expect(a.anfragen.any((r) => r.pfad == '/api/apps/qr-ausweis'), isTrue);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Rosenweg Zutritt auf Pixel 8 ist angemeldet.'), findsOneWidget);
    expect(a.anfragen.where((r) => r.pfad == '/api/apps/qr-ausweis').length, 2, reason: 'gleich ein neuer Code');
    await ende(t);
  });

  testWidgets('Anmelde-QR: nicht für geteilte Telefone freigeschaltet → Hinweis, App-QR geht', (t) async {
    await zeigen(t, const Size(412, 900), darfGeteilt: false);
    await zu(t, 'Anmelde-QR');
    await t.pump();
    expect(find.textContaining('nicht freigeschaltet'), findsOneWidget);
    await t.tap(find.text('Anmelde-QR für eine App zeigen'));
    await t.pump();
    await t.pump();
    expect(find.byType(QrImageView), findsOneWidget);
    await ende(t);
  });

  testWidgets('Anmelde-QR für Apps mit der Karte angemeldet → Hinweis aufs Rosenweg-Konto', (t) async {
    await zeigen(t, const Size(412, 900), vorher: (a) {
      a.erzwungen['POST /api/apps/qr-ausweis'] =
          (status: 403, json: {'error': 'Nur mit Browser-Login (Rosenweg-Konto) möglich, nicht mit der Karte'});
    });
    await zu(t, 'Anmelde-QR');
    await t.tap(find.text('App auf eigenem Handy'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('nur, wenn du mit dem Rosenweg-Konto angemeldet bist'), findsOneWidget);
    await ende(t);
  });

  testWidgets('Technik: Bereich „Alle Handys“, Zugang sperren', (t) async {
    final a = await zeigen(t, const Size(412, 900), gruppen: const ['technik']);
    await zu(t, 'Alle Handys');
    await t.pumpAndSettle();
    expect(find.text('300215-p9 · Galaxy A55'), findsOneWidget);
    await t.tap(find.text('Sperren').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Sperren'));
    await t.pumpAndSettle();
    expect(a.anfragen.any((r) => r.methode == 'DELETE' && r.pfad == '/api/pbx/sip-privat/9'), isTrue);
    expect(find.text('300215-p9 · Galaxy A55'), findsNothing);
    expect(find.text('Zugang 300215-p9 gesperrt.'), findsOneWidget);
    await ende(t);
  });

  testWidgets('Desktop (Station): Leiste links', (t) async {
    await zeigen(t, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await ende(t);
  });

  testWidgets('Geteiltes Telefon: Hinweis, keine Anfrage an die Anlage', (t) async {
    final a = await zeigen(t, const Size(412, 900), geteilt: true);
    expect(find.textContaining('Dies ist ein geteiltes Telefon'), findsOneWidget);
    expect(a.anfragen.where((r) => r.pfad.startsWith('/api/telefon')), isEmpty);
    await ende(t);
  });

  testWidgets('Fehler der Anlage zeigt Nochmals und lädt neu', (t) async {
    await zeigen(t, const Size(412, 900), vorher: (a) {
      a.erzwungen['GET /api/telefon/ich'] = (status: 503, json: {'error': 'Wartung'});
    });
    expect(find.text('Nochmals'), findsOneWidget);
    await t.tap(find.text('Nochmals'));
    await t.pumpAndSettle();
    expect(find.text('300107'), findsOneWidget);
    await ende(t);
  });

  test('Handys: ohne Gerätekennung zum Handy mit gleichem Modell, als „vermutlich“', () {
    final hs = handysBilden([
      Anmeldung.telefon({'id': 1, 'geraet': 'samsung SM-A376B', 'geraet_gruppe': 'g1', 'registriert': true}),
      Anmeldung.messenger({'id': 2, 'geraet': 'samsung  SM-A376B'}),
      Anmeldung.karte({'id': 'as_x', 'app': 'ch.rosenweg4303.salz', 'app_name': 'Rosenweg Salz', 'geraet_name': 'Laptop'}),
    ]);
    expect(hs, hasLength(2));
    final samsung = hs.firstWhere((h) => h.name == 'samsung SM-A376B');
    expect(samsung.apps.map((a) => a.name), ['Rosenweg Telefon', 'Rosenweg Messenger']);
    expect(samsung.vermutlich, isTrue);
    expect(hs.firstWhere((h) => h.name == 'Laptop').vermutlich, isFalse);
  });

  test('Erreichbarkeit: Sekunden auf die Auswahl, Zeiten der Anlage in Ortszeit', () {
    expect(Erreichbarkeit.aus({'weiterleitung': 'nicht_erreichbar', 'sekunden': 25}).sekundenGewaehlt, 20);
    expect(Erreichbarkeit.aus({'weiterleitung': 'quatsch'}).weiterleitung, Weiterleitung.aus);
    expect(zeitLesen('2026-11-27 09:12:00'), DateTime.utc(2026, 11, 27, 9, 12).toLocal());
    expect(zeitLesen('2026-11-27T09:12:00+00:00'), DateTime.utc(2026, 11, 27, 9, 12).toLocal());
  });

  test('Kennung, Ordner und Logo passen zusammen', () {
    expect(appAngaben.kennung, 'ch.rosenweg4303.meintelefon');
    expect(appAngaben.kennung, matches(RegExp(r'^ch\.rosenweg4303\.[a-z][a-z0-9]*$')));
    expect(appAngaben.gruppe, RosenwegGruppe.bewohner);
    expect(File('assets/logo/${appAngaben.ordner}-512.png').existsSync(), isTrue);
    expect(File('assets/logo/${appAngaben.ordner}-klein.png').existsSync(), isTrue);
  });
}
