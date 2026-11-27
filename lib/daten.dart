// SPDX-License-Identifier: GPL-3.0-or-later
//
// Daten der App, gelesen aus den Antworten der Telefonanlage
// (pbx/api/app.py: /api/telefon/ich, /api/telefon/meine, /api/pbx/sip-privat)
// und der Haupt-API (/api/messenger/zugaenge, /api/apps/sitzungen).
// Felder nur lesen, nie voraussetzen: fehlt eines, gilt ein sinnvoller Ersatz.

Map<String, dynamic> _objekt(Object? j) => j is Map<String, dynamic> ? j : const {};
List<Map<String, dynamic>> _liste(Object? l) => [for (final e in l is List ? l : const []) if (e is Map<String, dynamic>) e];
String? _text(Object? t) => t == null || '$t'.trim().isEmpty ? null : '$t';

/// Zeit der Anlage: SQLite `2026-11-27 09:12:00` (UTC, ohne Zone) oder ISO mit Zone.
DateTime? zeitLesen(Object? t) {
  final s = _text(t);
  if (s == null) return null;
  final iso = s.replaceFirst(' ', 'T');
  final mitZone = RegExp(r'([zZ]|[+-]\d\d:?\d\d)$').hasMatch(iso);
  return DateTime.tryParse(mitZone ? iso : '${iso}Z')?.toLocal();
}

String _zwei(int n) => n.toString().padLeft(2, '0');

/// "27.11., 09:12" wie im Portal.
String zeitKurz(DateTime? d) => d == null ? '' : '${_zwei(d.day)}.${_zwei(d.month)}., ${_zwei(d.hour)}:${_zwei(d.minute)}';

/// Weiterleitung der persoenlichen Nummer (wie `personen_nummern.weiterleitung`).
enum Weiterleitung {
  /// Es klingelt nur auf den eigenen Geraeten.
  aus,

  /// Zuerst die Geraete, nach [Erreichbarkeit.sekunden] die Zielnummer.
  nichtErreichbar,

  /// Nur die Zielnummer.
  immer;

  String get wert => this == nichtErreichbar ? 'nicht_erreichbar' : name;

  static Weiterleitung aus_(Object? w) => switch (w) {
        'immer' => immer,
        'nicht_erreichbar' => nichtErreichbar,
        _ => aus,
      };
}

/// Was passiert, wenn jemand die Nummer anruft.
class Erreichbarkeit {
  const Erreichbarkeit({this.weiterleitung = Weiterleitung.aus, this.ziel = '', this.sekunden = 20, this.voicemail = false});
  final Weiterleitung weiterleitung;
  final String ziel;
  final int sekunden;
  final bool voicemail;

  /// Auswahl der Sekunden wie im Portal; die Anlage nimmt 5–60.
  static const sekundenWahl = [10, 15, 20, 30, 45, 60];

  factory Erreichbarkeit.aus(Object? j) {
    final e = _objekt(j);
    final s = e['sekunden'];
    return Erreichbarkeit(
      weiterleitung: Weiterleitung.aus_(e['weiterleitung']),
      ziel: _text(e['ziel']) ?? '',
      sekunden: s is num ? s.round().clamp(5, 60) : 20,
      voicemail: e['voicemail'] == true,
    );
  }

  /// Naechster Wert aus [sekundenWahl] (die Anlage kennt auch andere).
  int get sekundenGewaehlt =>
      sekundenWahl.reduce((a, b) => (b - sekunden).abs() < (a - sekunden).abs() ? b : a);

  Map<String, Object?> json() => {
        'weiterleitung': weiterleitung.wert,
        'ziel': ziel,
        'sekunden': sekunden,
        'voicemail': voicemail,
      };

  Erreichbarkeit mit({Weiterleitung? weiterleitung, String? ziel, int? sekunden, bool? voicemail}) => Erreichbarkeit(
        weiterleitung: weiterleitung ?? this.weiterleitung,
        ziel: ziel ?? this.ziel,
        sekunden: sekunden ?? this.sekunden,
        voicemail: voicemail ?? this.voicemail,
      );

  @override
  bool operator ==(Object other) =>
      other is Erreichbarkeit && other.weiterleitung == weiterleitung && other.ziel.trim() == ziel.trim() && other.sekunden == sekunden && other.voicemail == voicemail;

  @override
  int get hashCode => Object.hash(weiterleitung, ziel.trim(), sekunden, voicemail);
}

/// Gruppe, in der die Nummer mitklingelt (heute: Ring-Group Technik).
class Gruppe {
  const Gruppe({required this.nummer, required this.name, this.dienste = const [], this.immer = false});
  final String nummer;
  final String name;
  final List<String> dienste;

  /// Auch ausserhalb der Geschaeftszeiten.
  final bool immer;

  factory Gruppe.aus(Map<String, dynamic> j) => Gruppe(
        nummer: '${j['nummer'] ?? ''}',
        name: '${j['name'] ?? 'Gruppe'}',
        dienste: [for (final d in j['dienste'] is List ? j['dienste'] as List : const []) '$d'],
        immer: j['immer'] == true,
      );

  /// "Du klingelst in der Ring-Group Technik (1000) und damit für … , auch ausserhalb der Geschäftszeiten."
  String get satz => 'Du klingelst in der $name ($nummer)'
      '${dienste.isEmpty ? '' : ' und damit für ${dienste.join(' und ')}'}'
      '${immer ? ', auch ausserhalb der Geschäftszeiten' : ', während der Geschäftszeiten'}.';
}

/// Alles zur eigenen Nummer (`GET /api/telefon/ich`).
class MeineNummer {
  const MeineNummer({
    required this.name,
    this.nummer,
    this.haus,
    this.wohnung,
    this.erreichbarkeit = const Erreichbarkeit(),
    this.gruppen = const [],
    this.zuletztZeit,
    this.zuletztDurch,
    this.darfGeteilt = true,
  });
  final String name;

  /// null: die Person hat (noch) keine Rosenweg-Nummer.
  final String? nummer;
  final int? haus;
  final String? wohnung;
  final Erreichbarkeit erreichbarkeit;
  final List<Gruppe> gruppen;
  final DateTime? zuletztZeit;

  /// 'selbst' oder Name der Technik-Person.
  final String? zuletztDurch;

  /// Darf sich an geteilten Telefonen anmelden.
  final bool darfGeteilt;

  factory MeineNummer.aus(Object? j) {
    final d = _objekt(j);
    final z = _objekt(d['zuletzt_geaendert']);
    final h = d['haus'];
    return MeineNummer(
      name: _text(d['name']) ?? '',
      nummer: _text(d['nummer']),
      haus: h is num ? h.toInt() : int.tryParse('${h ?? ''}'),
      wohnung: _text(d['wohnung']),
      erreichbarkeit: Erreichbarkeit.aus(d['erreichbarkeit']),
      gruppen: [for (final g in _liste(d['gruppen'])) Gruppe.aus(g)],
      zuletztZeit: zeitLesen(z['zeit']),
      zuletztDurch: _text(z['durch']),
      darfGeteilt: d['darf'] != false,
    );
  }

  /// "Erika Muster · Haus 9, Wohnung 3.2" (Haus 0 = MEG)
  String get wer {
    final teile = <String>[if (name.isNotEmpty) name];
    if (haus != null) teile.add('Haus ${haus == 0 ? 'MEG' : haus}${wohnung != null ? ', Wohnung $wohnung' : ''}');
    return teile.join(' · ');
  }
}

/// Geteiltes Telefon, an dem die Person angemeldet ist.
class GeteiltesTelefon {
  const GeteiltesTelefon({required this.ext, required this.name, this.seit});
  final String ext;
  final String name;
  final DateTime? seit;

  factory GeteiltesTelefon.aus(Map<String, dynamic> j) =>
      GeteiltesTelefon(ext: '${j['ext'] ?? ''}', name: _text(j['geraet']) ?? 'Telefon ${j['ext']}', seit: zeitLesen(j['seit']));
}

/// Woher eine Anmeldung auf einem eigenen Handy kommt; bestimmt, wie man sie abmeldet.
enum Quelle {
  /// Rosenweg Telefon (Anlage, telefon_sip_privat): DELETE /api/telefon/privat/:id
  telefon,

  /// Rosenweg Messenger (messenger_privat): DELETE /api/messenger/zugaenge/:id
  messenger,

  /// Karten-, QR- oder Handy-Sitzung einer App (app_karten_sitzungen): DELETE /api/apps/sitzungen/:id
  karte,
}

/// Eine Anmeldung einer App auf einem eigenen Handy.
class Anmeldung {
  const Anmeldung({
    required this.quelle,
    required this.id,
    required this.app,
    required this.appName,
    this.geraet,
    this.gruppe,
    this.seit,
    this.zuletzt,
    this.verbunden,
    this.text,
  });
  final Quelle quelle;
  final String id;

  /// Paket der App (ch.rosenweg4303.…).
  final String app;
  final String appName;
  final String? geraet;

  /// Gruppenschluessel des Handys (geraet_gruppe), gleich fuer alle Apps eines Handys.
  final String? gruppe;
  final DateTime? seit;
  final DateTime? zuletzt;

  /// Nur Rosenweg Telefon: mit der Anlage verbunden.
  final bool? verbunden;
  final String? text;

  static const telefonApp = 'ch.rosenweg4303.phone';
  static const messengerApp = 'ch.rosenweg4303.messages';

  /// `privat` aus /api/telefon/meine
  factory Anmeldung.telefon(Map<String, dynamic> j) => Anmeldung(
        quelle: Quelle.telefon,
        id: '${j['id']}',
        app: telefonApp,
        appName: 'Rosenweg Telefon',
        geraet: _text(j['geraet']),
        gruppe: _text(j['geraet_gruppe']),
        seit: zeitLesen(j['seit'] ?? j['created_at']),
        verbunden: j['registriert'] == true,
        text: _text(j['kennung']) != null ? 'Zugang ${j['kennung']}' : null,
      );

  /// `zugaenge` aus /api/messenger/zugaenge
  factory Anmeldung.messenger(Map<String, dynamic> j) => Anmeldung(
        quelle: Quelle.messenger,
        id: '${j['id']}',
        app: messengerApp,
        appName: 'Rosenweg Messenger',
        geraet: _text(j['geraet']),
        gruppe: _text(j['geraet_gruppe']),
        seit: zeitLesen(j['seit']),
        zuletzt: zeitLesen(j['zuletzt']),
      );

  /// `sitzungen` aus /api/apps/sitzungen
  factory Anmeldung.karte(Map<String, dynamic> j) {
    final art = j['art'];
    final wie = art == 'qr'
        ? 'mit Anmelde-QR'
        : art == 'handy'
            ? 'auf dem Handy bestätigt'
            : 'mit der Karte …${j['karte_anzeige'] ?? ''}';
    return Anmeldung(
      quelle: Quelle.karte,
      id: '${j['id']}',
      app: _text(j['app']) ?? _text(j['app_name']) ?? 'App',
      appName: _text(j['app_name']) ?? _text(j['app']) ?? 'App',
      geraet: _text(j['geraet_name']),
      gruppe: _text(j['geraet_gruppe']),
      seit: zeitLesen(j['created_at']),
      zuletzt: zeitLesen(j['last_used_at']),
      text: wie,
    );
  }

  /// Eine Zeile fuer die Anzeige: "verbunden · Zugang 300123-p4 · seit 27.11., 09:12".
  String get zeile => [
        if (verbunden != null) verbunden! ? 'verbunden' : 'gerade nicht verbunden',
        ?text,
        if (seit != null) 'seit ${zeitKurz(seit)}',
        if (zuletzt != null) 'zuletzt ${zeitKurz(zuletzt)}',
      ].join(' · ');
}

/// Eine App auf einem Handy, mit ihren Anmeldungen (meist eine; Rosenweg Telefon
/// kann zusaetzlich eine Karten-Sitzung haben).
class HandyApp {
  HandyApp(this.app, this.name);
  final String app;
  String name;
  final anmeldungen = <Anmeldung>[];
}

/// Ein eigenes Handy mit seinen Rosenweg-Apps.
class Handy {
  Handy(this.schluessel);
  final String schluessel;
  String name = 'Eigenes Handy';

  /// Ein Eintrag ohne Geraetekennung (aeltere App) steht hier nur nach dem Modellnamen.
  bool vermutlich = false;
  final apps = <HandyApp>[];
  DateTime? zuletzt;

  List<Anmeldung> get anmeldungen => [for (final a in apps) ...a.anmeldungen];
}

/// Anmeldungen je Handy zusammenlegen – wie js/meine-geraete.js der Website
/// (Stefan 26.11.2026: "ist nur 1 Telefon – so sieht es aus, als wären es 4 Geräte").
///
/// Alle drei Quellen liefern `geraet_gruppe` (gleiche Geraetekennung der
/// Rosenweg-Apps). Aeltere Eintraege ohne Kennung kommen zum Handy mit gleichem
/// Modellnamen, wenn es genau eines gibt, sonst nach Modell zusammen – beides
/// nur "vermutlich dasselbe Handy".
List<Handy> handysBilden(List<Anmeldung> xs) {
  final handys = <String, Handy>{};
  String modell(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final ohneKennung = <Anmeldung>{};
  final eintraege = <String, List<Anmeldung>>{};

  for (final e in xs.where((e) => e.gruppe != null)) {
    final k = 'g:${e.gruppe}';
    handys.putIfAbsent(k, () => Handy(k));
    (eintraege[k] ??= []).add(e);
  }
  for (final e in xs.where((e) => e.gruppe == null)) {
    final m = modell(e.geraet);
    final passend = [
      for (final k in handys.keys)
        if (k.startsWith('g:') && eintraege[k]!.any((x) => modell(x.geraet) == m)) k,
    ];
    final k = passend.length == 1 ? passend.first : 'm:$m';
    handys.putIfAbsent(k, () => Handy(k));
    (eintraege[k] ??= []).add(e);
    ohneKennung.add(e);
  }

  int rang(HandyApp a) => a.app == Anmeldung.telefonApp ? 0 : a.app == Anmeldung.messengerApp ? 1 : 2;
  for (final h in handys.values) {
    final es = eintraege[h.schluessel]!;
    final namen = [for (final e in es) ?e.geraet];
    h.name = namen.firstWhere((n) => n.contains(' '), orElse: () => namen.isEmpty ? 'Eigenes Handy' : namen.first);
    h.vermutlich = es.length > 1 && es.any(ohneKennung.contains);
    final apps = <String, HandyApp>{};
    for (final e in es) {
      final a = apps.putIfAbsent(e.app, () => HandyApp(e.app, e.appName));
      if (e.quelle != Quelle.karte) a.name = e.appName;
      a.anmeldungen.add(e);
    }
    h.apps.addAll(apps.values.toList()..sort((a, b) => rang(a) != rang(b) ? rang(a) - rang(b) : a.name.compareTo(b.name)));
    final zeiten = [for (final e in es) ?(e.zuletzt ?? e.seit)]..sort((a, b) => b.compareTo(a));
    h.zuletzt = zeiten.isEmpty ? null : zeiten.first;
  }
  return handys.values.toList()
    ..sort((a, b) => (b.zuletzt ?? DateTime(2000)).compareTo(a.zuletzt ?? DateTime(2000)));
}

/// Eigenes Handy mit Rosenweg Telefon, Sicht der Technik (`GET /api/pbx/sip-privat`).
class SipZugang {
  const SipZugang({required this.id, required this.kennung, this.email, this.geraet, this.seit, this.verbunden = false});
  final int id;

  /// `<nummer>-p<id>`
  final String kennung;
  final String? email;
  final String? geraet;
  final DateTime? seit;
  final bool verbunden;

  factory SipZugang.aus(Map<String, dynamic> j) => SipZugang(
        id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}') ?? 0,
        kennung: _text(j['kennung']) ?? '${j['nummer']}-p${j['id']}',
        email: _text(j['email']),
        geraet: _text(j['geraet']),
        seit: zeitLesen(j['created_at']),
        verbunden: j['registriert'] == true,
      );
}

/// Ausgestellter Anmelde-QR (`POST /api/telefon/ausweis` bzw. `/api/apps/qr-ausweis`).
class AnmeldeQr {
  const AnmeldeQr({required this.inhalt, required this.bis, this.id});

  /// Inhalt des Codes (RWTEL1… fuer geteilte Telefone, RWAPP1… fuer Apps).
  final String inhalt;
  final DateTime bis;

  /// Nur App-QR: Kennung fuer die Abfrage "eingeloest?".
  final String? id;

  factory AnmeldeQr.aus(Object? j, {DateTime? jetzt}) {
    final d = _objekt(j);
    final ttl = d['ttl_seconds'] is num ? (d['ttl_seconds'] as num).toInt() : 90;
    return AnmeldeQr(
      inhalt: '${d['inhalt'] ?? ''}',
      bis: (jetzt ?? DateTime.now()).add(Duration(seconds: ttl)),
      id: _text(d['id']),
    );
  }
}

/// Stand eines App-QR (`GET /api/apps/qr-ausweis/:id`).
class QrStand {
  const QrStand({required this.eingeloest, this.appName, this.geraetName});
  final bool eingeloest;
  final String? appName;
  final String? geraetName;

  factory QrStand.aus(Object? j) {
    final d = _objekt(j);
    return QrStand(eingeloest: d['eingeloest'] == true, appName: _text(d['app_name']), geraetName: _text(d['geraet_name']));
  }
}
