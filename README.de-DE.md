# Visual-PS5 — PS5 Homebrew Studio 1.1.7

Lokale visuelle IDE für Windows zum Entwerfen von Oberflächen, Verwalten von Projekten, Prüfen von Code, Generieren von C++20-UI und Steuern von Builds mit Community-Toolchains für PS5.

**Sprachstatus:** Die Oberfläche bleibt auf Spanisch. Das deutsche Handbuch ist verfügbar; die UI-Übersetzung wird separat umgesetzt.

## Neu in Version 1.1.7

- Importierte TrueType-Schriftdateien (`.ttf`) können als Unicode-Schrift für native Projekte gewählt werden. Das IDE erzeugt für OpenGL und Vulkan SDF-Atlanten für die tatsächlich verwendeten Codepoints; fehlende Glyphen führen zu einer klaren Build-Fehlermeldung.
- Die neue Regressionstests umfassen Kyrillisch, Griechisch, Japanisch, vereinfachtes/traditionelles Chinesisch und Koreanisch. Dies lokalisiert nicht die spanische IDE-Oberfläche und bietet noch keine CJK-Eingabemethode oder vollständige RTL-Formgebung.
- [Unicode-Schriftanleitung](docs/UNICODE-FONTS.en-GB.md)

- Die neue Ansicht **Struktur** trennt bearbeitbare visuelle Bildschirme von nativen C++-Menüzuständen. Sie bietet einen durchsuchbaren Baum, einen Übergangsgraphen, erkannte Menütexte und Sprünge zu Quellcodezeilen. C++-Übergänge werden statisch abgeleitet und sollten manuell überprüft werden.
- Die Aktionsschaltflächen in den Dialogen UltraPack und Präsentation wurden korrigiert.
- Native OpenGL-Builds von IDE-generierten Projekten verwenden das projektlokale `build.ps1` und dessen Abhängigkeiten. Dadurch entfällt die redundante Vorbereitung des gemeinsamen SDKs, die auf WSL/DrvFS ohne `metadata` fehlschlagen kann.
- Vor dem Build lassen sich App-Symbol, Auswahl-/Start-Hintergrund und Musik auswählen; außerdem gibt es Bildschirmverwaltung und eine Ebenenhierarchie pro Bildschirm.
- OpenGL-Kompilierung und UltraPack-Paketierung sind im Windows/WSL-Testsystem des Maintainers bestätigt. Vollständige Vulkan-Builds, ATRAC9-Konvertierung und Ausführung auf echter PS5-Hardware sind noch nicht verifiziert. Siehe [bekannte Probleme und Validierungsstatus](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md).

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
- [Bekannte Probleme und Validierungsstatus](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md)

## Schnellstart

1. Lade das Paket für den gewünschten Branch herunter oder erstelle es.
2. Entpacke es unter Windows 10/11 in einen beschreibbaren Ordner.
3. Starte `PS5-Homebrew-Studio/start.bat` und öffne bei Bedarf http://127.0.0.1:47813/.

PowerShell 7 wird empfohlen; Windows PowerShell 5.1 wird ebenfalls unterstützt. Native Builds benötigen Git, WSL/Linux und die Abhängigkeiten der gewählten Vorlage. Der Dienst lauscht nur auf 127.0.0.1.

Erfolgreiche Kompilierung und Paketierung beweisen noch nicht die Funktion auf einer physischen PS5; den aktuellen Validierungsstatus findest du in den bekannten Problemen. Visual-PS5 ist kein offizielles Sony-SDK und enthält keine proprietären Dateien, Firmware, Schlüssel, Spiele oder BIOS.