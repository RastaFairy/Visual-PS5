# Benutzerhandbuch — PS5 Homebrew Studio 1.1.5

Letzte Aktualisierung: 16. Oktober 2026. Die Anwendungsoberfläche ist weiterhin auf Spanisch. Das übersetzte Handbuch bedeutet nicht, dass die UI bereits lokalisiert ist.

## 1. Voraussetzungen

Zum Starten werden Windows 10/11 und Lese-/Schreibrechte für den Anwendungsordner benötigt. PowerShell 7 wird empfohlen; Windows PowerShell 5.1 wird ebenfalls unterstützt.

Zum Kompilieren braucht man Git, WSL/Linux und die Upstream-Abhängigkeiten des gewählten Backends. SharpProspero/C# benötigt die von der installierten Revision verlangte .NET-Version. Native C++-Vorlagen benötigen kompatible Toolchains. UltraPack benötigt Python 3.10 oder neuer und das Repository [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack).

## 2. Installation und Start

1. Lade das Paket für den zu testenden Branch herunter oder baue es.
2. Entpacke es in einen beschreibbaren Ordner, nicht in einen geschützten Windows-Pfad.
3. Starte start.bat und lasse das PowerShell-Fenster geöffnet.
4. Falls der Browser nicht startet, öffne http://127.0.0.1:47813/.
5. Beende den Dienst durch Schließen des Serverfensters oder mit STOP.bat.

Der Dienst bindet ausschließlich an 127.0.0.1. Stelle ihn nicht im Netzwerk bereit und ändere die Adresse nicht auf 0.0.0.0. Projekte werden standardmäßig unter Documents/PS5HomebrewStudio/Projects gespeichert.

## 3. Oberfläche und visuelles Projekt

Die Arbeitsfläche beginnt mit 1920×1080 und kann in der Größe geändert werden. Sie ist ein virtueller Bereich, kein exakter Screenshot der PS5-Systemoberfläche. Füge Steuerelemente über die Komponentenpalette hinzu, bearbeite Geometrie und Eigenschaften im Inspektor, ordne Elemente in der Hierarchie und strukturiere die UI über die Bildschirmverwaltung. Der Flow-Editor verbindet Ereignisse mit Aktionen wie notify, setText, toggleVisibility, setValue, changeColor und navigate, sofern Komponente und Backend dies unterstützen.

Erstelle das Projekt, wähle das Backend vor der Einrichtung der Abhängigkeiten, füge Komponenten und Ressourcen hinzu, verwende eindeutige IDs und richte Bildschirme ein. Führe die Diagnose aus und korrigiere ungültige Referenzen. Speichere mit Ctrl+S. Ein Modell- oder ZIP-Export ist kein nativer Build.

## 4. Backends und Build

**SharpProspero / C#:** verwendet die echte Upstream-Buildpipeline und .NET/NativeAOT. Prüfe die von deinem Commit verlangte .NET-Version.

**Native OpenGL / C++20:** erzeugt einen Bildschirm gemäß dem ps5-homebrew-ui-Vertrag. Bilder werden in RGBA8 konvertiert, auf 512×512 Pixel und 16 eindeutige Textur-IDs pro Bildschirm begrenzt.

**Vulkan/RADV / C++20:** erstellt einen Titel mit PS5_VulkanTemplate und integriert die UI in das passende Vulkan-Modul. Kompatible Revisionen von PS5_Vulkan, PS5_Mesa/RADV, PS5_PayloadSDK und PS5_VKHomebrewUI werden benötigt.

Das IDE führt echte Upstream-Skripte aus und bewahrt Logs auf. Exit-Code null reicht nicht: Für die Paketierung müssen eboot.bin und sce_sys/param.json vorhanden sein. Das IDE liefert keine proprietären Sony-SDKs mit und garantiert keine universelle Firmware-Kompatibilität.

## 5. Präsentationsressourcen einer nativen App

Öffne unter **Projekte** einen initialisierten Titel mit `sce_sys/param.json` und klicke auf **Presentación**. Leere Felder bleiben unverändert.

- **Symbol:** `sce_sys/icon0.png`, PNG mit 512×512 Pixeln.

- **Auswahlhintergrund:** `sce_sys/pic0.dds`. **Start-/Ladehintergrund:** `sce_sys/pic1.dds`. Beide werden in DDS BC7/DX10 mit 3840×2160 Pixeln konvertiert und dürfen verschieden sein. Fehlen beide, wähle beim ersten Mal beide Dateien aus. Benötigt DirectXTex `texconv` (`winget install Microsoft.DirectXTex.Texconv`).

- **Auswahlmusik:** `sce_sys/snd0.at9`, gelooptes ATRAC9 mit 48 kHz, höchstens 2 MiB. Eine kompatible AT9-Datei kann direkt verwendet werden. WAV/MP3/FLAC/AIFF/AIFC werden offline mit dem enthaltenen Open-Source-Encoder konvertiert; FFmpeg und `ps4_at9tool.exe` sind nicht erforderlich. Lizenz GPL-3.0-or-later und Hinweise unter `toolchains/ps5-at9-converter/` beachten.

Das Upstream-Skript `tools/prepare-assets.ps1` validiert Formate vor dem Anwenden. Diese Dateien ändern nur die Präsentation dieser App, nicht den globalen PS5-Hintergrund oder den Startton der Konsole. Für ein separates Systemthema siehe [ps5-theme](https://github.com/Blaze414/ps5-theme).

## 6. Paketierung mit UltraPack

1. Öffne Werkzeuge und konfiguriere Python 3.10+ sowie die Datei backend/cli.py von UltraPack.
2. Speichere die Einstellungen lokal in .runtime/integrations.json.
3. Wähle ein gebautes natives Projekt und klicke auf Paketieren.
4. Wähle .ffpfs, .ffpfsc oder .pkg. Unter Windows braucht .pkg einen nativen Helper und dessen Abhängigkeiten.
5. Lasse „Inhalt mit Quelle vergleichen“ aktiviert, damit --verify übergeben wird. Die Prüfung kann mehr Laufzeit und Speicher beanspruchen.
6. Prüfe Abschlusslog, Exit-Code, Ausgabepfad und Warnungen. Ein altes Artefakt beweist nicht den Erfolg des aktuellen Laufs.

Ausgaben werden unter packages-ultrapack nach Format und Zeitstempel sortiert. Die Aufgabe läuft im Hintergrund. Laut Maintainer wurde ein .ffpfsc-Abbild erstellt und erfolgreich auf echter Hardware getestet; dies garantiert nicht jedes Spiel, jede Firmware oder jedes Backend.

## 7. Tests und Fehlerbehebung

Führe mit installiertem Node.js im Anwendungsordner node --check app.js, node --check runtime/native-generator.js und node runtime/test-native-generator.js aus. Diese Tests prüfen JavaScript und Generatorfälle, ersetzen aber keinen Build mit der vollständigen PS5-Toolchain oder einen Konsolentest.

Wenn der Server nicht startet, sichere die Fehlermeldung und prüfe PowerShell und Berechtigungen. Bei Build-Fehlern notiere Backend, Upstream-Versionen und Commits, vollständige Ausgabe und Exit-Code. Bei UltraPack prüfe Python/cli.py, eboot.bin, sce_sys/param.json und Schreibrechte. Teile keine Geheimnisse.


### WSL-Fehler: chmod auf .git/config.lock

Wenn das Protokoll `chmod on /mnt/d/.../.git/config.lock failed: Operation not permitted` oder `could not set 'core.filemode' to 'false'` enthält, wurde ein Windows-Laufwerk in WSL ohne die Option `metadata` eingebunden. Die IDE erkennt dies vor dem SDK-Build und zeigt die Reparaturschritte an.

Öffne die WSL-Distribution und führe das mit der IDE gelieferte Skript aus (Pfad an den tatsächlichen Installationsort anpassen):

```bash
sudo bash /mnt/d/PS5-Homebrew-Studio/runtime/fix-wsl-permissions.sh
```

Das Skript sichert `/etc/wsl.conf` und aktualisiert `[automount] options`, ohne andere Einstellungen zu entfernen. Beende WSL, führe in der Windows-PowerShell `wsl --shutdown` aus, starte die Distribution erneut und wiederhole den Build. Der Befehl beendet alle laufenden WSL-Distributionen; speichere vorher deine Arbeit. Starte Git oder die IDE nicht als Administrator. Siehe die [ausführliche WSL-Berechtigungsanleitung](WSL_PERMISSIONS.md) und die [Microsoft-Dokumentation](https://learn.microsoft.com/windows/wsl/file-permissions).
## 8. Lizenzen und Grenzen

SDKs, Treiber, Vorlagen und UI-Kits behalten ihre eigenen Lizenzen. Prüfe LICENSE, COPYING, NOTICE und die Weitergabebedingungen vor der Veröffentlichung. Visual-PS5 ist kein offizielles Sony-SDK, enthält keine Firmware, Schlüssel, Spiele oder BIOS und installiert Titel nicht automatisch. Die Vorschau ist kein PS5-Emulator und validiert weder Laufzeit noch Audio, Eingabe oder Persistenz.
