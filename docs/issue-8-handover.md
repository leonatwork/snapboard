# Issue #8 – Review-Handover

## Ausgangsstand und verbindlicher Umfang

Basis: ausgechecktes `origin/main`, `2306fc6e8e357a64980c9674b273825f52e8844f`.
Der Workspace war vor der Arbeit sauber. Kein Branchwechsel, kein fremder PR-Code,
kein Cherry-Pick, Commit oder Push.

Grundlage ist die im Auftrag vollständig mitgelieferte strukturierte Issue-Beschreibung
inklusive Originalbeschreibung. Der Versuch, den GitHub-Thread und offene PRs mit `gh`
zu lesen, wurde durch die Werkzeugberechtigungen abgewiesen. Kommentare, zusätzliche
Entscheidungen und mögliche offene PR-Abhängigkeiten sind daher **nicht geprüft**.
`CLAUDE.md` und `AGENTS.md` wurden im Workspace nicht gefunden; Zugriff außerhalb des
Workspaces ist gesperrt. `CONTRIBUTING.md`, Paket-/Testkonfiguration, bestehende Tests
und Build-Workflow wurden gelesen; die Wissensbasis wurde abgefragt.

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
| AC-5 | Windows cached eine mit `ApplyBlur` erzeugte Bildlage, einschließlich Reihenfolge überlappender Bereiche. Native/fitted Paint-, Cache-, Geometrieänderungs-, Undo-/Redo- und Randfalltests. | Implementiert, Windows-Lauf offen |
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

Zuerst wurden `AnnotationPreviewTests`, die Windows-Pixelungsregression und der neue
Vergleichsharness samt eingefrorenem macOS-Exportrenderer angelegt; erst danach wurden
die Produktionsdateien geändert. Im anschließenden Review kamen zusätzliche direkte
Editor-Paint-Regressionen und der Windows-All-Tool-Exportvergleich hinzu.

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

Alle Änderungen liegen uncommitted im bestehenden Workspace. Keine App-Abhängigkeiten
und keine neuen UI-Texte. Kein PR erstellt oder gemergt, kein Release/Deployment und keine
Produktionsdaten oder Supabase-Instanzen angefasst.

Es wurde ausschließlich auf dem genannten `origin/main`-Stand gearbeitet. Aus dem lokalen
Code ergibt sich keine notwendige zusätzliche PR-Abhängigkeit; die vorhandene Windows-
Fit-/Scroll-Geometrie ist bereits in diesem Main-Stand enthalten. Ob die nicht lesbaren
Issue-Kommentare oder offenen PRs andere Abhängigkeiten nennen, bleibt vor Review zu prüfen.
