// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'app.dart';
import 'daten.dart';

/// Alle Aufrufe der App.
///
/// Zwei Dienste:
///
///  * [pbx] Telefonanlage `pbx.rosenweg4303.ch` (pbx/api/app.py): Nummer,
///    Erreichbarkeit, geteilte Telefone, Rosenweg Telefon auf eigenen Handys,
///    Anmelde-QR fuer geteilte Telefone
///  * [web] Haupt-API `rosenweg4303.ch`: Anmelde-QR fuer Apps, Messenger-
///    Zugaenge, Karten-/QR-Sitzungen der Apps
///
/// Eigenes Handy, Computer, Station: die Anlage direkt mit dem Zugang der
/// Anmeldung (Konto, Karte, QR, Kerberos – die Anlage prueft das Token ueber
/// `/api/auth/me` der Haupt-API).
///
/// Geteiltes Telefon: kein Token; Rosenweg Geraet reicht Anfragen nur an die
/// Haupt-API. Dort reicht `/api/telefonanlage/*` die Anfragen dieser App an
/// die Anlage weiter, im Auftrag der Person am Telefon und nur fuer sie
/// (Website api/routes/telefonanlage.js) – [AnlageUeberHauptApi].
class MeinTelefonApi {
  MeinTelefonApi({required this.web, required this.pbx, this.istGeteiltesTelefon = false});

  /// Fuer die App. [transport] ersetzt Haupt-API und Anlage (Attrappe, Tests).
  factory MeinTelefonApi.fuer(RosenwegSitzung s, {Transport? transport}) {
    final geteilt = s.geteiltesTelefon;
    final Transport anlage = geteilt
        ? AnlageUeberHauptApi(transport ?? s.api.transport)
        : transport ?? HttpTransport(basis: telefonanlage, zugang: s.zugang);
    return MeinTelefonApi(
      web: s.api,
      pbx: RosenwegApi(anlage, nichtAngemeldet: geteilt ? s.api.nichtAngemeldet : s.nichtMehrAngemeldet),
      istGeteiltesTelefon: geteilt,
    );
  }

  final RosenwegApi web;
  final RosenwegApi pbx;
  final bool istGeteiltesTelefon;

  static String _p(String s) => Uri.encodeComponent(s);
  static List<Map<String, dynamic>> _liste(Object? l) =>
      [for (final e in l is List ? l : const []) if (e is Map<String, dynamic>) e];

  // ── Nummer und Erreichbarkeit (Anlage) ──
  Future<MeineNummer> ich() async => MeineNummer.aus(await pbx.objekt('/api/telefon/ich'));

  /// Gilt ab dem naechsten Anruf. Antwort: der gespeicherte Stand (Ziel normalisiert).
  Future<Erreichbarkeit> erreichbarkeitSpeichern(Erreichbarkeit e) async {
    final j = await pbx.put('/api/telefon/ich/erreichbarkeit', e.json());
    return j is Map && j['erreichbarkeit'] != null ? Erreichbarkeit.aus(j['erreichbarkeit']) : e;
  }

  // ── Geraete ──
  /// Geteilte Telefone, an denen die Person angemeldet ist, ihre Handys mit
  /// Rosenweg Telefon, und ob sie sich an geteilten Telefonen anmelden darf.
  Future<({List<GeteiltesTelefon> geteilt, List<Anmeldung> telefon, bool darf})> meine() async {
    final j = await pbx.objekt('/api/telefon/meine');
    return (
      geteilt: [for (final s in _liste(j['sitzungen'])) GeteiltesTelefon.aus(s)],
      telefon: [for (final p in _liste(j['privat'])) Anmeldung.telefon(p)],
      darf: j['darf'] != false,
    );
  }

  Future<List<Anmeldung>> messenger() async {
    final j = await web.objekt('/api/messenger/zugaenge');
    return [for (final z in _liste(j['zugaenge'])) Anmeldung.messenger(z)];
  }

  Future<List<Anmeldung>> appSitzungen() async {
    final j = await web.objekt('/api/apps/sitzungen');
    return [for (final s in _liste(j['sitzungen'])) Anmeldung.karte(s)];
  }

  /// Eine Anmeldung auf einem eigenen Handy beenden – je nach Quelle beim
  /// richtigen Dienst (wie js/meine-geraete.js).
  Future<void> abmelden(Anmeldung a) => switch (a.quelle) {
        Quelle.telefon => pbx.delete('/api/telefon/privat/${_p(a.id)}'),
        Quelle.messenger => web.delete('/api/messenger/zugaenge/${_p(a.id)}'),
        Quelle.karte => web.delete('/api/apps/sitzungen/${_p(a.id)}'),
      };

  /// Am geteilten Telefon abmelden.
  Future<void> geteiltAbmelden(String ext) => pbx.post('/api/telefon/${_p(ext)}/abmelden');

  /// Verlegtes geteiltes Telefon bis 45 s klingeln lassen.
  Future<void> klingeln(String ext) => pbx.post('/api/telefon/${_p(ext)}/suchen');

  /// Nach [klingeln]: wurde am Telefon "Gefunden" getippt? (Zeit, von wem)
  Future<({DateTime? gefunden, String? von})> klingelnStand(String ext) async {
    final j = await pbx.objekt('/api/telefon/${_p(ext)}/suchen');
    final von = j['gefunden_von'];
    return (gefunden: zeitLesen(j['gefunden']), von: von is String && von.isNotEmpty ? von : null);
  }

  // ── Anmelde-QR ──
  /// Fuer ein geteiltes Telefon (Sperrbildschirm "QR-Code scannen"), einmalig, ~90 s.
  Future<AnmeldeQr> telefonQr() async => AnmeldeQr.aus(await pbx.post('/api/telefon/ausweis'));

  /// Fuer eine Rosenweg-App auf einem eigenen Handy (Anmeldeschirm "QR-Code
  /// scannen"). Nur mit dem Rosenweg-Konto, nicht mit der Karte (403).
  Future<AnmeldeQr> appQr() async => AnmeldeQr.aus(await web.post('/api/apps/qr-ausweis'));

  Future<QrStand> appQrStand(String id) async => QrStand.aus(await web.get('/api/apps/qr-ausweis/${_p(id)}'));

  // ── Technik: alle Handys mit Rosenweg Telefon ──
  Future<List<SipZugang>> alleSipZugaenge() async => [for (final z in _liste(await pbx.get('/api/pbx/sip-privat'))) SipZugang.aus(z)];

  Future<void> sipZugangSperren(int id) => pbx.delete('/api/pbx/sip-privat/$id');
}

/// Geteiltes Telefon: Anfragen an die Anlage (`/api/telefon/…`) gehen ueber die
/// Haupt-API (`/api/telefonanlage/…`, mit dem Transport von Rosenweg Geraet).
/// Die Technik-Pfade der Anlage (`/api/pbx/…`) gibt es dort nicht.
class AnlageUeberHauptApi implements Transport {
  AnlageUeberHauptApi(this.haupt);
  final Transport haupt;

  static String? umschreiben(String pfad) =>
      pfad.startsWith('/api/telefon/') ? '/api/telefonanlage/${pfad.substring('/api/telefon/'.length)}' : null;

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) {
    final neu = umschreiben(pfad);
    if (neu == null) {
      return Future.value((status: 403, json: {'error': 'Auf einem geteilten Telefon nicht möglich.'}));
    }
    return haupt.senden(methode, neu, koerper: koerper);
  }
}
