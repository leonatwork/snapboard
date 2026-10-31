# Issue #10 – Lokale OCR auf macOS und Windows

## Verbindlicher Umfang und Ausgangsstand

Grundlage: die bereitgestellte strukturierte Issue-Beschreibung, beide Plattformen
in einem Lauf, macOS ⌘⇧6, Windows Ctrl+Shift+3, automatische Spracherkennung,
Editor-OCR auf gerenderten Pixeln einschließlich Anmerkungen. Die früheren offenen
Fragen im Original sind durch die strukturierten Entscheidungen beantwortet.

Arbeitsbeginn: sauberer Arbeitsbaum; HEAD und lokales origin/main identisch mit
`644e5458eb76eef7e3ce43fefa3e1c0619082a98`. Keine fremden PR-Branches als Grundlage.
`CONTRIBUTING.md` gelesen; `AGENTS.md` und `CLAUDE.md` sind nicht vorhanden.
`kb ask "snapboard Issue 10 OCR Architektur, Repository-Regeln und offene PR-Abhängigkeiten"`
bestätigt den bekannten Stand, liefert aber keinen aktuellen GitHub-Abgleich.

**Nicht erfüllbare Vorprüfung:** Der Harness sperrt `gh`; vollständiger Issue-Thread,
Kommentare und offene PRs konnten nicht abgerufen werden. Die Aktualität des lokalen
origin/main gegenüber GitHub ist nicht bestätigt. Vor Integration muss der Reviewer
Kommentare und offene PRs abgleichen. Keine bekannte technische PR-Abhängigkeit;
Windows-Texte folgen dem vorhandenen deutschen UI ohne neue Lokalisierungsabhängigkeit.

## Akzeptanzkriterien

| AC | Verbindliches Verhalten | Nachweisplanung |
| --- | --- | --- |
| 1 | Auswahl über ⌘⇧6 / Ctrl+Shift+3 → nur Klartext, kein Bild | OCR-Service-Regressionen + Plattformtest von Hotkey und Auswahl |
| 2 | Editor nutzt gerendertes Bild; verpixelter Text fehlt | Render-/Redaktionsregressionen + reale OCR manuell |
| 3 | Kein Text → Hinweis und unveränderte Zwischenablage | injizierte leere OCR-Ergebnisse |
| 4 | Esc bei Auswahl → keine Meldung, Zwischenablage unverändert | macOS-Abbruchregression + manueller Windows-Abbruch |
| 5 | Lokale OCR ohne Netzwerk | ausschließlich Vision / Windows.Media.Ocr; Offline-Test offen |
| 6 | Lesereihenfolge und Zeilenumbrüche, reine Funktion | Tests für ungeordnete Zeilen, leicht versetzte Zeilenfragmente, Leerraum, Redaktionen |
| 7 | Bestehende Kürzel unverändert; neues belegtes Kürzel meldet Hinweis | macOS-Dispatchregression + manuelle Registrierungskollision auf beiden Plattformen |
| 8 | Alle zehn Lokalisierungen, grüne build-macos/build-windows; fehlendes Windows-Sprachpaket verständlich | Sprachpaket-Regression; Lokalisierungs-/CI-Nachweise offen |

## TDD-Einschränkung

Regressionstests wurden **vor** dem Produktionscode ergänzt. Zu diesem Zeitpunkt
fehlen `OCRLine`, `OCRTextProcessing`, `OCRService`, `captureForText`, `copyText`,
`onTriggerText` und die entsprechenden Windows-APIs vollständig im Ausgangscode.
Die Tests referenzieren diese fehlenden APIs und wären vor dem Fix nicht kompilierbar.
Das ist eine statische Feststellung, **kein ausgeführter Rot-Nachweis**.

Die Zusatzregel „nichts bauen oder ausführen“ auf Linux steht im Widerspruch zum
geforderten ausgeführten Rot-/Grün-Nachweis und lokalen QS-Lauf. Sie wird beachtet:
keine App, Tests oder Build-/QS-Skripte ausführen. Tatsächliche Testergebnisse,
`scripts/check-localizations.sh` und grüne Plattform-CI sind damit noch nicht belegt.

## Implementierung

- `Sources/OCRService.swift`: `VNRecognizeTextRequest` mit genauer Erkennung,
  automatischer Spracherkennung und ohne Sprachkorrektur. Vision läuft abseits des
  UI-Threads; Klartext wird erst nach einem nichtleeren Ergebnis auf dem Main Actor
  als `.string` (`public.utf8-plain-text`) geschrieben. Keine Bildformate.
- `windows/Snapboard.Windows/OcrService.cs`: `TryCreateFromUserProfileLanguages`,
  PNG/WinRT-Konvertierung ausschließlich im RAM, `SoftwareBitmap` in BGRA8.
  Übergröße wird proportional auf `OcrEngine.MaxImageDimension` reduziert; erkannte
  Rechtecke werden zurück in Originalpixel transformiert. Clipboard-Zugriff nach
  `await` im WinForms-STA mit der bestehenden Drei-Versuche-/100-ms-Strategie.
- `OCRTextProcessing.swift` / `OcrTextProcessing.cs`: reine, deterministische
  Sortierung mit festem Zeilenanker (Toleranz: halbe kleinere Zeilenhöhe), dann
  links nach rechts. Eine erkannte Zeile pro Zeilenumbruch, kein Layout-/Tabellenerhalt.
- Editor-OCR benutzt die vorhandenen Export-Renderer und bleibt im Editor.
  Aktuelle Entwürfe werden vorher abgeschlossen. Erkannte Zeilen, deren Rechteck
  eine Verpixelung berührt, werden vollständig ausgelassen. Das ist bewusst
  konservativ: Auch nicht verdeckte Wörter derselben Zeile können entfallen.
  Damit werden noch lesbare Restbuchstaben einer Pixelierung nicht kopiert.
- macOS-OCR-Auswahl teilt den vorhandenen Berechtigungs-/Abbruch-/Tempdateipfad
  mit dem Editor; Löschen der Aufnahme erfolgt vor OCR. Windows verwaltet die
  ausgewählte Bitmap bis zum Ende der asynchronen OCR und gibt sie danach frei.
- Neue Hotkey-ID 3 auf beiden Plattformen, macOS-Keycode 22 (6), Windows 0x33 (3),
  Registrierungskonflikt-Hinweis, Menü und Deregistrierung. IDs 1/2 bleiben gleich.
- Sieben neue Schlüssel in allen zehn `.lproj`, OCR-Zeile in SettingsView samt
  angepasster Höhe, OCR-Kürzeltabellen und Bedienhinweise in beiden READMEs.
  Windows bleibt beim bestehenden deutschen UI. Keine neuen Paketabhängigkeiten.
- App- und Windows-Testprojekt zielen auf `net8.0-windows10.0.19041.0`.
  `build-macos` enthält jetzt `scripts/check-localizations.sh` und `swift test`;
  `build-windows` führt weiterhin den erweiterten Regression-Runner aus.

## Tatsächlich durchgeführte Prüfungen

- `git diff --check`: erfolgreich (statische Whitespace-Prüfung).
- Quelltext-/Diff-Review: Aufnahmeabbruch vor OCR, Tempdateilöschung vor Erkennung,
  Clipboard erst nach Text, WinForms-STA nach `await`, Bitmap-Lebensdauer,
  Vision-Bottom-left → Top-left und Retina-Redaktionskoordinaten geprüft.
- `rg --count '^"ocr\.' Resources --glob '*.strings'`: genau sieben neue
  OCR-Schlüssel in jeder der zehn Dateien; Schlüssel und Texte zusätzlich gelesen.
  Das ersetzt **nicht** `plutil` oder das vorgeschriebene Lokalisierungsskript.
- HEAD und lokales origin/main nach Änderungen weiterhin identisch mit dem
  Ausgangscommit. Keine Commits, Branch-Erstellung, Pushes oder PR-Erstellung.

**Offen:** Keine Builds, Testläufe, ausgeführte Rot-/Grün-Nachweise, native OCR-Läufe,
Lokalisierungs-QS oder GitHub-CI-Abfragen. AC-1 bis AC-7 sind implementiert, aber
nicht vollständig auf den Zielplattformen nachgewiesen. AC-8 ist ohne grüne CI und
Lokalisierungsprüfung noch nicht erfüllt. Keine Releases oder Deployments.

## Nachzuholende QS auf den Zielplattformen

Auf einem Mac mit macOS 14+ und Xcode/Swift aus dem Repository-Root:

```sh
swift test --filter OCRTests
swift test --filter CapturePermissionTests
./scripts/check-localizations.sh
```

Zusätzlich den gesamten bestehenden `build-macos`-Job bestätigen (dieser enthält
nun auch die bestehenden Export-/Berechtigungsregressionen). Keine Release-Pipeline
ausführen. Der unveränderte App-Build benutzt weiterhin die vorhandene CI-Signierlogik.

In einer Windows-10-2004+/Windows-11-Testsitzung mit .NET 8:

```powershell
dotnet build windows/Snapboard.Windows/Snapboard.Windows.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release
```

Der dependency-freie Runner schreibt bei den OCR-Clipboard-Tests Bild und Unicode-
Text auf die Zwischenablage der Testsitzung; nicht in einer produktiven Sitzung
mit benötigtem Clipboard-Inhalt ausführen. Formulare werden vor UI-Prüfungen
angezeigt und besitzen dadurch ihre nativen Handles. Native OCR ist in diesen
Regressionen durch injizierte Ergebnisse ersetzt; kein Sprachpaket wird verändert.

Manuell auf **beiden** Plattformen (Ergebnisse und Betriebssystemversion festhalten):

1. Browsertext, Fehlermeldung und Bild-PDF, Deutsch und Englisch, mehrere Zeilen:
   OCR-Kürzel und Menü ausprobieren; Text mit Umlauten prüfen, kein Bildformat.
   macOS muss `public.utf8-plain-text`, Windows `CF_UNICODETEXT` enthalten; zusätzliche
   OS-Aliase sind zulässig. Kein PNG/TIFF/Bitmap als OCR-Nutzlast.
2. Editor mit Text-/Pfeilanmerkungen und Verpixelung: Text aus dem gerenderten Bild,
   keine verdeckten Zeilen; Editor und Anmerkungen bleiben verfügbar. Auch Retina,
   Windows-100%-Scrollansicht und große Bilder oberhalb des OCR-Limits prüfen.
3. Leerer Bereich → Hinweis und identischer Clipboard-Inhalt. Esc während der
   OCR-Auswahl → identischer Inhalt und keine Meldung. Danach alle Modi erneut nutzen.
4. ⌘⇧6 bzw. Ctrl+Shift+3 in einer Testanwendung vor App-Start reservieren → Hinweis;
   Menü-OCR bleibt nutzbar und die unveränderten Kürzel 1/2 funktionieren.
5. Netzwerk deaktivieren, Erkennung wiederholen und Prozess-Netzwerkaktivität
   beobachten: kein OCR-Netzwerkzugriff. Keine anhaltenden Aufnahme-/OCR-Dateien.
6. Windows-Testprofil ohne passendes OCR-Sprachpaket → verständlicher Hinweis,
   unverändertes Clipboard, kein Absturz. Mit vorhandenem Profil-Sprachpaket erneut
   prüfen. Belegte Zwischenablage → Hinweis nach drei Schreibversuchen.
7. Alle zehn macOS-Sprachen: Menü, Settings-Zeile, Editor-Button und Hinweise auf
   abgeschnittene Texte und Fensterlayout prüfen.

Vor Integration: vollständigen Issue-Thread/Kommentare und offene PRs abgleichen,
die beiden CI-Jobs bestätigen und diese offenen Nachweise im Review aktualisieren.
