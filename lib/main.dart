// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'app.dart';
import 'attrappe.dart';
import 'seiten/haupt.dart';

/// rosenwegStarten (rosenweg_basis): Logdatei, Fehlerfang, Anmeldung
/// (Anmeldeschirm mit Karte, QR, Konto; an Stationen still per Kerberos;
/// auf geteilten Telefonen ueber Rosenweg Geraet) und der Updater
/// (aus auf Rosenweg-Stationen und mit Rosenweg Geraet). Erst danach kommt
/// [Haupt].
void main() {
  // Attrappe: Haupt-API und Telefonanlage aus derselben Vorfuehrung
  final vorfuehrung = attrappe ? Attrappe() : null;
  rosenwegStarten(
    appAngaben,
    (sitzung) => Haupt(sitzung: sitzung, anlage: vorfuehrung),
    sitzung: vorfuehrung != null ? RosenwegSitzung(appAngaben, transport: vorfuehrung) : null,
  );
}
