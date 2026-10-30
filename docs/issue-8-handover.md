# Issue #8 – Review-Handover

## Ausgangsstand und verbindlicher Umfang

Basis der vorhandenen Lösung: lokales `origin/main`,
`2306fc6e8e357a64980c9674b273825f52e8844f`.
Dieser Fortsetzungslauf startete sauber auf dem bereits ausgecheckten Branch
`agent/bearbeite-github-issue-8-vollst-ndig-und-1026-2301`, Commit
`094905c8ee6bfea04b74a0a406da79c46c0c146d` (laut Auftrag der eigene Stand von PR #17).
Die beiden vorhandenen Commits `46f2210` und `094905c` und ihr Diff gegen `origin/main`
wurden geprüft und beibehalten.
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
| AC-7 | Bestehendes Textlayout und Textpreview-Zeichenweg unverändert; eigener All-Tool-Harness mit 48 Fällen und je zwei macOS-Canvas-Größen. | Beide Harness-Läufe offen |
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

Im aktuellen Fortsetzungslauf wurden zuerst Assertions für erstellte und sichtbare
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
Rendercode benötigte im aktuellen statischen Review keine weitere Änderung.

Der Server ist Linux; der Auftrag verbietet Build und Plattformausführung. Deshalb wurde
**kein Test vor oder nach dem Fix ausgeführt**, und insbesondere kein korrektes rotes
Testergebnis beobachtet. Neue Layout-/Cache-API-Tests benötigen den Fix bereits zum
Kompilieren. Die separaten `AnnotationRenderingRegressionTests` verwenden ausschließlich
vorhandene APIs und sind für einen echten Vorher-/Nachher-Verhaltenslauf geeignet. Auch
die erste Windows-Pixelungsassertion vergleicht den vorhandenen Paint- mit dem Exportpfad,
bevor auf die neue Cache-API zugegriffen wird; sie soll am grauen Platzhalter scheitern.

Ausgeführt und erfolgreich:

- `git diff --check`
- `bash -n scripts/screenshots/render.sh` (nur Syntax, keine Harness-Ausführung)
- Statischer Diff-/Quellreview: unveränderte Exportarithmetik und Stile, unveränderte
  Textimplementierung, Plattform-spezifische Pixelungsquellen/Überlappungsreihenfolge,
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
`2306fc6` ausschließlich `AnnotationRenderingRegressionTests.swift` hinzufügen und
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
Lösung ist bereits in den beiden übernommenen Commits enthalten. Keine App-Abhängigkeiten
und keine neuen UI-Texte. Kein PR erstellt oder gemergt, kein Release/Deployment und keine
Produktionsdaten oder Supabase-Instanzen angefasst.

Es wurde auf dem vorhandenen eigenen PR-Stand mit der oben genannten Main-Basis gearbeitet. Aus dem lokalen
Code ergibt sich keine notwendige zusätzliche PR-Abhängigkeit; die vorhandene Windows-
Fit-/Scroll-Geometrie ist bereits in diesem Main-Stand enthalten. Ob die nicht lesbaren
Issue-Kommentare oder offenen PRs andere Abhängigkeiten nennen, bleibt vor Review zu prüfen.
