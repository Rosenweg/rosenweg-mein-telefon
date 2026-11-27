// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../mein_telefon_api.dart';

/// Zwei Codes, nicht austauschbar (wie smartphones.html, Stefan 27.11.2026):
enum QrArt {
  /// Fuer den Sperrbildschirm eines geteilten Telefons (Telefonanlage, RWTEL1…).
  telefon,

  /// Fuer den Anmeldeschirm einer Rosenweg-App auf dem eigenen Handy (Haupt-API, RWAPP1…).
  app,
}

/// Anmelde-QR zeigen. Er gilt einmal und nur kurz; die Seite holt kurz vor
/// Ablauf von selbst einen neuen. Beim App-QR meldet sie, sobald eine App ihn
/// eingeloest hat, und holt gleich den naechsten.
class AnmeldeQrSeite extends StatefulWidget {
  const AnmeldeQrSeite({super.key, required this.api, this.nur, this.takt = const Duration(seconds: 1)});
  final MeinTelefonApi api;

  /// Nur diese Art, ohne Umschalter (aus "Geräte" geoeffnet).
  final QrArt? nur;

  /// Abstand der Uhr (Tests: laengere Abstaende).
  final Duration takt;

  @override
  State<AnmeldeQrSeite> createState() => _AnmeldeQrSeiteState();
}

class _AnmeldeQrSeiteState extends State<AnmeldeQrSeite> with WidgetsBindingObserver {
  late QrArt _art = widget.nur ?? QrArt.telefon;
  AnmeldeQr? _qr;
  Object? _fehler;
  String? _eingeloest;
  bool _holt = false;
  bool _fragt = false;
  bool _sichtbar = true;
  int _schlag = 0;
  Timer? _uhr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _holen();
    _uhr = Timer.periodic(widget.takt, (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uhr?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // im Hintergrund keine Codes holen; zurueck im Vordergrund gleich einen frischen
    _sichtbar = s == AppLifecycleState.resumed;
    if (_sichtbar && (_qr == null || _rest <= 10)) _holen();
  }

  int get _rest => _qr == null ? 0 : _qr!.bis.difference(DateTime.now()).inSeconds;

  void _waehlen(QrArt a) {
    if (a == _art) return;
    setState(() {
      _art = a;
      _qr = null;
      _fehler = null;
      _eingeloest = null;
    });
    _holen();
  }

  Future<void> _holen() async {
    if (_holt) return;
    _holt = true;
    final art = _art;
    try {
      final qr = art == QrArt.app ? await widget.api.appQr() : await widget.api.telefonQr();
      if (!mounted || art != _art) return;
      setState(() {
        _qr = qr;
        _fehler = null;
      });
    } catch (e) {
      if (!mounted || art != _art) return;
      setState(() {
        _qr = null;
        _fehler = e;
      });
    } finally {
      _holt = false;
    }
  }

  /// App-QR: hat ihn eine App eingeloest? Dann zeigen welche (und wo) und gleich einen neuen holen.
  Future<void> _stand() async {
    final id = _qr?.id;
    if (_art != QrArt.app || id == null || _fragt) return;
    _fragt = true;
    try {
      final s = await widget.api.appQrStand(id);
      if (s.eingeloest && mounted && _qr?.id == id) {
        setState(() {
          _eingeloest = '${s.appName ?? 'Die App'} auf ${s.geraetName ?? 'deinem Handy'} ist angemeldet.';
          _qr = null;
        });
        await _holen();
      }
    } catch (_) {
      // naechster Versuch beim naechsten Schlag
    } finally {
      _fragt = false;
    }
  }

  void _tick() {
    if (!mounted || !_sichtbar) return;
    // Fehler (z. B. nicht freigeschaltet) nicht staendig neu versuchen: Knopf "Nochmals"
    if (_fehler != null) return;
    setState(() {}); // Restzeit
    if (_qr != null && _rest <= 10) _holen();
    if (++_schlag % 2 == 0) _stand();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    final text = switch (_art) {
      QrArt.telefon => 'Am gesperrten geteilten Telefon „QR-Code scannen“ tippen und diesen Code vor die Kamera halten. '
          'Noch einfacher: Rosenweg-Karte hinten ans Telefon halten.',
      QrArt.app => 'In der Rosenweg-App auf deinem Handy „QR-Code scannen“ tippen und die Kamera auf diesen Code halten. '
          'Jede App meldet sich einzeln an. Ist die App auf diesem Gerät? Dann dort einfach „Mit Rosenweg-Konto anmelden“ tippen.',
    };
    final qr = _qr;
    final rest = _rest;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.nur == null) ...[
          Center(
            child: SegmentedButton<QrArt>(
              key: const Key('qr-art'),
              segments: const [
                ButtonSegment(value: QrArt.telefon, icon: Icon(Icons.phone_android), label: Text('Geteiltes Telefon')),
                ButtonSegment(value: QrArt.app, icon: Icon(Icons.apps), label: Text('App auf eigenem Handy')),
              ],
              selected: {_art},
              onSelectionChanged: (s) => _waehlen(s.first),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(text, style: t.bodyMedium),
        const SizedBox(height: 16),
        if (_eingeloest != null) ...[
          Hinweis(_eingeloest!, art: HinweisArt.gut),
          const SizedBox(height: 12),
        ],
        if (_fehler != null)
          _QrFehler(fehler: _fehler!, art: _art, nochmals: _holen, zurApp: widget.nur == null ? () => _waehlen(QrArt.app) : null)
        else
          Center(
            child: Container(
              key: const Key('qr'),
              // immer weiss mit Rand, auch im dunklen Modus: sonst lesen Kameras schlecht
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              width: 280,
              height: 280,
              child: qr == null
                  ? const Center(child: CircularProgressIndicator())
                  : Opacity(
                      opacity: rest > 0 ? 1 : 0.25,
                      child: QrImageView(
                        data: qr.inhalt,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        semanticsLabel: _art == QrArt.app ? 'Anmelde-QR für eine App' : 'Anmelde-QR für ein geteiltes Telefon',
                      ),
                    ),
            ),
          ),
        if (_fehler == null) ...[
          const SizedBox(height: 8),
          Text(
            qr == null ? 'wird geholt …' : (rest > 0 ? 'gültig noch $rest s' : 'wird erneuert …'),
            key: const Key('frist'),
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: grau),
          ),
        ],
      ],
    );
  }
}

class _QrFehler extends StatelessWidget {
  const _QrFehler({required this.fehler, required this.art, required this.nochmals, this.zurApp});
  final Object fehler;
  final QrArt art;
  final VoidCallback nochmals;
  final VoidCallback? zurApp;

  @override
  Widget build(BuildContext context) {
    // 403 der Anlage: Konto nicht fuer geteilte Telefone freigeschaltet;
    // 403 der Haupt-API: App-QR nur mit dem Rosenweg-Konto, nicht mit der Karte.
    if (fehler is KeineBerechtigung) {
      final text = art == QrArt.telefon
          ? 'Dein Konto ist für geteilte Telefone nicht freigeschaltet. Melde dich bei der Technik.'
          : 'Einen App-QR gibt es nur, wenn du mit dem Rosenweg-Konto angemeldet bist, nicht mit der Karte. '
              'Im Menü oben rechts abmelden und mit dem Rosenweg-Konto neu anmelden.';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Hinweis(text, art: HinweisArt.warnung),
        if (art == QrArt.telefon && zurApp != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: zurApp, child: const Text('Anmelde-QR für eine App zeigen')),
          ),
        ],
      ]);
    }
    return FehlerAnzeige.aus(fehler, nochmals: nochmals, titel: 'Kein Anmelde-QR');
  }
}
