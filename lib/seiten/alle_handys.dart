// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../mein_telefon_api.dart';

/// Nur Technik und Praesident (die Anlage prueft es auch): alle eigenen Handys
/// mit Rosenweg Telefon (Zugang `<nummer>-p<id>`), z. B. Handy verloren →
/// Zugang sperren. Wie "Eigene Handys mit Rosenweg Telefon" in smartphones.html.
class AlleHandysSeite extends StatefulWidget {
  const AlleHandysSeite({super.key, required this.api});
  final MeinTelefonApi api;

  @override
  State<AlleHandysSeite> createState() => _AlleHandysSeiteState();
}

class _AlleHandysSeiteState extends State<AlleHandysSeite> {
  late final _liste = ListenSteuerung<SipZugang>.lokal(
    alle: widget.api.alleSipZugaenge,
    suchText: (z) => '${z.kennung} ${z.email ?? ''} ${z.geraet ?? ''}',
    schluessel: (z) => z.id,
    filter: [
      ListenFilter(id: 'verbunden', titel: 'Verbunden', passt: (z) => z.verbunden),
      ListenFilter(id: 'getrennt', titel: 'Nicht verbunden', passt: (z) => !z.verbunden),
    ],
    sortierer: {
      'kennung': (a, b) => a.kennung.compareTo(b.kennung),
      'seit': (a, b) => (a.seit ?? DateTime(2000)).compareTo(b.seit ?? DateTime(2000)),
    },
  );

  @override
  void dispose() {
    _liste.dispose();
    super.dispose();
  }

  Future<void> _sperren(SipZugang z) async {
    if (!await frage(context, 'Zugang sperren?',
        '${z.kennung} (${z.geraet ?? 'Handy'}, ${z.email ?? '–'}) sperren? Rosenweg Telefon auf diesem Handy klingelt dann nicht mehr; '
            'neu anmelden kann sich die Person jederzeit in der App.',
        ja: 'Sperren', gefaehrlich: true)) {
      return;
    }
    try {
      await widget.api.sipZugangSperren(z.id);
      if (mounted) zeigeMeldung(context, 'Zugang ${z.kennung} gesperrt.');
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    }
    await _liste.neuLaden();
  }

  Widget _punkt(BuildContext context, SipZugang z) => Icon(Icons.circle,
      size: 12,
      color: z.verbunden ? RosenwegFarben.gut : Theme.of(context).colorScheme.outlineVariant,
      semanticLabel: z.verbunden ? 'verbunden' : 'nicht verbunden');

  Widget _knopf(SipZugang z) => OutlinedButton(onPressed: () => _sperren(z), child: const Text('Sperren'));

  @override
  Widget build(BuildContext context) => RosenwegListe<SipZugang>(
        steuerung: _liste,
        suchHinweis: 'Zugang, E-Mail oder Gerät',
        leerText: 'Kein eigenes Handy mit Rosenweg Telefon.',
        kopf: const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Alle eigenen Handys mit Rosenweg Telefon. Sperren, wenn ein Handy verloren ging.'),
        ),
        spalten: [
          ListenSpalte(id: 'stand', titel: '', breite: 32, zelle: _punkt),
          ListenSpalte(id: 'kennung', titel: 'Zugang', text: (z) => z.kennung, flex: 2, sortierbar: true),
          ListenSpalte(id: 'person', titel: 'Person', text: (z) => z.email ?? '–', flex: 3),
          ListenSpalte(id: 'geraet', titel: 'Gerät', text: (z) => z.geraet ?? '–', flex: 2),
          ListenSpalte(id: 'seit', titel: 'Seit', text: (z) => zeitKurz(z.seit), flex: 2, sortierbar: true),
          ListenSpalte(id: 'aktion', titel: '', breite: 120, zelle: (_, z) => _knopf(z)),
        ],
        kachel: (context, z) => ListTile(
          leading: _punkt(context, z),
          title: Text('${z.kennung} · ${z.geraet ?? 'Handy'}'),
          subtitle: Text('${z.email ?? '–'}${z.seit != null ? ' · seit ${zeitKurz(z.seit)}' : ''}'),
          trailing: _knopf(z),
        ),
      );
}
