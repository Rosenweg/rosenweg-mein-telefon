// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:url_launcher/url_launcher.dart';

import '../daten.dart';
import '../mein_telefon_api.dart';
import 'anmelde_qr.dart';

/// Wo man angemeldet ist: geteilte Telefone (klingeln lassen, abmelden) und
/// eigene Handys mit ihren Rosenweg-Apps, je Handy einmal (abmelden, einzeln
/// oder alle). Laedt alle 15 Sekunden still nach, damit eine Anmeldung am
/// geteilten Telefon gleich erscheint.
class GeraeteSeite extends StatefulWidget {
  const GeraeteSeite({super.key, required this.api, this.nachladen = const Duration(seconds: 15)});
  final MeinTelefonApi api;

  /// Abstand fuers stille Nachladen (Tests: Duration.zero = aus).
  final Duration nachladen;

  @override
  State<GeraeteSeite> createState() => _GeraeteSeiteState();
}

class _GeraeteSeiteState extends State<GeraeteSeite> {
  List<GeteiltesTelefon>? _geteilt;
  List<Handy> _handys = const [];
  bool _darf = true;

  /// Dienste, die nicht geantwortet haben (ihre Eintraege fehlen).
  List<String> _fehlt = const [];
  Object? _fehler;
  Timer? _takt;
  final _laeuft = <String>{};

  @override
  void initState() {
    super.initState();
    _laden();
    if (widget.nachladen > Duration.zero) {
      _takt = Timer.periodic(widget.nachladen, (_) => _laden(still: true));
    }
  }

  @override
  void dispose() {
    _takt?.cancel();
    super.dispose();
  }

  Future<void> _laden({bool still = false}) async {
    if (!still) setState(() => _fehler = null);
    final fehlt = <String>[];
    // Messenger und App-Anmeldungen kommen von der Haupt-API: fehlt eine,
    // steht der Rest trotzdem da (mit Hinweis). Die Anlage ist die Hauptquelle.
    Future<List<Anmeldung>> teil(String wer, Future<List<Anmeldung>> Function() f) async {
      try {
        return await f();
      } catch (e) {
        Protokoll.schreiben('Geräte: $wer nicht geladen', '$e');
        fehlt.add(wer);
        return const [];
      }
    }

    final messengerF = teil('Rosenweg Messenger', widget.api.messenger);
    final appsF = teil('Anmeldungen der Apps', widget.api.appSitzungen);
    try {
      final meine = await widget.api.meine();
      final messenger = await messengerF;
      final apps = await appsF;
      if (!mounted) return;
      setState(() {
        _geteilt = meine.geteilt;
        _darf = meine.darf;
        _handys = handysBilden([...meine.telefon, ...messenger, ...apps]);
        _fehlt = fehlt;
        _fehler = null;
      });
    } catch (e) {
      if (mounted && !still) setState(() => _fehler = e);
    }
  }

  Future<void> _tun(String schluessel, Future<void> Function() aktion, String fertig) async {
    setState(() => _laeuft.add(schluessel));
    try {
      await aktion();
      if (mounted) zeigeMeldung(context, fertig);
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    } finally {
      if (mounted) setState(() => _laeuft.remove(schluessel));
    }
    await _laden(still: true);
  }

  Future<void> _geteiltAbmelden(GeteiltesTelefon t) async {
    if (!await frage(context, 'Abmelden?', 'Am geteilten Telefon ${t.name} abmelden?', ja: 'Abmelden')) return;
    await _tun('g:${t.ext}', () => widget.api.geteiltAbmelden(t.ext), 'Am Telefon ${t.name} abgemeldet.');
  }

  Future<void> _klingeln(GeteiltesTelefon t) async {
    setState(() => _laeuft.add('k:${t.ext}'));
    try {
      await widget.api.klingeln(t.ext);
      if (mounted) zeigeMeldung(context, '${t.name} klingelt jetzt bis zu 45 Sekunden.');
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
      if (mounted) setState(() => _laeuft.remove('k:${t.ext}'));
      return;
    }
    // bis 60 s nachfragen, ob am Telefon "Gefunden" getippt wurde
    for (var i = 0; i < 20 && mounted; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final s = await widget.api.klingelnStand(t.ext);
        if (s.gefunden != null && mounted) {
          final z = s.gefunden!;
          zeigeMeldung(context,
              'Gefunden um ${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')}${s.von != null ? ' (${s.von})' : ''}.');
          break;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _laeuft.remove('k:${t.ext}'));
  }

  Future<void> _abmelden(Handy h, List<Anmeldung> es, String was) async {
    final nachricht = es.any((e) => e.quelle == Quelle.messenger)
        ? ' Der Messenger löscht dort beim nächsten Kontakt seine Chats.'
        : '';
    final telefon = es.any((e) => e.quelle == Quelle.telefon) ? ' Deine Nummer klingelt dort dann nicht mehr.' : '';
    if (!await frage(context, 'Abmelden?', '$was auf ${h.name} abmelden?$telefon$nachricht Neu anmelden geht jederzeit in der App.',
        ja: 'Abmelden', gefaehrlich: es.length > 1)) {
      return;
    }
    final fehler = <String>[];
    setState(() => _laeuft.add(h.schluessel));
    for (final e in es) {
      try {
        await widget.api.abmelden(e);
      } catch (f) {
        fehler.add('${e.appName}: ${fehlerText(f)}');
      }
    }
    if (!mounted) return;
    setState(() => _laeuft.remove(h.schluessel));
    zeigeMeldung(context, fehler.isEmpty ? '$was abgemeldet.' : fehler.join(' · '), fehler: fehler.isNotEmpty);
    await _laden(still: true);
  }

  void _telefonAnmelden() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Am Telefon anmelden')),
          body: RosenwegInhalt(child: AnmeldeQrSeite(api: widget.api, nur: QrArt.telefon)),
        ),
      ));

  void _handyVerbinden() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _HandyVerbinden(api: widget.api),
      );

  @override
  Widget build(BuildContext context) {
    final geteilt = _geteilt;
    if (_fehler != null && geteilt == null) return FehlerAnzeige.aus(_fehler!, nochmals: _laden);
    if (geteilt == null) return const LadeAnzeige();
    final t = Theme.of(context).textTheme;
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Abschnitt(
            titel: 'Geteilte Telefone',
            symbol: Icons.phone_android_outlined,
            erklaerung: 'Hier bist du gerade angemeldet. Deine Nummer klingelt dort mit.',
            aktion: _darf
                ? TextButton.icon(
                    key: const Key('telefon-anmelden'),
                    onPressed: _telefonAnmelden,
                    icon: const Icon(Icons.login),
                    label: const Text('Anmelden'))
                : null,
            kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!_darf)
                const Hinweis('Dein Konto ist für geteilte Telefone nicht freigeschaltet. Melde dich bei der Technik.')
              else if (geteilt.isEmpty)
                Text('An keinem geteilten Telefon angemeldet. Anmelden: Rosenweg-Karte hinten ans Telefon halten '
                    'oder „Anmelden“ tippen und den Anmelde-QR zeigen.', style: t.bodyMedium?.copyWith(color: grau)),
              for (final g in geteilt)
                ListTile(
                  key: Key('geteilt-${g.ext}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_android),
                  title: Text(g.name),
                  subtitle: Text('Nebenstelle ${g.ext}${g.seit != null ? ' · seit ${zeitKurz(g.seit)}' : ''}'),
                  trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    IconButton(
                      tooltip: 'Klingeln lassen (Telefon verlegt?)',
                      onPressed: _laeuft.contains('k:${g.ext}') ? null : () => _klingeln(g),
                      icon: const Icon(Icons.notifications_active_outlined),
                    ),
                    OutlinedButton(
                      onPressed: _laeuft.contains('g:${g.ext}') ? null : () => _geteiltAbmelden(g),
                      child: const Text('Abmelden'),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Abschnitt(
            titel: 'Eigene Handys',
            symbol: Icons.smartphone_outlined,
            erklaerung: 'Rosenweg-Apps auf deinen Handys, je Handy einmal.',
            aktion: TextButton.icon(
                key: const Key('handy-verbinden'),
                onPressed: _handyVerbinden,
                icon: const Icon(Icons.add),
                label: const Text('Verbinden')),
            kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_handys.isEmpty)
                Text('Auf keinem eigenen Handy angemeldet. Mit „Verbinden“ klingelt deine Nummer auch auf deinem Handy.',
                    style: t.bodyMedium?.copyWith(color: grau)),
              for (final h in _handys) _HandyKarte(handy: h, beschaeftigt: _laeuft.contains(h.schluessel), abmelden: _abmelden),
              if (_fehlt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Hinweis('Nicht erreichbar, fehlt darum hier: ${_fehlt.join(', ')}.', art: HinweisArt.warnung),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

class _HandyKarte extends StatelessWidget {
  const _HandyKarte({required this.handy, required this.beschaeftigt, required this.abmelden});
  final Handy handy;
  final bool beschaeftigt;
  final Future<void> Function(Handy h, List<Anmeldung> es, String was) abmelden;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = Theme.of(context).colorScheme;
    final h = handy;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.smartphone, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(h.name, style: t.titleSmall)),
            Text('${h.apps.length} ${h.apps.length == 1 ? 'App' : 'Apps'}', style: t.bodySmall?.copyWith(color: f.onSurfaceVariant)),
          ]),
          if (h.vermutlich)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Vermutlich dasselbe Handy (gleiches Modell) – ältere App-Versionen melden noch keine Gerätekennung.',
                  style: t.bodySmall?.copyWith(color: RosenwegFarben.warnung)),
            ),
          for (final a in h.apps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: a.app == Anmeldung.telefonApp
                  ? Icon(Icons.circle,
                      size: 12,
                      color: a.anmeldungen.any((e) => e.verbunden == true) ? RosenwegFarben.gut : f.outlineVariant,
                      semanticLabel: a.anmeldungen.any((e) => e.verbunden == true) ? 'verbunden' : 'nicht verbunden')
                  : const SizedBox(width: 12),
              minLeadingWidth: 12,
              title: Text(a.name),
              subtitle: Text(a.anmeldungen.map((e) => e.zeile).where((z) => z.isNotEmpty).join('\n')),
              trailing: OutlinedButton(
                onPressed: beschaeftigt ? null : () => abmelden(h, a.anmeldungen, a.name),
                child: const Text('Abmelden'),
              ),
            ),
          if (h.apps.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: f.error),
                onPressed: beschaeftigt ? null : () => abmelden(h, h.anmeldungen, 'Alle Apps'),
                child: const Text('Alle Apps auf diesem Handy abmelden'),
              ),
            ),
        ]),
      ),
    );
  }
}

/// "Verbinden": wie man das eigene Handy dazunimmt. Kurz, drei Schritte.
class _HandyVerbinden extends StatelessWidget {
  const _HandyVerbinden({required this.api});
  final MeinTelefonApi api;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget schritt(int n, String text) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, child: Text('$n')),
          title: Text(text),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Dein Handy verbinden', style: t.titleLarge),
          const SizedBox(height: 8),
          schritt(1, 'Auf dem Handy die Apps-Seite öffnen und „Rosenweg Telefon“ installieren (Android).'),
          schritt(2, 'Die App öffnen und „Mit Rosenweg-Konto anmelden“ tippen – oder die Rosenweg-Karte hinten ans Handy halten.'),
          schritt(3, 'Fertig: das Handy erscheint unter „Eigene Handys“ und deine Nummer klingelt dort mit.'),
          const SizedBox(height: 4),
          Text('Fragt die App, ob sie im Hintergrund laufen darf, mit Ja antworten – sonst klingelt es nach ein paar '
              'Minuten nicht mehr. Rosenweg Telefon telefoniert nur in der eigenen App und greift nicht in deine '
              'normalen Anrufe ein.', style: t.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://www.rosenweg4303.ch/apps'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Apps-Seite öffnen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Anmelde-QR für eine App')),
                  body: RosenwegInhalt(child: AnmeldeQrSeite(api: api, nur: QrArt.app)),
                ),
              ));
            },
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Andere App mit QR anmelden'),
          ),
        ]),
      ),
    );
  }
}
