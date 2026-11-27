// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Antwortet wie Haupt-API und Telefonanlage zusammen (die Pfade ueberschneiden
/// sich nicht), mit erfundenen Daten: keine echten Personen, Nummern oder Geraete.
/// Fuer Tests, Bildschirmfotos und Entwicklung ohne Server
/// (--dart-define=RW_ATTRAPPE=1).
class Attrappe implements Transport {
  Attrappe({this.gruppen = const ['stweg3-eigentuemer'], this.mitNummer = true, this.darfGeteilt = true});

  /// Gruppen der angemeldeten Person (mit 'technik': Bereich "Alle Handys").
  final List<String> gruppen;
  final bool mitNummer;
  final bool darfGeteilt;

  /// Alle Anfragen in der Reihenfolge (fuer Tests).
  final anfragen = <({String methode, String pfad, Object? koerper})>[];

  /// Naechste Antwort fuer einen Pfad erzwingen (Tests), z. B. einen Fehler:
  /// `erzwungen['GET /api/telefon/ich'] = (status: 503, json: null);`
  final erzwungen = <String, ApiAntwort>{};

  var _erreichbarkeit = <String, Object?>{'weiterleitung': 'nicht_erreichbar', 'ziel': '+41790000000', 'sekunden': 20, 'voicemail': true};
  Map<String, Object?>? _zuletzt = {'ereignis': 'Erreichbarkeit: …', 'durch': 'selbst', 'zeit': '2026-11-26 18:04:00'};
  int _qrNr = 0;
  int _standAbfragen = 0;

  final _geteilt = <Map<String, Object?>>[
    {'ext': '2041', 'geraet': 'Telefon Waschküche Haus 9', 'seit': '2026-11-27 07:58:00'},
  ];

  final _privat = <Map<String, Object?>>[
    {'id': 4, 'kennung': '300107-p4', 'geraet': 'Pixel 8', 'seit': '2026-11-20 10:00:00', 'geraet_gruppe': 'hA1', 'registriert': true},
  ];

  final _messenger = <Map<String, Object?>>[
    {'id': 12, 'kennung': 'z12', 'geraet': 'Pixel 8', 'seit': '2026-11-21T08:00:00Z', 'zuletzt': '2026-11-27T07:30:00Z', 'geraet_gruppe': 'hA1'},
  ];

  final _sitzungen = <Map<String, Object?>>[
    {'id': 'as_aaaaaaaaaaaaaaaa', 'app': 'ch.rosenweg4303.salz', 'app_name': 'Rosenweg Salz', 'geraet_name': 'Pixel 8',
     'geraet_gruppe': 'hA1', 'art': 'karte', 'karte_anzeige': '0042', 'created_at': '2026-11-22T18:00:00Z', 'last_used_at': '2026-11-26T21:15:00Z'},
    {'id': 'as_bbbbbbbbbbbbbbbb', 'app': 'ch.rosenweg4303.profil', 'app_name': 'Rosenweg Profil', 'geraet_name': 'iPad Küche',
     'geraet_gruppe': 'hB2', 'art': 'qr', 'created_at': '2026-11-24T19:00:00Z', 'last_used_at': '2026-11-25T20:10:00Z'},
  ];

  final _alleSip = <Map<String, Object?>>[
    {'id': 4, 'nummer': '300107', 'email': 'erika.muster@example.org', 'geraet': 'Pixel 8', 'created_at': '2026-11-20 10:00:00',
     'kennung': '300107-p4', 'registriert': true},
    {'id': 9, 'nummer': '300215', 'email': 'max.beispiel@example.org', 'geraet': 'Galaxy A55', 'created_at': '2026-11-23 12:30:00',
     'kennung': '300215-p9', 'registriert': false},
  ];

  Map<String, Object?> get _ich => {
        'id': 7,
        'username': 'erika.muster',
        'name': 'Erika Muster',
        'email': 'erika.muster@example.org',
        'role': 'user',
        'groups': gruppen,
        'permissions': {'dashboard': 'read'},
      };

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    anfragen.add((methode: methode, pfad: pfad, koerper: koerper));
    final z = erzwungen.remove('$methode $pfad');
    if (z != null) return z;
    final k = koerper is Map ? koerper : const {};
    final ich = _ich;

    switch ('$methode $pfad') {
      case 'GET /api/auth/me':
        return (status: 200, json: {'user': ich});

      // ── Telefonanlage ──
      case 'GET /api/telefon/ich':
        if (!mitNummer) return (status: 200, json: {'name': ich['name'], 'nummer': null});
        return (status: 200, json: {
          'name': ich['name'], 'nummer': '300107', 'haus': 9, 'wohnung': '3.2',
          'erreichbarkeit': _erreichbarkeit,
          'geraete': [
            for (final p in _privat)
              {'art': 'app', 'id': p['id'], 'name': p['geraet'], 'seit': p['seit'], 'kennung': p['kennung'], 'erreichbar': p['registriert']},
            for (final g in _geteilt) {'art': 'geteilt', 'ext': g['ext'], 'name': g['geraet'], 'seit': g['seit'], 'erreichbar': true},
          ],
          'gruppen': [
            if (gruppen.contains('technik'))
              {'nummer': '1000', 'name': 'Ring-Group Technik', 'dienste': ['2000 Dienst Technik', 'Amtsnummer'], 'immer': false},
          ],
          'zuletzt_geaendert': _zuletzt,
          'darf': darfGeteilt,
        });
      case 'PUT /api/telefon/ich/erreichbarkeit':
        final wl = '${k['weiterleitung'] ?? 'aus'}';
        final ziel = '${k['ziel'] ?? ''}'.replaceAll(RegExp(r'[\s\-/().]'), '');
        if (wl != 'aus' && !RegExp(r'^(\+|0)[0-9]{6,15}$').hasMatch(ziel)) {
          return (status: 400, json: {'error': 'Zielnummer ungültig (z.B. 079 123 45 67 oder +49 …)'});
        }
        _erreichbarkeit = {'weiterleitung': wl, 'ziel': ziel, 'sekunden': k['sekunden'] ?? 20, 'voicemail': k['voicemail'] == true};
        _zuletzt = {'ereignis': 'Erreichbarkeit: …', 'durch': 'selbst', 'zeit': '2026-11-27 10:00:00'};
        return (status: 200, json: {'ok': true, 'erreichbarkeit': _erreichbarkeit});
      case 'GET /api/telefon/meine':
        return (status: 200, json: {'name': ich['name'], 'darf': darfGeteilt, 'sitzungen': _geteilt, 'privat': _privat});
      case 'POST /api/telefon/ausweis':
        if (!darfGeteilt) return (status: 403, json: {'error': 'Dein Konto ist fuer geteilte Telefone nicht freigeschaltet'});
        _qrNr++;
        return (status: 200, json: {'inhalt': 'RWTEL1:attrappe-$_qrNr', 'qr_svg': '<svg/>', 'ttl_seconds': 90});
      case 'GET /api/pbx/sip-privat':
        if (!gruppen.contains('technik')) return (status: 403, json: {'error': 'Nur fuer Technik / Praesident'});
        return (status: 200, json: _alleSip);

      // ── Haupt-API ──
      case 'GET /api/messenger/zugaenge':
        return (status: 200, json: {'max': 5, 'zugaenge': _messenger});
      case 'GET /api/apps/sitzungen':
        return (status: 200, json: {'sitzungen': _sitzungen, 'alle': false});
      case 'POST /api/apps/qr-ausweis':
        _qrNr++;
        _standAbfragen = 0;
        return (status: 200, json: {
          'id': 'qa_attrappe${_qrNr.toString().padLeft(8, '0')}',
          'inhalt': 'RWAPP1:attrappe-$_qrNr',
          'qr_svg': '<svg/>',
          'ttl_seconds': 90,
        });
    }

    // Pfade mit Kennung
    final geteiltAb = RegExp(r'^/api/telefon/(\d+)/abmelden$').firstMatch(pfad);
    if (methode == 'POST' && geteiltAb != null) {
      _geteilt.removeWhere((g) => g['ext'] == geteiltAb[1]);
      return (status: 200, json: {'ok': true, 'angemeldet': false});
    }
    final suchen = RegExp(r'^/api/telefon/(\d+)/suchen$').firstMatch(pfad);
    if (suchen != null) {
      if (methode == 'POST') return (status: 200, json: {'ok': true});
      return (status: 200, json: {'start': '2026-11-27T10:00:00+00:00', 'gefunden': '2026-11-27T10:00:09+00:00', 'gefunden_von': 'Erika Muster'});
    }
    final privat = RegExp(r'^/api/telefon/privat/(\d+)$').firstMatch(pfad);
    if (methode == 'DELETE' && privat != null) {
      _privat.removeWhere((p) => '${p['id']}' == privat[1]);
      return (status: 200, json: {'ok': true});
    }
    final messenger = RegExp(r'^/api/messenger/zugaenge/(\d+)$').firstMatch(pfad);
    if (methode == 'DELETE' && messenger != null) {
      _messenger.removeWhere((m) => '${m['id']}' == messenger[1]);
      return (status: 200, json: {'ok': true});
    }
    final sitzung = RegExp(r'^/api/apps/sitzungen/(as_[A-Za-z0-9_-]+)$').firstMatch(pfad);
    if (methode == 'DELETE' && sitzung != null) {
      _sitzungen.removeWhere((s) => s['id'] == sitzung[1]);
      return (status: 200, json: {'ok': true});
    }
    final qrStand = RegExp(r'^/api/apps/qr-ausweis/(qa_[A-Za-z0-9_-]+)$').firstMatch(pfad);
    if (methode == 'GET' && qrStand != null) {
      // beim dritten Nachfragen "eingeloest" (Vorfuehrung)
      final ein = ++_standAbfragen >= 3;
      return (status: 200, json: {
        'eingeloest': ein,
        if (ein) 'app_name': 'Rosenweg Zutritt',
        if (ein) 'geraet_name': 'Pixel 8',
        'abgelaufen': false,
      });
    }
    final sip = RegExp(r'^/api/pbx/sip-privat/(\d+)$').firstMatch(pfad);
    if (methode == 'DELETE' && sip != null) {
      _alleSip.removeWhere((s) => '${s['id']}' == sip[1]);
      return (status: 200, json: {'ok': true});
    }
    return (status: 404, json: {'error': 'Nicht gefunden: $methode $pfad'});
  }
}
