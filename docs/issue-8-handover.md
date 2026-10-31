# Issue #8 – Review-Handover

## Ausgangsstand und verbindlicher Umfang

Stand dieses Fortsetzungslaufs (2026-10-31): sauber ausgecheckter eigener Branch
`agent/bearbeite-github-issue-8-vollst-ndig-und-1026-2301`, HEAD `ac8632b`.
Das lokale `origin/main` ist `644e5458eb76`; es ist durch den bereits vorhandenen
Merge `ac8632b` enthalten. Die eigene Umsetzung (`46f2210`, `094905c`, `728580b`)
und die CI-Nacharbeiten (`d346eb8`, `90ad362`) wurden anhand von Log und Diff geprüft.
Der eingefrorene Exportvergleich basiert weiter auf `2306fc6`; zwischen diesem Stand
und dem aktuellen `origin/main` sind die beiden Annotationsrenderer unverändert
(`git diff 2306fc6 origin/main -- Sources/Models/AnnotationModel.swift windows/Snapboard.Windows/EditorForm.cs`
ist leer).
Die spätere ausdrückliche Anweisung zur Fortsetzung auf diesem Branch konkretisiert die
ursprüngliche Main-only-Vorgabe. Kein Branchwechsel, Cherry-Pick, neuer Commit oder Push
in diesem Lauf; kein fremder offener PR als Grundlage.

Grundlage ist die im Auftrag vollständig mitgelieferte strukturierte Issue-Beschreibung
inklusive Originalbeschreibung und des Fortsetzungsauftrags für PR #17. GitHub-Zugriff
(`gh`, Netzwerkzugriff) ist durch die Werkzeugberechtigungen gesperrt. Kommentare, zusätzliche
Entscheidungen und mögliche offene PR-Abhängigkeiten sind daher **nicht geprüft**.
`CLAUDE.md` und `AGENTS.md` wurden im Workspace nicht gefunden; Zugriff außerhalb des
Workspaces ist gesperrt. `CONTRIBUTING.md`, Paket-/Testkonfiguration, bestehende Tests
und Build-Workflow wurden gelesen; die Wissensbasis wurde erneut abgefragt. Ein aktueller
GitHub-/CI-Status ist aus lokalen Remote-Tracking-Refs nicht ableitbar.

Verbindlich übernommen: Der Export bestimmt die Optik. Nur die Vorschau wird angepasst;
keine Angleichung zwischen Plattformen, keine neuen Werkzeuge/Stile, keine Windows-
Strichstärkenauswahl. `--verify-annotations` ist ein eigener Modus; die bestehende
`--verify-text`-Prüfung und Textdarstellung behalten ihr Verhalten.

## Umsetzung und Akzeptanzkriterien

| Kriterium | Umsetzung / vorbereiteter Nachweis | Aktueller Nachweisstatus |
| --- | --- | --- |
| AC-1 | Reine `AnnotationLayout`-Werte in Bildpixeln; gemeinsame Export-Zeichenroutine für Rechteck, Kreis, Pfeil, Stift und Marker. Harness: 400×300 / 3000×2000, 2/4/7, native und eingepasste Canvas; symmetrischer Pixelvergleich mit höchstens ±1 px Nachbarschaft. | Implementiert, Plattformlauf offen |
| AC-2 | Gemeinsame Pfeilspitzenpunkte und unveränderte Exportkonstanten; Geometrie- und Bildregressionen. | Implementiert, Plattformlauf offen |
| AC-3 | Gemeinsame Badge-Geometrie, Rand und Schriftgröße; dieselbe AppKit-Zeichenroutine inklusive Ziffernplatzierung. Harness verwendet die mehrstellige Ziffer 12. | Implementiert, Plattformlauf offen |
| AC-4 | Abgeschlossene macOS-Pixelungen verwenden den unveränderten Exportpfad mit CIPixellate, Blockgröße und Quellbild; eine gecachte Bildlage liegt unter allen Vektoren. Entwürfe dürfen weiterhin vereinfacht sein. | Optische Übereinstimmung implementiert, Plattform-/Sichtprüfung offen; Unlesbarkeitsgarantie siehe unten |
| AC-5 | Windows cached eine mit `ApplyBlur` erzeugte Bildlage, einschließlich Reihenfolge überlappender Bereiche. Native/fitted/scrolled Paint-, Cache-, Geometrieänderungs-, Undo-/Redo- und Randfalltests. | Implementiert, Windows-Lauf offen |
| AC-6 | Beide Plattformen vergleichen alle acht Werkzeuge auf beiden Größen mit 2/4/7 gegen eingefrorene, unabhängige Exportrenderer des Ausgangsstands. macOS speichert Before/Export/Preview-PNGs; Windows optional ebenso. Windows-Exportmethoden sind im Diff unverändert. | Vergleich vorbereitet, nicht ausgeführt |
| AC-7 | Bestehendes Textlayout und Export-Zeichenoperationen unverändert; die Vorschau rasterisiert jetzt gemeinsam mit den Vektoren in Quellbildpixeln. Eigener All-Tool-Harness mit 48 Fällen und je zwei macOS-Canvas-Größen; `--verify-text` unverändert. | Beide Harness-Läufe offen |
| AC-8 | `build-macos` enthält jetzt relevante Swift-Tests und beide Harness-Prüfungen; die neuen Windows-Tests laufen über den vorhandenen Regression-Runner in `build-windows`. | Kein CI-Lauf gestartet oder eingesehen; Grünstatus nicht bestätigt |

### Konflikt innerhalb AC-4

„Im Bereich ist kein Originalinhalt mehr lesbar“ lässt sich für **beliebigen** Inhalt nicht
zusichern, wenn der Export gemäß AC-6 unverändert bleiben muss. Die vorhandene Pixelung
kann beispielsweise sehr große Zeichen weiterhin erkennen lassen; Bereiche mit Breite
oder Höhe ≤2 px werden vom bisherigen Export überhaupt nicht gepixelt. Die Lösung zeigt
genau diesen unveränderten Export, ohne eine stärkere Redaktion vorzutäuschen. Eine
universelle Unlesbarkeitsgarantie würde eine eigene fachliche Entscheidung und Änderungen
am Export erfordern. Dieses Teilkriterium wird deshalb nicht als erfüllt behauptet.

## Testfolge und Grenzen

Der vorherige Handover beschreibt eine test-first-Erstellung der vorhandenen Lösung;
die genaue Editierreihenfolge ist aus dem einzelnen übernommenen Commit nicht belegbar.
Im vorherigen Fortsetzungslauf wurden zuerst Windows-Paint-Regressionen für native,
eingepasste und gescrollte Ansicht ergänzt. Danach wurde das macOS-Exportoracle für
Text von `TextAnnotationLayout` entkoppelt: Es enthält jetzt die aus `origin/main`
übernommenen Textwerte und Zeichenoperationen, damit der Before/After-Vergleich nicht
dieselbe Textregression auf beiden Seiten übernehmen kann. Die vorhandene Textprüfung
bleibt unverändert. Die direkten macOS-Editor-Regressionen decken jetzt zusätzlich alle
sechs Vektorwerkzeuge bei 2/4/7 ab; ihre Fehlerbewertung verwendet nur tatsächlich
veränderte Pixel, damit falsche Pfeilspitzen/Badges nicht durch unveränderten Hintergrund
im Mittelwert verborgen werden. Im Produktionscode ergab der statische Review keinen
zusätzlichen erforderlichen Fix; der vorhandene Stand wurde beibehalten.

Im früheren Fortsetzungslauf wurden zuerst Assertions für erstellte und sichtbare
Windows-Canvas-Controls zu den beiden noch versteckt laufenden Paint-Prüfungen hinzugefügt.
Danach wurde ihr Aufbau korrigiert: `PixelationPreview` und `AnnotationExports` zeigen
das Editorformular an und verarbeiten die initialen UI-Ereignisse vor dem Einstellen der
Canvas-Größe und `DrawToBitmap`. So prüft auch der native Rotnachweis den sichtbaren
Paint-Pfad mit tatsächlich erstellten Handles. Die vorhandene native/fitted/scrolled-
Prüfung hatte diesen Aufbau bereits.

Zusätzlich prüft ein macOS-Cache-Regressionstest überlappende Pixelungen mit verschiedenen
Blockgrößen auf einer synthetischen 400×300-Aufnahme: Abgleich mit dem Export, Vektoren
zwischen Pixelungen, unveränderter Cache beim Umsortieren nur der Vektoren, geänderte
Pixelungsreihenfolge, Undo/Redo sowie Clear/Undo. Eine Fixture-Assertion fordert einen
tatsächlichen Pixelunterschied zwischen beiden Überlappungsreihenfolgen. Der Produktions-
Rendercode benötigte dabei keine weitere Änderung.

### Ergänzungen vom 2026-10-31

Zuerst wurde die fehlende Verhaltensregression für eine abgeschlossene Pixelung mit
überlagerndem transparentem Marker ergänzt (Vektor sowohl vor als auch nach der Pixelung
eingefügt). Danach wurde der gemeinsame Editor-Snapshot-Helfer um diese Annotationslisten
erweitert. Er vergleicht weiterhin den tatsächlichen Editor mit dem unabhängigen Export;
Fehlerschwellen und bestehende Assertions wurden nicht gelockert.

Der vorgesehene macOS-Vorher-Lauf war inzwischen nicht mehr kompilierbar: Die dafür
genannte Datei enthielt einen Test mit der erst im Fix eingeführten `AnnotationCanvasView`.
Dieser Test wurde unverändert nach `AnnotationCanvasRegressionTests.swift` verschoben,
als Extension derselben XCTest-Klasse. Damit bleibt er im bestehenden CI-Testfilter,
während **nur** `AnnotationRenderingRegressionTests.swift` wieder ausschließlich APIs
des Ausgangsstands verwendet. Beim Vorher-Lauf die Extension-Datei nicht übernehmen.

Die Kernumsetzung wurde beibehalten; dieser Lauf ändert keinen Produktionscode.
Der bestehende PR enthält auch einen PNG-DPI-Fix in `ImageExport.swift` samt Test aus
`d346eb8`. Das gehört fachlich zum Editor-Export (außerhalb Issue #8), wurde damals aber
zur Reparatur der bereits vorhandenen `EditorExportTests` aufgenommen. Es wurde gemäß
Fortsetzungsauftrag beibehalten und hier nicht erweitert. AC-6 vergleicht Bildpixel,
nicht identische PNG-Dateibytes oder deren DPI-Metadaten.

Die historischen Committexte der CI-Nacharbeiten enthalten fehlgeschlagene macOS-
Regressionen und einen Windows-Pixelvergleich; sie sind kein Nachweis für den aktuellen
Stand. Ein erfolgreicher Folgelauf ist ohne GitHub-Zugriff nicht feststellbar.

Der Server ist Linux; der Auftrag verbietet Build und Plattformausführung. Deshalb wurde
**kein Test vor oder nach dem Fix ausgeführt**, und insbesondere kein korrektes rotes
Testergebnis beobachtet. Neue Layout-/Cache-API-Tests benötigen den Fix bereits zum
Kompilieren. Die separaten `AnnotationRenderingRegressionTests` verwenden ausschließlich
vorhandene APIs und sind für einen echten Vorher-/Nachher-Verhaltenslauf geeignet. Auch
die erste Windows-Pixelungsassertion vergleicht den vorhandenen Paint- mit dem Exportpfad,
bevor auf die neue Cache-API zugegriffen wird; sie soll am grauen Platzhalter scheitern.

Ausgeführt und erfolgreich:

- `git diff --check`
- `git diff --no-index --check /dev/null Tests/SnapboardTests/AnnotationCanvasRegressionTests.swift`
  (Whitespace-Prüfung auch für die neue, noch ungetrackte Datei)
- `bash -n scripts/screenshots/render.sh` (nur Syntax, keine Harness-Ausführung)
- Statischer Diff-/Quellreview: unveränderte Exportarithmetik und Stile, unveränderte
  Textlayout/Export-Zeichenoperationen, Plattform-spezifische Pixelungsquellen/Überlappungsreihenfolge,
  wertbasierte Cache-Schlüssel und Windows-Bitmap-Freigabe.

## Plattform-QS für den Reviewer

### macOS

```bash
swift test --filter 'AnnotationPreviewTests|AnnotationRenderingRegressionTests|EditorExportTests'
./scripts/screenshots/render.sh --verify-text
./scripts/screenshots/render.sh --verify-annotations
```

Die Harness-Ausgaben liegen jeweils unter `build/screenshots/`. `render.sh` leert diesen
Arbeitsordner bei jedem Start; die Annotation-Prüfung zuletzt ausführen oder die jeweiligen
Artefakte vor dem nächsten Aufruf sichern. Der All-Tool-Harness nutzt die tatsächliche
Editor-Canvas. Bei eingepasster Canvas wird die Render-/Display-Skalierung so gesetzt,
dass der Vergleich wieder in Quellbildpixeln erfolgt. Keine Bildschirmaufnahme oder
Nutzerdaten; die PNGs enthalten ausschließlich synthetischen Inhalt.

Für den noch fehlenden Rotnachweis in einem separaten, sauberen Workspace auf exakt
`2306fc6` ausschließlich `AnnotationRenderingRegressionTests.swift` hinzufügen (ohne
`AnnotationCanvasRegressionTests.swift` und ohne die Cache-/Layout-Tests) und
`swift test --filter AnnotationRenderingRegressionTests` ausführen. Erwartet sind
Bildabweichungen für das kleine Retina-Rechteck und die abgeschlossene Pixelung; ein
Buildfehler wäre **kein** korrekter Verhaltensnachweis. Danach dieselben Tests mit dem Fix
ausführen. Das wurde in dieser Arbeit weder ausgeführt noch als bestanden protokolliert.

Manuell kleine und große Aufnahme mit allen Werkzeugen und 2/4/7 prüfen. Pixelung über
echtem Text visuell mit Export vergleichen; Undo/Redo und Vektorzeichnungen über zuvor
gepixelten Bereichen kontrollieren. Text und Badge-Ziffern dürfen nicht gespiegelt sein.

### Windows 10/11

```bash
dotnet build windows/Snapboard.Windows/Snapboard.Windows.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release -- --verify-annotations build/annotations-windows
```

Der letzte Befehl prüft nur Anmerkungen/Pixelung und schreibt synthetische Vergleichs-PNGs.
Der normale Regression-Runner schreibt diese Artefakte nicht. Für einen Vorher-Lauf kann
der neue Runner samt Testoracle in einem separaten Workspace auf dem Ausgangsstand
verwendet werden: Die erste echte Pixelungs-Paint-Assertion soll vor dem Cache-Zugriff
mit einer Pixelabweichung scheitern. Auch dieser Rot-/Grün-Lauf ist noch ausstehend.

Manuell abgeschlossene Pixelung mit dem kopierten Bild vergleichen, inklusive
überlappender Bereiche, Undo/Redo, eingepasster Ansicht und gescrollter 100%-Ansicht.

## Lieferung / Abhängigkeiten

Die Ergänzungen dieses Laufs liegen uncommitted im bestehenden Workspace; die bisherige
Lösung ist bereits in den oben genannten übernommenen Commits enthalten. Keine App-Abhängigkeiten
und keine neuen UI-Texte. Kein PR erstellt oder gemergt, kein Release/Deployment und keine
Produktionsdaten oder Supabase-Instanzen angefasst.

Es wurde auf dem vorhandenen eigenen PR-Stand mit der oben genannten Main-Basis gearbeitet. Aus dem lokalen
Code ergibt sich keine notwendige zusätzliche PR-Abhängigkeit; die vorhandene Windows-
Fit-/Scroll-Geometrie ist bereits in diesem Main-Stand enthalten. Ob die nicht lesbaren
Issue-Kommentare oder offenen PRs andere Abhängigkeiten nennen, bleibt vor Review zu prüfen.
