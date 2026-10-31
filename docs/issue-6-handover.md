# Issue #6: macOS-Berechtigungen und Erststart – Handover

## Grundlage und Lieferstatus

- Issue: <https://github.com/leonatwork/snapboard/issues/6>
- Ausgangsstand: `2306fc6e8e357a64980c9674b273825f52e8844f`; `HEAD` entsprach dem
  lokalen `origin/main`, der Arbeitsbaum war sauber. Kein Branchwechsel, kein
  Cherry-Pick und keine Übernahme aus offenen PRs.
- Gelesen: mitgelieferter strukturierter und ursprünglicher Issue-Text,
  `CONTRIBUTING.md`, `Package.swift`, Build-Workflow, Lokalisierungsprüfung,
  vorhandene XCTest-Konventionen und relevante Quellen. `AGENTS.md` und
  `CLAUDE.md` sind im Repository nicht vorhanden; der Zugriff auf übergeordnete
  Verzeichnisse wurde durch die Umgebung gesperrt.
- **Vorprüfung offen:** Lesende `gh issue view … --comments`- und
  `gh pr list … --state open`-Aufrufe wurden durch die Tool-Berechtigungen
  gesperrt. Vollständiger Thread, Kommentare, PR-Überschneidungen und Aktualität
  des Remote-Stands sind deshalb nicht bestätigt. Vor Lieferung nachprüfen.
  Aus dem geprüften Main-Code ergibt sich keine zusätzliche PR-Abhängigkeit;
  eine Aussage über unbekannte offene PRs ist nicht möglich.
- Code und Tests liegen im Arbeitsbaum zur Review. Kein Commit, Push, neuer
  Branch oder PR wurde erstellt. Kein Build, App-Start, Release oder Deployment.

## Verbindliche Akzeptanzkriterien

Grundlage sind AC-1 bis AC-8 des bereitgestellten Issue-Texts. Kein eigener
Onboarding-Assistent; `screencapture` bleibt der Aufnahmeweg. Keine neue
Einstellung, Abhängigkeit oder Änderung an Signierung/Notarisierung.

| AC | Umsetzung und Regressionstest | Nachweisstatus |
| --- | --- | --- |
| 1: Fehlendes Bildschirmaufnahme-Recht verhindert beide Aufnahmearten; lokalisierter Dialog | Gemeinsames `canStartCapture()` in `CaptureService`, injizierbares `CGPreflightScreenCaptureAccess` vor Prozess-/Dateivorbereitung; Test ruft beide Methoden auf und erwartet null Starts | Implementiert; XCTest und Hotkey-/UI-Prüfung auf Mac offen |
| 2: Dialog öffnet direkt die Datenschutz-Unterseite | Injizierbarer Aufruf von `NSWorkspace.open` mit `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`; Test prüft exakte URL beider Modi | Implementiert; tatsächliches Ziel auf Mac offen |
| 3: Mit Recht funktionieren beide Modi ohne Zusatzdialog | Bestehende Prozessargumente, Clipboard-/Editor- und Erfolgslogik bleiben erhalten; Test prüft Starts und erneute Prüfung nach Entzug | Implementiert; echte erfolgreiche Aufnahmen auf Mac offen |
| 4: Startfehler sichtbar, Esc ohne Meldung | Beide `runProcess`-Fehlerwege zeigen lokalisierten Alert mit Systemfehler; Test injiziert Startfehler. Abbruchtest durchläuft reale Prozess-Terminierung ohne Ergebnis und erwartet keine Meldung | Implementiert; XCTest und echtes Esc auf Mac offen |
| 5: Keine Mitteilungsanfrage beim Start | Anfrage aus `AppDelegate` entfernt; Initialisierung von `AppState` fragt nicht an, auch bei gespeichertem eingeschaltetem Schalter; zwei Tests | Implementiert; erster App-Start auf Mac offen |
| 6: Anfrage beim Einschalten; Ablehnung setzt Schalter aus und zeigt Hinweis | `showNotification.didSet` reagiert nur auf aus → an. Systemadapter prüft zuerst den Autorisierungsstatus und fragt nur bei `.notDetermined` an. Bereits erlaubt/abgelehnt löst keine erneute Systemanfrage aus. Tests für Erlauben, Ablehnen, unveränderte Zuweisung sowie aus/an während laufender Anfrage | Implementiert; XCTest und reale TCC-/Mitteilungsdialoge offen |
| 7: Beide READMEs erklären Gatekeeper auf macOS 15+ und Bildschirmaufnahme-Recht | Je zwei Abschnitte unter Installation, einschließlich „Dennoch öffnen“, Datenschutz-Unterseite und möglichem App-Neustart | Dokumentation vorhanden; Gatekeeper-Ablauf auf macOS 15+ offen |
| 8: `scripts/check-localizations.sh` fehlerfrei | Sieben neue Schlüssel in allen zehn Sprachen, einheitlich ein `%@` im Startfehler | Originalskript auf Linux wegen fehlendem `plutil` und `/usr/libexec/PlistBuddy` gescheitert; erfolgreicher Originalskript-Lauf auf Mac offen |

Der Bildschirmaufnahme-Dialog bricht den aktuellen Aufnahmeversuch immer ab.
Bei „Systemeinstellungen öffnen“ wird `CGRequestScreenCaptureAccess` höchstens
einmal pro App-Sitzung aufgerufen, damit Snapboard in der Liste erscheint; danach
folgt der Deep-Link. „Abbrechen“ löst weder Systemanfrage noch Deep-Link aus.
Auch wiederholte Hotkeys während des modalen Dialogs starten keine Aufnahme.
Nach einer Mitteilungsablehnung wird der ausgeschaltete Wert vor dem Hinweis
gespeichert. Ein inzwischen ausgeschalteter Schalter erzeugt keinen verspäteten
Ablehnungshinweis und wird nicht automatisch wieder eingeschaltet.

## Test-first und ausgeführte Prüfungen

1. Zuerst `CapturePermissionTests.swift` und `NotificationPermissionTests.swift`
   im bestehenden XCTest-Target angelegt, danach Produktionscode geändert.
   Insgesamt elf neue Tests. Die vorhandenen Exporttests wurden nicht verändert.
2. **Kein bestätigter Rot-/Grün-Nachweis:** Der Auftrag fordert Testausführung,
   verbietet zugleich Build und Ausführung auf diesem Linux-Server ohne
   Swift/Xcode/AppKit. Die Swift-Tests wurden deshalb nicht ausgeführt. Auf dem
   Ausgangscode fehlen außerdem die neuen Injektionsinitialisierer; ein reiner
   Kompilierfehler wäre kein verifizierter fachlicher Regressionstest. Die
   fachliche Rot-Verifikation muss auf einem Mac mit den Injektionspunkten und
   dem alten Verhalten nachgeholt werden.
3. Tests ersetzen TCC, UI-Dialoge, Systemeinstellungen und Prozessstarts durch
   Closures. Der Abbruchtest startet ausschließlich `/usr/bin/false`, wartet auf
   den Produktions-Terminierungspfad und verändert weder Clipboard noch echte
   Berechtigungen. Mitteilungstests verwenden isolierte UserDefaults-Suites.
4. `git diff --check`: erfolgreich.
5. `bash -n scripts/check-localizations.sh`: erfolgreich.
6. `bash scripts/check-localizations.sh`: fehlgeschlagen wegen fehlender
   macOS-Werkzeuge (`plutil`, `PlistBuddy`). Vor dem Abbruch keine gemeldeten
   Schlüssel-, Duplikat-, Platzhalter- oder Quellreferenzabweichungen.
7. Ergänzender temporärer, abhängigkeitsfreier Python-Crosscheck: erfolgreich
   für alle zehn Sprachen und 62 Schlüssel. Geprüft wurden Strings-Syntax,
   doppelte Schlüssel, Schlüsselgleichheit, Platzhalter, verwendete Quellschlüssel
   und `CFBundleLocalizations`. Das ersetzt keinen Apple-`plutil`-Lint.
8. Statischer Diff-Review: beide Aufnahme-Einstiege verwenden dieselbe Prüfung;
   nur Startausnahmen zeigen den neuen Fehlerdialog. Keine Berechtigungsanfrage
   im App-Start; nur `.notDetermined` löst eine Mitteilungsanfrage aus. UI-Texte
   verwenden ausschließlich die vorhandene `L10n`-Infrastruktur.

Es gibt keine erkennbaren widersprüchlichen fachlichen Kriterien. Nicht erfüllbar
in dieser Umgebung sind der vollständige GitHub-/Regelabgleich, ausgeführte
Swift-Regressionstests, erfolgreicher Apple-Lokalisierungslint, grünes
`build-macos` und die manuelle macOS-Prüfung. Diese Nachweise sind ausdrücklich
offen, nicht als bestanden zu behandeln.

## Nachzuholende Prüfungen auf macOS

```bash
swift test --filter CapturePermissionTests
swift test --filter NotificationPermissionTests
scripts/check-localizations.sh
```

Zusätzlich muss `build-macos` im bestehenden Build-Workflow grün sein. Der Job
baut die App, führt aber die XCTest-Tests und den Lokalisierungslint nicht aus.

Manuell mit einer lokalen Testinstallation (nicht auf Produktionssystemen):

1. Snapboard beenden, `tccutil reset ScreenCapture com.leon.snapboard` ausführen,
   App starten. `⌘⇧1` und `⌘⇧2` sowie Menü und Einstellungs-Testbuttons prüfen:
   erklärender lokalisierter Dialog, keine Auswahl/kein Editor. „Abbrechen“
   öffnet keine Systemeinstellungen.
2. „Systemeinstellungen öffnen“ wählen: falls notwendig die einmalige
   Systemanfrage beantworten; danach landet man in Datenschutz & Sicherheit →
   Bildschirm- & Systemaudioaufnahme. Snapboard aktivieren, ggf. beenden und
   neu starten. Beide Modi erfolgreich testen, jeweils auch mit Esc abbrechen:
   kein Fehlerdialog und kein veränderter Clipboard-Inhalt beim Abbruch.
3. Kontrollierten Prozess-Startfehler über den Test-Injektionspunkt prüfen;
   Systembeschreibung und lokalisierter Titel erscheinen für beide Modi.
4. Für getrennte Erlauben-/Ablehnen-Durchläufe Snapboard beenden und auf der
   Testinstallation `tccutil reset All com.leon.snapboard` verwenden. Bestehenden
   Mitteilungsschalter vor dem jeweiligen Neustart ausschalten. Start ohne
   Anfrage prüfen; erst Einschalten zeigt die Systemanfrage. Erlauben behält
   den Schalter an; Ablehnen setzt ihn aus und zeigt den lokalisierten Hinweis.
   Nach Ablehnung erneut einschalten: kein zweiter System-Berechtigungsdialog,
   wieder Schalter aus mit Hinweis. Auch rasches aus/an während einer Anfrage
   prüfen. Nach Erlauben Direktaufnahme mit tatsächlicher Mitteilung prüfen.
5. Gatekeeper-Anleitung aus beiden READMEs mit einem heruntergeladenen,
   quarantänisierten Release auf macOS 15+ nachvollziehen. Nicht nur mit einem
   lokal gebauten Bundle testen. Lokalisierte Dialoge mindestens auf Deutsch
   und Englisch visuell prüfen.
