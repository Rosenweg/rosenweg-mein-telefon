// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../mein_telefon_api.dart';

/// Die eigene Rosenweg-Nummer: wer sie anruft, erreicht alle Geraete
/// gleichzeitig. Darunter die Erreichbarkeit (Weiterleitung, Voicemail) und
/// die Gruppen, in denen die Nummer mitklingelt.
class NummerSeite extends StatefulWidget {
  const NummerSeite({super.key, required this.api});
  final MeinTelefonApi api;

  @override
  State<NummerSeite> createState() => _NummerSeiteState();
}

class _NummerSeiteState extends State<NummerSeite> {
  MeineNummer? _ich;
  Object? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _fehler = null);
    try {
      final ich = await widget.api.ich();
      if (mounted) setState(() => _ich = ich);
    } catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ich = _ich;
    if (_fehler != null && ich == null) return FehlerAnzeige.aus(_fehler!, nochmals: _laden);
    if (ich == null) return const LadeAnzeige(text: 'Telefonanlage wird gefragt …');
    if (ich.nummer == null) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        Abschnitt(
          titel: 'Noch keine Rosenweg-Nummer',
          symbol: Icons.dialpad,
          kind: Text('Nummern bekommen alle, die mit E-Mail im Rosenweg eingetragen sind. '
              'Fehlt deine, melde dich bei der Technik.'),
        ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NummerKarte(ich: ich),
          const SizedBox(height: 12),
          ErreichbarkeitKarte(
            // neu aufbauen, wenn die Anlage einen anderen Stand meldet
            key: ValueKey(ich.erreichbarkeit),
            api: widget.api,
            stand: ich.erreichbarkeit,
            zuletzt: ich.zuletztZeit,
            zuletztDurch: ich.zuletztDurch,
            gespeichert: _laden,
          ),
          if (ich.gruppen.isNotEmpty) ...[
            const SizedBox(height: 12),
            Abschnitt(
              titel: 'Meine Gruppen',
              symbol: Icons.groups_outlined,
              erklaerung: 'Ändern kann das die Technik.',
              kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final g in ich.gruppen) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(g.satz)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _NummerKarte extends StatelessWidget {
  const _NummerKarte({required this.ich});
  final MeineNummer ich;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final nummer = ich.nummer!;
    return Abschnitt(
      titel: 'Deine Nummer',
      symbol: Icons.dialpad,
      aktion: IconButton(
        tooltip: 'Nummer kopieren',
        icon: const Icon(Icons.copy_outlined),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: nummer));
          if (context.mounted) zeigeMeldung(context, 'Nummer $nummer kopiert.');
        },
      ),
      kind: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(nummer,
            key: const Key('nummer'), style: t.displaySmall?.copyWith(fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()])),
        if (ich.wer.isNotEmpty) Text(ich.wer, style: t.bodyLarge),
        const SizedBox(height: 8),
        Text('Wer im Rosenweg diese Nummer wählt, erreicht dich auf allen deinen Geräten gleichzeitig – '
            'am eigenen Handy mit Rosenweg Telefon und an jedem geteilten Telefon, an dem du gerade angemeldet bist.',
            style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// Weiterleitung und Voicemail. "Speichern" geht erst, wenn etwas geaendert ist.
class ErreichbarkeitKarte extends StatefulWidget {
  const ErreichbarkeitKarte({
    super.key,
    required this.api,
    required this.stand,
    this.zuletzt,
    this.zuletztDurch,
    required this.gespeichert,
  });
  final MeinTelefonApi api;
  final Erreichbarkeit stand;
  final DateTime? zuletzt;
  final String? zuletztDurch;
  final Future<void> Function() gespeichert;

  @override
  State<ErreichbarkeitKarte> createState() => _ErreichbarkeitKarteState();
}

class _ErreichbarkeitKarteState extends State<ErreichbarkeitKarte> {
  /// Stand der Anlage, Sekunden auf die Auswahl gerundet (sonst gaelte er als geaendert).
  late final Erreichbarkeit _ausgang = widget.stand.mit(sekunden: widget.stand.sekundenGewaehlt);
  late Erreichbarkeit _e = _ausgang;
  late final _ziel = TextEditingController(text: widget.stand.ziel);
  String? _zielFehler;
  bool _speichert = false;

  bool get _geaendert => _e != _ausgang;

  @override
  void dispose() {
    _ziel.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    final e = _e.mit(ziel: _ziel.text.trim());
    if (e.weiterleitung != Weiterleitung.aus && e.ziel.isEmpty) {
      setState(() => _zielFehler = 'Bitte die Nummer angeben, an die weitergeleitet wird.');
      return;
    }
    setState(() {
      _zielFehler = null;
      _speichert = true;
    });
    try {
      await widget.api.erreichbarkeitSpeichern(e);
      if (!mounted) return;
      zeigeMeldung(context, 'Gespeichert – gilt ab dem nächsten Anruf.');
      await widget.gespeichert();
    } on ApiFehler catch (f) {
      // 400 der Anlage: meist die Zielnummer ("Zielnummer ungültig …")
      if (!mounted) return;
      if (f.status == 400 && f.text.toLowerCase().contains('ziel')) {
        setState(() => _zielFehler = f.text);
      } else {
        zeigeMeldung(context, fehlerText(f), fehler: true);
      }
    } catch (f) {
      if (mounted) zeigeMeldung(context, fehlerText(f), fehler: true);
    } finally {
      if (mounted) setState(() => _speichert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    final wl = _e.weiterleitung;
    final durch = widget.zuletztDurch;
    final zuletzt = widget.zuletzt == null
        ? null
        : 'Zuletzt geändert ${zeitKurz(widget.zuletzt)}${durch != null && durch != 'selbst' ? ' durch $durch' : ' von dir'}';

    Widget wahl(Weiterleitung w, String titel, String text) => RadioListTile<Weiterleitung>(
          key: Key('wl-${w.wert}'),
          value: w,
          contentPadding: EdgeInsets.zero,
          title: Text(titel),
          subtitle: Text(text),
        );

    return Abschnitt(
      titel: 'Erreichbarkeit',
      symbol: Icons.phone_forwarded_outlined,
      erklaerung: 'Was passiert, wenn jemand deine Nummer anruft. Gilt ab dem nächsten Anruf.',
      kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RadioGroup<Weiterleitung>(
          groupValue: wl,
          onChanged: (w) => setState(() => _e = _e.mit(weiterleitung: w)),
          child: Column(children: [
            wahl(Weiterleitung.aus, 'Keine Weiterleitung', 'Es klingelt nur auf deinen Geräten.'),
            wahl(Weiterleitung.nichtErreichbar, 'Weiterleiten, wenn ich nicht abnehme',
                'Zuerst klingeln deine Geräte, danach die Nummer unten – auch wenn gerade keines verbunden ist.'),
            wahl(Weiterleitung.immer, 'Immer weiterleiten', 'Deine Geräte klingeln nicht, nur die Nummer unten.'),
          ]),
        ),
        if (wl != Weiterleitung.aus) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('ziel'),
            controller: _ziel,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            onChanged: (z) => setState(() {
              _e = _e.mit(ziel: z);
              _zielFehler = null;
            }),
            decoration: InputDecoration(
              labelText: 'An Nummer',
              hintText: '079 123 45 67 oder +49 …',
              errorText: _zielFehler,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (wl == Weiterleitung.nichtErreichbar) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const Key('sekunden'),
            initialValue: _e.sekunden,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Weiterleiten nach', helperText: 'so lange klingeln zuerst deine Geräte', border: OutlineInputBorder()),
            items: [for (final s in Erreichbarkeit.sekundenWahl) DropdownMenuItem(value: s, child: Text('$s Sekunden'))],
            onChanged: (s) => setState(() => _e = _e.mit(sekunden: s)),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('voicemail'),
          contentPadding: EdgeInsets.zero,
          value: _e.voicemail,
          onChanged: (v) => setState(() => _e = _e.mit(voicemail: v)),
          title: const Text('Voicemail'),
          subtitle: const Text('Nimmt niemand ab, kann man dir eine Nachricht hinterlassen. Du hörst sie in '
              'Rosenweg Telefon. Nachrichten werden nach 90 Tagen gelöscht.'),
        ),
        const SizedBox(height: 4),
        Text('In Gruppen (z. B. Ring-Group Technik) gilt deine Weiterleitung, deine Voicemail nicht – sonst nähme '
            'sie den Anruf für die ganze Gruppe an. Anrufe an Nummern ausserhalb des Rosenwegs kosten die '
            'Gemeinschaft Gebühren.', style: t.bodySmall?.copyWith(color: grau)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            key: const Key('speichern'),
            onPressed: _geaendert && !_speichert ? _speichern : null,
            icon: _speichert
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Speichern'),
          ),
          if (_geaendert && !_speichert)
            TextButton(
              onPressed: () => setState(() {
                _e = _ausgang;
                _ziel.text = widget.stand.ziel;
                _zielFehler = null;
              }),
              child: const Text('Verwerfen'),
            ),
          if (zuletzt != null) Text(zuletzt, style: t.bodySmall?.copyWith(color: grau)),
        ]),
      ]),
    );
  }
}
