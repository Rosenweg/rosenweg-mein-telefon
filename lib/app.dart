// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/painting.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Angaben der App fuer rosenweg_basis.
///
/// kennung = applicationId (Android) = Bundle-ID (iOS/macOS) = GTK-ID (Linux)
/// = Schema des Ruecksprungs (ch.rosenweg4303.meintelefon:/anmeldung, in Authentik
/// bei rosenweg-apps eintragen) = Paket im App-Katalog (/apps, Updater).
const appAngaben = RosenwegApp(
  kennung: 'ch.rosenweg4303.meintelefon',
  name: 'Rosenweg Mein Telefon',
  ordner: 'rosenweg-mein-telefon',
  beschreibung: 'Deine Rosenweg-Nummer einstellen: Weiterleitung, Voicemail, Geräte, Anmelde-QR für geteilte Telefone und Apps.',
  quelle: 'https://github.com/Rosenweg/rosenweg-mein-telefon',
  logo: AssetImage('assets/logo/rosenweg-mein-telefon-512.png'),
  // Farbe des Anmeldeschirms wie der Logo-Grund (assets/logo/erzeugen.sh GRUPPE);
  // neue-app.sh setzt sie aus werkzeug/logo/flutter-apps.txt
  gruppe: RosenwegGruppe.bewohner,
);

/// --dart-define=RW_ATTRAPPE=1: ohne Anmeldung und ohne Server, mit
/// erfundenen Vorfuehrdaten (Entwicklung, Bildschirmfotos, Tests).
const attrappe = bool.fromEnvironment('RW_ATTRAPPE');

/// Telefonanlage (pbx/api/app.py der Website, CT 220): Nummer, Erreichbarkeit,
/// Geraete, Anmelde-QR fuer geteilte Telefone. Sie prueft das Token der
/// Anmeldung ueber `/api/auth/me` der Haupt-API.
const telefonanlage = 'https://pbx.rosenweg4303.ch';
