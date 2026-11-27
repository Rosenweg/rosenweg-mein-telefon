<p align="center"><img src="assets/logo/rosenweg-mein-telefon-512.png" width="96" alt="Logo"></p>
<h1 align="center">Rosenweg Mein Telefon</h1>
<p align="center">Deine Rosenweg-Nummer einstellen: Weiterleitung, Voicemail, Geräte, Anmelde-QR für geteilte Telefone und Apps.</p>
<p align="center"><a href="docs/anleitung.md">Anleitung</a> · <a href="https://www.rosenweg4303.ch/apps">Herunterladen</a></p>

Angelegt mit `werkzeug/neue-app.sh` aus der App-Vorlage von
[rosenweg-basis](https://github.com/Rosenweg/rosenweg-basis). Anmeldung, API,
Gerüst, Updater und Logo kommen aus der Basis; hier steht nur, was diese App
eigen macht.

## Läuft auf

| Plattform | Datei | Grenzen |
|---|---|---|
| Linux (Debian 13, Stationen und eigene Rechner) | `rosenweg-mein-telefon_<version>_amd64.deb` | Stationen bekommen das Paket vom PXE-Server (os-stationen), dort ist der Updater aus |
| Android 8 und neuer | `rosenweg-mein-telefon-<version>.apk` (Rosenweg-Schlüssel) | auf geteilten Telefonen meldet Rosenweg Gerät an und ab |
| Windows 10/11 | `Rosenweg-Mein-Telefon-<version>-Setup.exe` | unsigniert, solange kein Code-Signing-Zertifikat da ist (SmartScreen fragt einmal) |
| macOS 11 und neuer | `Rosenweg-Mein-Telefon-<version>.dmg` | ohne Apple Developer ID ad hoc signiert (Gatekeeper fragt beim ersten Start) |
| iOS/iPadOS | – | baut in CI ohne Signatur, verteilt wird erst mit dem Apple Developer Program |

Herunterladen: [www.rosenweg4303.ch/apps](https://www.rosenweg4303.ch/apps).

## Bedienung

Für alle mit einer Rosenweg-Nummer. Abgrenzung: **Rosenweg Telefon** (Fossify)
telefoniert, **Rosenweg Mein Telefon** stellt ein. Drei Bereiche (Handy unten,
Computer links), für Technik und Präsident ein vierter:

| Bereich | Was | Web-Vorbild |
|---|---|---|
| Nummer | eigene Nummer (kopieren), Erreichbarkeit: keine / bei Nichtabnehmen nach x s / immer weiterleiten, Zielnummer, Voicemail; Gruppen (z. B. Ring-Group Technik) | `mein-telefon.html` |
| Geräte | geteilte Telefone, an denen man angemeldet ist (klingeln lassen, abmelden, „Anmelden“ → Anmelde-QR); eigene Handys je Handy einmal mit ihren Rosenweg-Apps (Telefon, Messenger, Karten-/QR-Sitzungen), einzeln oder alle abmelden; „Verbinden“ erklärt Rosenweg Telefon aufs eigene Handy | `mein-telefon.html`, `smartphones.html` („Hier bist du angemeldet“, `js/meine-geraete.js`) |
| Anmelde-QR | Code für ein geteiltes Telefon (Sperrbildschirm) oder für eine Rosenweg-App auf dem eigenen Handy; gilt einmal und kurz, wird von selbst erneuert; meldet, welche App ihn eingelöst hat | `pbx/web/telefon.html`, `smartphones.html` |
| Alle Handys (Technik, Präsident) | alle eigenen Handys mit Rosenweg Telefon (`<nummer>-p<id>`), Zugang sperren | `smartphones.html` |

Auf einem **geteilten Telefon** zeigt die App nur einen Hinweis: Rosenweg Gerät
reicht Anfragen nur an die Haupt-API weiter, die Telefonanlage ist von dort nicht
erreichbar; an- und abmelden macht das Telefon selbst. Auf eigenen Handys greift
die App nicht ins Android-Telefon ein (kein Telecom-Framework).

Ausführlich: [docs/anleitung.md](docs/anleitung.md).

## API

Zwei Dienste, beide mit dem Zugang der Anmeldung (Konto, Karte, QR, Kerberos).
Die Telefonanlage prüft das Token über `GET /api/auth/me` der Haupt-API, darum
gilt jede Anmeldung der Basis auch dort (`lib/mein_telefon_api.dart`).

| Dienst | Pfad | wofür |
|---|---|---|
| Telefonanlage `pbx.rosenweg4303.ch` | `GET /api/telefon/ich`, `PUT /api/telefon/ich/erreichbarkeit` | Nummer, Erreichbarkeit, Gruppen |
| | `GET /api/telefon/meine`, `DELETE /api/telefon/privat/:id` | geteilte Telefone, Handys mit Rosenweg Telefon |
| | `POST /api/telefon/:ext/abmelden`, `POST`/`GET /api/telefon/:ext/suchen` | am geteilten Telefon abmelden, klingeln lassen |
| | `POST /api/telefon/ausweis` | Anmelde-QR für geteilte Telefone (RWTEL1) |
| | `GET /api/pbx/sip-privat`, `DELETE /api/pbx/sip-privat/:id` | Technik: alle Handy-Zugänge |
| Haupt-API `rosenweg4303.ch` | `POST /api/apps/qr-ausweis`, `GET /api/apps/qr-ausweis/:id` | Anmelde-QR für Apps (RWAPP1; nur mit Rosenweg-Konto, nicht mit Karte) |
| | `GET /api/messenger/zugaenge`, `DELETE /api/messenger/zugaenge/:id` | Rosenweg Messenger auf eigenen Handys |
| | `GET /api/apps/sitzungen`, `DELETE /api/apps/sitzungen/:id` | Karten-/QR-/Handy-Sitzungen der Apps |

## Entwickeln

```sh
# rosenweg-basis daneben auschecken, dann lokal gegen sie bauen:
printf 'dependency_overrides:\n  rosenweg_basis:\n    path: ../rosenweg-basis\n' > pubspec_overrides.yaml
flutter pub get
flutter run -d macos                       # oder linux, windows, ein Handy
flutter run -d macos --dart-define=RW_ATTRAPPE=1   # ohne Server, mit Vorführdaten (lib/attrappe.dart)
flutter analyze && flutter test
RW_FOTO=$HOME/Downloads flutter test test/bildschirmfoto_test.dart   # Bildschirmfotos
```

Vor dem Commit `pubspec_overrides.yaml` entfernen und `flutter pub get` laufen lassen –
`pubspec.lock` darf nicht auf `../rosenweg-basis` zeigen (die CI bricht sonst ab).

| Ordner | Inhalt |
|---|---|
| `lib/app.dart` | `RosenwegApp`: Kennung `ch.rosenweg4303.meintelefon`, Name, Logo |
| `lib/seiten/` | die Seiten der App (`RosenwegGeruest`: Handy unten, Desktop links) |
| `lib/attrappe.dart` | Vorführdaten statt der API (Tests, Bildschirmfotos) |
| `assets/logo/` | Logo aus dem Baukasten der Basis: `sh assets/logo/erzeugen.sh ../rosenweg-basis` |
| `linux/paket/` | Debian-Paket (`bauen.sh`, im Bau-Container `im-container.sh`), `paket.conf` = Vorlage für os-stationen |
| `macos/installer/` | DMG (`bauen.sh`) |
| `windows/installer/` | Inno-Setup-Installer |
| `.github/workflows/` | `app.yml` (Bau, Release) und `apps.yml` (an /apps) – die Arbeit macht rosenweg-basis |

## Veröffentlichen

1. Version in `pubspec.yaml` erhöhen (`version: x.y.z+n`, Baunummer immer mit).
2. Pull Request, CI grün (Linux und Android), Merge auf main.
3. Die CI baut alle fünf Plattformen, legt das Release `vx.y.z` an und schickt
   APK, `.deb`, DMG und Installer an `/apps`. Ohne neue Version passiert nach dem
   Merge nur die CI.
4. Stationen: `linux/paket/paket.conf` in os-stationen (`pakete/rosenweg-mein-telefon/`)
   mit Version und Prüfsumme nachführen.

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE). Logo-Zeichen: siehe rosenweg-basis
`werkzeug/logo/zeichen/LIZENZEN.md`.
