# Issue #9 — Windows-Lokalisierung (Paket 1)

## Grundlage und Prüflücken

- Issue: <https://github.com/leonatwork/snapboard/issues/9>.
- Ausgangsstand: `2306fc6e8e357a64980c9674b273825f52e8844f`; `HEAD` entsprach
  dem lokalen `origin/main`, Arbeitsbaum vor Beginn sauber. Kein Branchwechsel,
  Cherry-Pick, Commit oder Push; keine fremden PR-Stände verwendet.
- `CONTRIBUTING.md`, beide READMEs, Windows-Quellen, bestehender Windows-Testrunner,
  macOS-Übersetzungen und Lokalisierungsprüfer sowie Build-Workflow gelesen.
  `CLAUDE.md` und `AGENTS.md` sind im Workspace nicht vorhanden. Die Wissensbasis
  wurde nach Issue-Kontext und Repository-Regeln gefragt.
- **GitHub-Thread einschließlich Kommentaren und offene PRs nicht überprüfbar:**
  Der lesende `gh`-Aufruf ist durch Tool-Berechtigungen gesperrt. Auch ein aktueller
  Remote-Abgleich ist nicht belegt. Grundlage ist der vollständige im Auftrag
  bereitgestellte Issue-Text. Kommentare und PR-Überschneidungen vor Lieferung
  extern prüfen. Im ausgecheckten Main-Code ist keine offene PR-Abhängigkeit
  erkennbar; bereits gemergte Windows-Fehlermeldungen sind mit lokalisiert.
- **Prüfkonflikt:** Testausführung und grünes `build-windows` sind gefordert,
  zusätzliche Server-Regeln verbieten App-Build/-Ausführung auf Linux.
  Keine App, .NET-/Swift-Tests oder Builds ausgeführt. Nur die ausdrücklich für
  Linux geforderte Python-Ressourcenprüfung, deren Standardbibliotheks-Tests
  und Git-Diff-Prüfungen ausgeführt. Der Windows-Red-/Green-Nachweis und AC-7
  sind offen. Bei wörtlicher Auslegung des Verbots als Verbot auch aller
  Prüfscripte wäre es mit AC-4 und dem verlangten Linux-Nachweis unvereinbar.

## Verbindlicher Umfang

Die strukturierte Paket-1-Fassung ersetzt die ursprünglichen, im Details-Block
aufbewahrten Kriterien. Deren Settings-, Ton-, Mitteilungs-, Strichstärken- und
Icon-Kriterien gehören ausdrücklich zu späteren Paketen. Dieser Stand setzt
Lokalisierung, Assembly-Version, Linux-Prüfer und README-Anpassung um.
Die bestehende Autostart-/Ton-/Fehlerlogik wurde nur mit Ressourcen versehen.
macOS-Quellen und macOS-Übersetzungen wurden nicht geändert.

| Kriterium | Umsetzung / Nachweis | Offener Nachweis |
| --- | --- | --- |
| AC-1: en/de, unsupported → en | `ResourceManager` mit `CurrentUICulture`, neutral `en`; Ressourcen für Tray, Tooltip, Dialoge, Editor. Windows-Tests prüfen echte Editor-Texte und Defaults in en-US/de-DE/ja-JP/pl-PL sowie fr-CA/zh-CN-Elternkulturen | Windows-Testrunner und manuelle Prüfung auf Windows 10/11 |
| AC-2: zehn .resx, identische Keys/Platzhalter | Neutral `Strings.resx` und neun Satelliten; Linux-Prüfer erfolgreich: **10 Sprachen, 54 Keys** | Laden der gebauten Satelliten durch Windows-Testrunner |
| AC-3: keine festen App-UI-Texte in windows/ | Alle vorhandenen App-Beschriftungen einschließlich Fehlermeldungen, Farben, Speicherfilter/-titel/-dateiname und Größenanzeige aus Ressourcen; verbleibende Literale statisch geprüft | Visueller Windows-Rundgang |
| AC-4: Linux-Prüfer, Fehlercode, Dokumentation | Python-3-Standardbibliothek; XML, Duplikate, Sprachdateien, fehlende/zusätzliche Keys, Platzhalter und im Code benutzte Keys geprüft; README und Skriptkopf dokumentieren Aufruf | Erfüllt; Fehlercodes durch absichtlich beschädigte temporäre Kataloge getestet |
| AC-5: Version aus Assembly | `L10n.AboutMessage` verwendet die App-Assembly-Version mit drei Komponenten (`1.1.1`); Windows-Test vergleicht mit App statt Testrunner-Assembly | Windows-Testrunner und Über-Dialog |
| AC-6: README-Sprachen | Beide READMEs nennen zehn Sprachen auf beiden Plattformen sowie Windows-Fallback Englisch | Erfüllt |
| AC-7: build-windows grün | Bestehender Job baut App und startet Windows-Testrunner; zusätzliche Python-Katalog-/Regressionstests eingebunden | **Nicht nachgewiesen**, GitHub/Windows-Ausführung gesperrt |

App-UI-Texte sind von Windows-eigenen Dateidialog-Controls, dem nativen
MessageBox-OK-Button und unverändert weitergereichten System-Exception-Details
zu unterscheiden: Diese werden von Windows/.NET lokalisiert und können auf
Polnisch erscheinen. Das englische Fallback gilt für Snapboard-eigene Texte.
Falls AC-1 auch alle Windows-eigenen Controls zwingend auf Englisch verlangt,
ist dieser weitergehende Anspruch nicht umgesetzt. Build-Batch-Ausgaben und
Regressionstest-Diagnosen sind Entwicklerausgaben, keine Client-UI.

## Ressourcen und UI

- Benötigte Texte einmalig aus `Resources/*.lproj/Localizable.strings` übertragen;
  die vorhandenen Windows-Toolbar-Symbole sind Bestandteil der Ressourcen.
  `windows.*` enthält eigene Kürzel (insbesondere Ctrl+Y statt macOS-Redo),
  Infobereich-, Versions-, Autostart-, Fehler- und Dateidialogtexte. Farben sind
  ebenfalls in allen zehn Sprachen übersetzt. Kein Generator/Sync hinzugefügt.
- SDK-Standard-Embedding der `.resx`, `RootNamespace=Snapboard` und
  `NeutralLanguage=en`: Englisch liegt in der Hauptassembly; die übrigen
  Ressourcen werden Satelliten. Unbekannte Kulturen fallen über .NETs
  Elternkultur-Kette auf Englisch zurück; pt-BR bleibt eine regionale Übersetzung.
- Toolbar-Flow-Layout erlaubt Umbruch für längere Übersetzungen. Die Visual-Basic-
  InputBox ist durch einen kleinen autoskalierenden modalen Textdialog ersetzt,
  damit auch OK/Abbrechen Snapboard-Ressourcen verwenden. Annahme, Abbruch und
  Nichtübernahme von leerem/Whitespace-Text folgen dem bisherigen Verhalten.
- `.resx` werden unabhängig gepflegt; Platzhalter sind .NET-Composite-Formate.
  Der Prüfer berücksichtigt Argumentindex, Wiederholungen, Ausrichtung und
  Format; Umordnung ist erlaubt, `{{`/`}}` sind literale Klammern.

## Test-first-Nachweis

1. `scripts/tests/test_windows_localizations.py` und die neuen Windows-Fälle vor
   dem Produktionsfix ergänzt.
2. Erster ausgeführter Python-Lauf: 14 Tests fehlgeschlagen (16 Assertions mit
   Subtests), da der Prüfer und sämtliche Ressourcen noch fehlten.
3. Danach nur den Prüfer implementiert, Ressourcen weiter fehlend: **12 Tests
   grün, 2 Repository-Regressionen rot**. Der Prüfer meldete exakt die zehn
   fehlenden Kataloge mit Exitcode 1. Das ist der gezielte ausgeführte Red-Nachweis
   vor dem Ressourcen-/UI-Fix, nicht nur ein fehlendes Testwerkzeug.
4. Nach dem Fix: **14 Python-Tests grün**, Katalogprüfung erfolgreich. Abgedeckt:
   fehlende/zusätzliche Sprache und Keys, Duplikate, XML-Fehler, leere Werte,
   falsche Argumentindices/-anzahl/-formate, ungültige Formatklammern,
   Mac-Kürzel, unbekannte Source-Keys, gültige Umordnung/escaped braces.
5. Windows-Fälle im vorhandenen abhängigkeitsfreien Runner ergänzt: echte Editor-
   Texte/Defaults, englisches pl-Fallback, zehn Satelliten ohne verdeckten
   Elternfallback, Formatierung jeder Ressource, Tooltip-Limit von 127 Zeichen,
   Elternkultur-Lookup und Assembly-Version. Kein Paket hinzugefügt.
   Vor dem Fix fehlten Kataloge und `L10n`; diese Windows-Red-Erwartung ist
   **nicht ausgeführt**. Auch Windows-Green und UI-Layout sind nicht belegt.
6. `git diff --check` erfolgreich; statischer Review der UI-Literale, Ressourcen-
   Namen, NeutralLanguage und aktuellen Assembly-Version durchgeführt.

## Reproduktion und verbleibende QS

Auf Linux (ausgeführt):

```bash
python3 -B -m unittest discover -s scripts/tests -v
python3 -B scripts/check_windows_localizations.py
git diff --check
```

Auf Windows 10/11 mit .NET 8 (noch erforderlich):

```powershell
dotnet build windows/Snapboard.Windows/Snapboard.Windows.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release
```

Den CI-Job `build-windows` extern prüfen. Manuelle en/de/ja/pl-Prüfung inklusive
kleinem Bildschirm und 100/150/200 % DPI, Texteingabe/Abbruch und Fehlerdialogen
steht in `windows/Tests/README.md`. Für die Sprachprüfung die Windows-Anzeigesprache
ändern, ggf. neu anmelden und Snapboard neu starten. Keine Produktionsdeployments,
Produktionsdaten-/Supabase-Änderungen, Releases oder Veröffentlichungen erfolgt.

Status: Code und Tests reviewbar im Arbeitsbaum; GitHub-Thread-/PR-, Windows-
Laufzeit-, manuelle QS- und CI-Nachweise bleiben offen. Kein PR angelegt oder gemergt.
