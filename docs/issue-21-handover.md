# Issue #21: Eine Text-/Schrittnummer-Annotation pro Geste

## Grundlage und Lieferstatus

- Issue: <https://github.com/leonatwork/snapboard/issues/21>
- Ausgangsstand: `644e5458eb76eef7e3ce43fefa3e1c0619082a98`; `HEAD` entspricht
  dem lokalen `origin/main`, der Arbeitsbaum war vor Beginn sauber.
- Gelesen: bereitgestellte strukturierte und ursprüngliche Issue-Beschreibung,
  `CONTRIBUTING.md`, `Package.swift`, `.github/workflows/build.yml`, vorhandene
  XCTest-Tests, EditorViewModel, Gesture-Handler und Annotation-/Rendering-Modell.
  `AGENTS.md` und `CLAUDE.md` sind im Workspace nicht vorhanden. Die Wissensbasis
  wurde zur Editor-/Testkonvention befragt; sie enthielt keine weiteren
  issue-spezifischen Entscheidungen.
- **GitHub-Vorprüfung offen:** `gh issue view 21` (einschließlich des
  `comments`-Felds) und `gh pr list --state open` wurden durch die
  Werkzeugberechtigungen gesperrt. Der vollständige Thread, Kommentare, offene
  PRs und die Aktualität des Remote-Stands konnten nicht verifiziert werden.
  Vor Übernahme der Lösung nachprüfen und gegebenenfalls Kriterien abgleichen.
- Der Fix verwendet ausschließlich APIs des geprüften Main-Stands. Keine
  erkennbare technische Abhängigkeit von einem offenen PR; unbekannte
  PR-Überschneidungen können mangels Zugriff nicht ausgeschlossen werden.
- Änderungen liegen ausschließlich im Arbeitsbaum. Kein Commit, Push,
  Branchwechsel, neuer Branch, Cherry-Pick, PR oder Merge. Keine Builds,
  App-Ausführung, Deployments oder Änderungen an Produktionsdaten.

## Akzeptanzkriterien und Umsetzung

Verbindliche Grundlage sind AC-1 bis AC-4 der bereitgestellten Beschreibung.
AC-1 formuliert die Zählererhöhung neben beiden Werkzeugen. Fachliche Auslegung:
**Text verändert `nextStepNumber` nicht; eine abgeschlossene Schrittnummer-Geste
erhöht ihn genau um 1.** Dies entspricht dem Ziel „die Schrittnummer zählt korrekt
hoch“ und dem bestehenden Text-Verhalten. Eine wörtlich geforderte Erhöhung auch
bei Text wäre hierzu widersprüchlich und wurde nicht implementiert.

| Kriterium | Umsetzung / Regressionstest | Nachweisstatus |
| --- | --- | --- |
| AC-1: Genau eine Annotation pro Text-/Schrittnummer-Geste, Nummer +1 | `startDrawing` setzt für beide Werkzeuge `currentDraft`. `finishDrawing` übernimmt einmal und erhöht nur bei `.stepNumber` den Zähler. Routing-Test prüft 0, 1 und 6 Bewegungen. | Implementiert, statisch geprüft; XCTest und manuelle Prüfung offen |
| AC-2: ViewModel-Sequenz belegt das Verhalten | Separate Text-/Schrittnummer-Tests rufen `startDrawing`, mehrere `updateDrawing` und `finishDrawing` auf; prüfen Draft-Identität, Anzahl, Startposition, Text/Fallback und zwei aufeinanderfolgende Nummern ab 4. Wiederholtes Finish erzeugt nichts Zusätzliches. | Tests geschrieben; ausgeführter Rot-/Grün-Nachweis offen |
| AC-3: Übrige Werkzeuge unverändert | Regressionstest für Rechteck, Kreis, Pfeil, Blur, Stift und Highlighter: Draft, normalisierte/geklemmte Koordinaten, Pfadpunkte, Farbe, Linienbreite, Abschluss und Undo/Redo. | Produktionspfade unverändert; XCTest offen |
| AC-4: Ein Undo entfernt genau diese eine Annotation | Gemeinsamer Abschluss speichert einen Undo-Snapshot. Test legt vorher ein Rechteck an; ein Undo stellt genau dessen Zustand wieder her, Redo die abgeschlossene Geste. | Implementiert, statisch geprüft; XCTest und UI-Prüfung offen |

Die Produktionsänderung betrifft nur `startDrawing` und `finishDrawing` in
`Sources/Views/EditorView.swift`. Der vorhandene Canvas zeigt den Draft bereits
an. Text und Nummer bleiben am Startpunkt der Geste verankert. Keine Änderung am
Gesture-Handler, Rendering, Windows-Code, Undo-Verhalten des Zählers oder an
Abhängigkeiten bzw. UI-Texten.

## Test-first und Prüfungen

1. Zuerst `Tests/SnapboardTests/EditorDrawingTests.swift` mit fünf Tests angelegt.
   Vor dem Fix zeigte `git status --short` ausschließlich diese neue Datei;
   der Diff für `EditorView.swift` war leer.
2. Erwartetes Fehlschlagen am unveränderten Code statisch nachvollzogen:
   - Die direkten Text-/Nummer-Tests verlangen einen Draft. Der alte Code lässt
     ihn leer und hängt sofort eine Annotation an; Text verändert außerdem den
     Undo-Stack sofort, Schrittnummer erhöht den Zähler sofort.
   - Der Routing-Test erzeugt bei zwei weiteren Mausereignissen mit dem alten
     Code drei Annotationen/Undo-Snapshots statt einer; bei Schrittnummer steigt
     der Zähler von 1 auf 4 statt auf 2. Der Startpunkt späterer Annotationen
     wandert mit der Maus.
   - Der Undo-Test hinterlässt im alten Code nach einem Undo noch zusätzliche
     Annotationen derselben Geste statt ausschließlich des vorherigen Rechtecks.
   - Der Test der übrigen Werkzeuge soll bereits auf dem Ausgangscode bestehen.
3. Erst danach Draft-Fix implementiert. Statischer Review bestätigt: Updates
   behalten die Draft-ID; Finish speichert einen Snapshot, übernimmt eine
   Annotation und leert den Draft. Ein zweites Finish ist wirkungslos. Die
   Erhöhung richtet sich nach `draft.tool`, nicht nach einer späteren Auswahl.
4. `git diff --check` erfolgreich; neue Test- und Handover-Dateien zusätzlich
   mit `git diff --no-index --check /dev/null <Datei>` geprüft.
5. **Kein ausgeführter Rot-/Grün-Nachweis und kein Build-Nachweis:** Der Auftrag
   fordert `swift test`, verbietet zugleich Builds und Ausführung auf diesem
   Linux-Server ohne Swift/Xcode/AppKit. Es wurden deshalb keine Swift-Tests,
   Builds oder manuellen App-Prüfungen ausgeführt. Statische Prüfung ersetzt
   keinen Testlauf. Keine Lokalisierungsänderung; kein entsprechender Lint nötig.

## Nachzuholende QS auf macOS

Auf macOS 14+ mit passender Xcode-/Swift-Toolchain:

1. In einer isolierten Kopie des genannten Ausgangsstands nur die neue Testdatei
   übernehmen und `swift test --filter EditorDrawingTests` ausführen. Die vier
   Text-/Schrittnummer-Tests müssen fachlich fehlschlagen; der Test der übrigen
   Werkzeuge muss bestehen. Kein Kompilierfehler gilt als Rot-Nachweis.
2. Auf dem Stand mit Fix `swift test --filter EditorDrawingTests`, danach
   `swift test` für neue und bestehende Tests ausführen.
3. Gemäß `CONTRIBUTING.md` die bestehenden macOS-/Windows-Build-Jobs prüfen.
   Der macOS-Workflow baut mit `./scripts/build_app.sh`, führt aber keine
   XCTest-Tests aus; ein grüner Build allein erfüllt den Testnachweis nicht.
4. In einer lokalen macOS-Testinstallation Text und Schrittnummer jeweils mit
   einfachem Klick sowie gedrückter Maustaste und mehreren Bewegungen prüfen:
   genau eine Annotation am Startpunkt. Text lässt den Zähler unverändert;
   aufeinanderfolgende Nummer-Gesten zeigen 1, 2, 3. Ein Undo entfernt nur die
   letzte Annotation, Redo stellt sie wieder her. Die sechs anderen Werkzeuge
   kurz zeichnen und Undo/Redo prüfen.

Die gesperrte GitHub-Vorprüfung, ausgeführte Regressionstests einschließlich
Rot-Nachweis, Plattform-Builds und manuelle macOS-Prüfung bleiben ausdrücklich
offen. Diese Lösung ist zur Code-Review vorbereitet, nicht laufzeitverifiziert.
