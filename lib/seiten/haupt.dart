// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../mein_telefon_api.dart';
import 'alle_handys.dart';
import 'anmelde_qr.dart';
import 'geraete.dart';
import 'nummer.dart';

/// Die App nach der Anmeldung. Drei Bereiche (Handy unten, Computer links),
/// fuer Technik und Praesident ein vierter:
///
///  * Nummer: die eigene Rosenweg-Nummer, Erreichbarkeit (Weiterleitung,
///    Voicemail), Gruppen – wie mein-telefon.html
///  * Geräte: geteilte Telefone, an denen man angemeldet ist (klingeln
///    lassen, abmelden), eigene Handys mit ihren Rosenweg-Apps (abmelden) –
///    wie der Teil "Hier bist du angemeldet" von smartphones.html
///  * Anmelde-QR: fuer ein geteiltes Telefon oder eine App auf dem eigenen
///    Handy – wie pbx/web/telefon.html und smartphones.html
///  * Alle Handys (nur Technik/Praesident): alle Handys mit Rosenweg Telefon,
///    Zugang sperren (Handy verloren)
///
/// Telefoniert wird in Rosenweg Telefon; diese App stellt nur ein.
class Haupt extends StatefulWidget {
  const Haupt({super.key, required this.sitzung, this.anlage});
  final RosenwegSitzung sitzung;

  /// Tests, Bildschirmfotos, Attrappe: Transport fuer die Telefonanlage
  /// (sonst direkt mit dem Zugang der Anmeldung).
  final Transport? anlage;

  @override
  State<Haupt> createState() => _HauptState();
}

class _HauptState extends State<Haupt> {
  late final MeinTelefonApi _api = MeinTelefonApi.fuer(widget.sitzung, transport: widget.anlage);

  @override
  void initState() {
    super.initState();
    // Rechte nur fuer den Technik-Bereich "Alle Handys" (nicht auf geteilten Telefonen)
    if (!widget.sitzung.geteiltesTelefon) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.sitzung.rechte.laden().ignore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sitzung;
    final logo = Padding(
      padding: const EdgeInsets.all(10),
      child: FarbLogo(sitzung: s, klein: true),
    );
    return ListenableBuilder(
      listenable: s.rechte,
      builder: (context, _) => RosenwegGeruest(
        titel: Text(s.app.name),
        logo: logo,
        aktionen: [_Menue(sitzung: s)],
        ziele: [
          GeruestZiel(
            titel: 'Nummer',
            symbol: Icons.dialpad_outlined,
            gewaehltSymbol: Icons.dialpad,
            seite: (_) => NummerSeite(api: _api),
          ),
          GeruestZiel(
            titel: 'Geräte',
            symbol: Icons.devices_outlined,
            gewaehltSymbol: Icons.devices,
            seite: (_) => GeraeteSeite(api: _api),
          ),
          GeruestZiel(
            titel: 'Anmelde-QR',
            symbol: Icons.qr_code_2_outlined,
            gewaehltSymbol: Icons.qr_code_2,
            // geteiltes Telefon: nur der Code fuer ein (anderes) geteiltes Telefon; ein App-QR
            // braucht das Rosenweg-Konto (die Haupt-API gibt ihn mit dem Anlage-Token nicht aus)
            seite: (_) => AnmeldeQrSeite(api: _api, nur: s.geteiltesTelefon ? QrArt.telefon : null),
          ),
          // Technik-Liste nicht auf geteilten Telefonen (dort nur fuer die Person am Telefon).
          // Spaeter in "Rosenweg Geteilte Telefone" (Stefan 27.11.2026).
          if (s.rechte.stand?.alles == true && !s.geteiltesTelefon)
            GeruestZiel(
              titel: 'Alle Handys',
              symbol: Icons.admin_panel_settings_outlined,
              gewaehltSymbol: Icons.admin_panel_settings,
              seite: (_) => AlleHandysSeite(api: _api),
            ),
        ],
      ),
    );
  }
}

/// Menue oben rechts: Anmeldung (echter Stand), Ueber, Abmelden (nicht auf
/// geteilten Telefonen – dort meldet Rosenweg Geraet ab).
class _Menue extends StatelessWidget {
  const _Menue({required this.sitzung});
  final RosenwegSitzung sitzung;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Mehr',
        onSelected: (w) async {
          switch (w) {
            case 'anmeldung':
              await zeigeAnmeldung(context, sitzung);
            case 'ueber':
              await zeigeUeber(context, sitzung.app);
            case 'abmelden':
              if (await frage(context, 'Abmelden?', 'Danach musst du dich neu anmelden.', ja: 'Abmelden')) {
                await sitzung.abmelden();
              }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'anmeldung', child: Text('Anmeldung: ${sitzung.name ?? 'angemeldet'}')),
          PopupMenuItem(value: 'ueber', child: Text('Über ${sitzung.app.name}')),
          if (!sitzung.geteiltesTelefon) const PopupMenuItem(value: 'abmelden', child: Text('Abmelden')),
        ],
      );
}
