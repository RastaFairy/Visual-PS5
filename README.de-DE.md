# Visual-PS5 — PS5 Homebrew Studio 1.1.0

Lokale visuelle IDE für Windows zum Entwerfen von Oberflächen, Verwalten von Projekten, Prüfen von Code, Generieren von C++20-UI und Steuern von Builds mit Community-Toolchains für PS5.

**Sprachstatus:** Die Oberfläche bleibt auf Spanisch. Das deutsche Handbuch ist verfügbar; die UI-Übersetzung wird separat umgesetzt.

## Dokumentation

- [Deutsches Benutzerhandbuch](docs/USER-MANUAL.de-DE.md)
- [Spanisches Handbuch](docs/MANUAL.es-ES.md)
- [Englisches Handbuch](docs/USER-MANUAL.en-GB.md)
- [Französisches Handbuch](docs/USER-MANUAL.fr-FR.md)
- [Handbuch auf vereinfachtem Chinesisch](docs/USER-MANUAL.zh-CN.md)
- [Japanisches Handbuch](docs/USER-MANUAL.ja-JP.md)
- [Russisches Handbuch](docs/USER-MANUAL.ru-RU.md)
- [Credits und Upstream-Zuordnungen](docs/CREDITS.md)
- [SDK- und Upstream-Projektmatrix](release/UPSTREAM-SDK-MATRIX.md)
- [Änderungsprotokoll](docs/CHANGELOG.md)

## Schnellstart

1. Lade das Paket für den gewünschten Branch herunter oder erstelle es.
2. Entpacke es unter Windows 10/11 in einen beschreibbaren Ordner.
3. Starte start.bat und öffne bei Bedarf http://127.0.0.1:47813/.

PowerShell 7 wird empfohlen; Windows PowerShell 5.1 wird ebenfalls unterstützt. Native Builds benötigen Git, WSL/Linux und die Abhängigkeiten der gewählten Vorlage. Der Dienst lauscht nur auf 127.0.0.1.

Laut Maintainer wurde ein .ffpfsc-Abbild erfolgreich auf echter Hardware getestet; dies garantiert nicht jeden Titel und jede Firmware. Visual-PS5 ist kein offizielles Sony-SDK und enthält keine proprietären Dateien, Firmware, Schlüssel, Spiele oder BIOS.