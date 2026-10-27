# Issue #10 — lokale OCR auf macOS und Windows

## Ausgangsstand und verbindlicher Umfang

- Basis: `origin/main`, Commit `2306fc6e8e357a64980c9674b273825f52e8844f`.
  Der Arbeitsbaum war sauber; kein Branchwechsel, Cherry-Pick oder Übernehmen
  von Code aus offenen PRs. Keine Commits, Pushes oder PR-Erstellung.
- Grundlage ist der vollständig im Auftrag bereitgestellte Issue-Text, insbesondere
  die strukturierten, geklärten Entscheidungen: beide Plattformen, macOS `⌘⇧6`,
  Windows `Ctrl+Shift+3`, automatische Sprachauswahl und gerendertes Editorbild.
  Die offenen Fragen der historischen Originalbeschreibung werden dadurch ersetzt.
- `CONTRIBUTING.md` gelesen. `AGENTS.md` und `CLAUDE.md` sind im Repository nicht vorhanden.
  Die Wissensbasis wurde zu Regeln und PR-Abhängigkeiten befragt, enthält hierzu
  aber nur den älteren allgemeinen Projektstand.
- **Nachweislücke:** Zugriff über `gh` wurde durch die Tool-Berechtigungen abgelehnt.
  Zusätzliche Issue-Kommentare und offene PRs konnten nicht gelesen/geprüft werden.
  Vor Review muss ein Maintainer den aktuellen Thread auf weitere verbindliche
  Entscheidungen und die PR-Liste auf Überschneidungen prüfen. Es besteht keine
  aus dem verfügbaren Code erkennbare Abhängigkeit von einem offenen PR; eine
  vollständige GitHub-seitige Abhängigkeitsprüfung steht aus. Windows-Texte folgen
  dem vorhandenen deutschen UI-Stil auf main.

## Umsetzung und Akzeptanzkriterien

| AC | Umsetzung / noch erforderlicher Nachweis |
| --- | --- |
| 1 | Dritter Hotkey und Menüeintrag auf beiden Plattformen. OCR-Auswahl schreibt zunächst kein Bild ins Clipboard. Nur nichtleerer OCR-Text wird veröffentlicht: macOS `.string` (`public.utf8-plain-text`), Windows `UnicodeText` (`CF_UNICODETEXT`). Reale Aufnahme und native Clipboard-Typen manuell prüfen. |
| 2 | Editor-Button verwendet das gerenderte Bild mit voller Pixelauflösung und Anmerkungen, bleibt nach dem Kopieren geöffnet. Erkannte Zeilen, die eine Verpixelungsfläche überlappen, werden zusätzlich verworfen, damit auch noch lesbare Pixelierung keinen Text preisgibt. Dabei entfällt vorsorglich die gesamte betroffene Zeile, einschließlich unzensierter Teile. Rendering und Ausschluss sind mit injizierter OCR abgedeckt; echte OCR manuell prüfen. |
| 3 | Leere Ergebnisse zeigen einen Hinweis, ohne das Clipboard anzufassen. Ebenso OCR-Fehler und fehlende Windows-Sprachpakete. Regressionstests prüfen Schreibaufrufe bzw. Pasteboard-Inhalt und `changeCount`. |
| 4 | Abgebrochene Auswahl beendet den bestehenden Capture-Pfad vor der OCR, ohne Hinweis oder Clipboard-Schreibzugriff. Auf beiden Plattformen mit Esc manuell prüfen. |
| 5 | Ausschließlich Vision bzw. `Windows.Media.Ocr`, keine Netzwerk-API und kein Cloud-Fallback. macOS automatische Sprache, Windows `TryCreateFromUserProfileLanguages`. Windows wandelt Bilder ausschließlich in Speicherstreams um; macOS nutzt den bestehenden sofort gelöschten temporären Capture-Pfad. Offline-Verhalten manuell prüfen. |
| 6 | Reine `OCRTextLayout`-/`OcrTextLayout`-Funktionen sortieren von oben nach unten und innerhalb einer Zeile von links nach rechts, verbinden Fragmente durch Leerzeichen und Zeilen durch `\n`. Feste Zeilenanker vermeiden nicht-transitive Vergleichsfunktionen. Vision-Koordinaten werden von unten-links nach oben-links umgerechnet. Tests prüfen unsortierte Eingaben, leichte Höhenabweichungen, umgekehrte Eingabe, leere Ergebnisse und Verpixelungsüberschneidungen. Kein Tabellen-/Mehrspalten-Layout-Erhalt. |
| 7 | Bestehende Hotkey-IDs und Bild-Exportkürzel bleiben erhalten. Registrierung des OCR-Kürzels wird geprüft und bei Fehler mit Menü-Fallback erklärt. Capture-Reentry ist auch während asynchroner OCR gesperrt; Editor-Button wird während OCR deaktiviert. Belegte Hotkeys und alte Aufnahmewege manuell prüfen. |
| 8 | App und Windows-Testprojekt zielen auf `net8.0-windows10.0.19041.0`. Fehlende OCR-Sprachpakete werden abgefangen und verständlich erklärt; der Fehlerpfad ist injiziert getestet. Alle neun neuen macOS-Strings sind in zehn `.lproj` übersetzt. Settings-Kürzelliste und beide README-Tabellen erweitert. CI `build-macos` führt zusätzlich Lokalisierungsprüfung und relevante Swift-Tests aus; `build-windows` nutzt seinen vorhandenen Regressionstest-Schritt. **Grüne Builds, Plattformtests und der vollständige Lokalisierungslauf sind noch nicht nachgewiesen.** |

## Test-first und lokale Prüfungen

Die neuen Swift-Tests und Windows-OCR-Fälle wurden **vor** den zugehörigen
Produktions-APIs ergänzt. Vor dem Fix zeigte die Quellensuche keine Definitionen
für `OCRService`, `OCRTextLine`, `OCRTextLayout`, ihre Windows-Gegenstücke,
`copyText`/`CopyTextAsync` und `TrySetText`. Damit ist ein initialer
Compilerfehler wegen fehlender APIs zu erwarten. Das ist ein **statischer
Rot-Nachweis, kein ausgeführter fehlgeschlagener Regressionstest**. Der Test für
das asynchrone Windows-Capture-Gate wurde ebenfalls vor dessen API ergänzt.

Die ausdrückliche Server-Regel untersagt Builds und Plattform-Testausführung
auf diesem Linux-Host. Deshalb wurden weder Rot- noch Grünläufe ausgeführt;
dieser Teil der TDD-/AC-8-Anforderung kann hier nicht erfüllt werden.
Weitere Tests ergänzen Renderfehler, Editor-Reentry und Clipboard-Retry-Fehler.
Alle OCR-Ergebnisse/Fehler sind für deterministische Regressionen injiziert;
die Tests ersetzen keinen Funktionstest der echten Erkennungsengines.

Lokal ausgeführt:

- `git diff --check`: erfolgreich.
- `scripts/check-localizations.sh`: nicht erfolgreich, da `plutil` und
  `/usr/libexec/PlistBuddy` fehlen. Die Schlüssel-/Duplikat-/Platzhalter- und
  Code-Schlüssel-Prüfungen meldeten keine Abweichungen; `.strings`-Lint und
  Plist-Prüfung müssen unter macOS erfolgen.
- Statische Durchsicht der API-Nutzung, Koordinaten, Capture-Abbruchpfade,
  Speicher-/Bildlebensdauer, Clipboard-Formate, Lokalisierung und CI-Einbindung.

Auf den Plattformen ausführen (auch in der Build-CI vorgesehen):

```sh
# macOS 14+, Xcode/Swift gemäß CONTRIBUTING.md
scripts/check-localizations.sh
swift test --filter 'OCRTests|EditorExportTests'
scripts/build_app.sh
```

```powershell
# Windows 10 Build 19041+ / Windows 11, .NET 8 SDK
dotnet build windows/Snapboard.Windows/Snapboard.Windows.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release
```

Der Windows-Runner veröffentlicht keine echten Clipboard-Daten und ändert keine
Registry-Daten. Swift-Tests verwenden eigene benannte Pasteboards. UI-Tests
zeigen das Windows-Formular vor Rendering-/Sichtbarkeitsprüfungen an.
Plattformformate werden auf erforderliche Typen geprüft, nicht auf eine exakte
Aliasliste.

## Manuelle Review-Checkliste (noch offen)

Auf **macOS und Windows** mit lokalem Testbuild:

1. Browsertext, Fehlermeldung und Bild-PDF, jeweils Deutsch und Englisch,
   über OCR-Hotkey und Menü auswählen. Einfügen ergibt Klartext ohne Bild.
   Native Pasteboard-/Clipboard-Typen auf den erforderlichen Texttyp und
   fehlende Bilddaten prüfen.
2. Dasselbe über **Text kopieren** im Editor, einschließlich Textanmerkungen,
   1x/Retina bzw. DPI-Skalierung, großer Aufnahmen und Verpixelung eines
   einzelnen Wortes/einer ganzen Zeile. Kein Text aus zensierten Bereichen;
   Editor bleibt offen, Bild-Kopieren und Speichern funktionieren weiter.
3. Clipboard vorab mit Text und einem Bild befüllen. Eine leere Auswahl mit
   Bildinhalt ohne Text muss einen Hinweis zeigen und alles unverändert lassen.
   Esc während Auswahl muss alles unverändert lassen und keinen Hinweis zeigen.
4. Netzwerk trennen, Fälle 1–3 wiederholen und ausgehende Verbindungen beobachten.
   OCR muss weiterhin funktionieren und selbst keine Verbindung aufbauen.
5. OCR-Kürzel durch eine separate Test-App vor dem Start belegen. Verständlicher
   Hinweis; OCR über Menü und beide bestehenden Hotkeys funktionieren.
   Wiederholte Hotkeys während Auswahl/Erkennung erzeugen keine zweite Auswahl.
6. Windows: in einem Testprofil ohne OCR-Sprachpaket starten, OCR versuchen.
   Erwartet: Installationshinweis, unverändertes Clipboard, kein Absturz.
   Mit Benutzerprofil-Sprache und installiertem OCR-Paket erneut prüfen.
   Große Bilder oberhalb von `OcrEngine.MaxImageDimension` prüfen.
7. Windows: Clipboard durch einen Testprozess blockieren und OCR ausführen.
   Erwartet: drei Schreibversuche, verständlicher Hinweis, App/Editor bleibt
   nutzbar; nach Freigabe funktioniert Kopieren wieder.
8. macOS: Settings und Editor in allen zehn UI-Sprachen auf Lesbarkeit prüfen.

Keine Produktionsdeployments, Produktionsdaten-/Supabase-Änderungen, Releases,
Signierung/Notarisierung oder Merges wurden durchgeführt.
