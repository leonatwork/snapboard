# Issue #5: macOS Retina-Export – Handover

## Grundlage und offene Nachweise

- Issue: <https://github.com/leonatwork/snapboard/issues/5>
- Ausgangsstand: `6aac49f51ce9964c1b038f016fddfe9db45e103c`; `HEAD` entsprach dem
  lokalen `origin/main`, Arbeitsbaum vor Beginn sauber. Kein Branchwechsel.
- `CONTRIBUTING.md`, `Package.swift`, Build-Workflow und die relevanten Quellen und
  QS-Skripte wurden gelesen. Im Workspace sind keine `CLAUDE.md` oder `AGENTS.md`
  vorhanden. Die Wissensbasis wurde nach Regeln und Testkonventionen gefragt;
  auf diesem Stand existierte kein Swift-Testtarget.
- Der vollständige GitHub-Thread und offene PRs konnten **nicht geprüft** werden:
  Der lesende `gh`-Aufruf wurde durch die Tool-Berechtigungen gesperrt. Verbindliche
  Grundlage dieser Umsetzung ist daher der im Auftrag bereitgestellte Issue-Text.
  Kommentare, PR-Überschneidungen und der aktuelle Remote-Stand müssen vor Lieferung
  auf GitHub nachgeprüft werden. Im lokalen Code ist keine PR-Abhängigkeit erkennbar;
  die Lösung basiert vollständig auf dem oben genannten Main-Stand.
- **Widerspruch im Prüfauftrag:** Ausgeführte Red-/Green-Tests und macOS-QS sind
  gefordert, zugleich verbieten die zusätzlichen Regeln Build und Ausführung auf
  diesem Linux-Server ohne Swift/Xcode/AppKit. Es wurden deshalb keine App-, Test-
  oder QS-Skripte ausgeführt. Ein grüner `build-macos`-Job ist nicht nachgewiesen.

## Umsetzung und Akzeptanzkriterien

Die strukturierte Beschreibung verlangt bei AC-6 Fehlermeldungen sowohl beim
Kopieren als auch beim Speichern; beide Wege sind berücksichtigt. PNG soll vor
TIFF angeboten werden, Fehler zeigen `localizedDescription` und nur „OK“.

| Kriterium | Umsetzung / Regressionstest | Noch erforderlicher Nachweis |
| --- | --- | --- |
| AC-1: Notes-Größe wie Direktaufnahme | Renderer übernimmt exakt `image.size`; Test für unveränderte Punktgröße ohne Anmerkung auf 2x | Vergleich von ⌘⇧1 und ⌘⇧2 in Notes auf Retina-Mac |
| AC-2: Aufnahme-Pixelmaße bei Anmerkungen | CGContext-Abmessungen unverändert; Tests prüfen Render-, PNG- und TIFF-Pixelbreite/-höhe | Testlauf und Mac-Prüfung |
| AC-3: PNG und TIFF im Pasteboard | Ein `NSPasteboardItem` mit PNG zuerst und TIFF als Fallback; Test mit isoliertem Pasteboard prüft erforderliche Typen, relative Reihenfolge und DPI | Testlauf und Prüfung von `NSPasteboard.general` |
| AC-4: gespeichertes PNG mit Aufnahmebreite und 144 dpi | `NSBitmapImageRep(cgImage:)`, anschließend `bitmap.size = image.size`; PNG direkt daraus, ohne TIFF-Umweg. Test prüft ImageIO-Metadaten | Testlauf und `sips` auf Retina-Aufnahme |
| AC-5: Schreibfehler lokalisiert, Editor bleibt offen | `do/catch` reicht Systemfehler unverändert an `NSAlert` weiter; Test provoziert Schreibfehler über fehlenden Elternordner und prüft Anmerkungen/Undo | Testlauf und lokalisierter Alert beim Speichern in schreibgeschützten Ordner |
| AC-6: Renderfehler beim Kopieren/Speichern sichtbar | Beide Wege melden lokalisierten Fehler; Kopieren schließt nur nach Erfolg. Tests prüfen Meldung, offenen Editor, erhaltene Anmerkungen und unverändertes Clipboard bei Renderfehler | Testlauf und visuelle Alert-Prüfung |
| AC-7: 1x unverändert | Dieselben Größen- und Metadatentests auf 1x (72 dpi) | Testlauf und Wiederholung auf 1x-Bildschirm |
| AC-8: Lokalisierungen und Text-Harness erfolgreich | Vier neue Schlüssel in allen zehn `.lproj`-Dateien; Text-/Anmerkungszeichnung unverändert | Beide vorgeschriebenen Skripte auf macOS |

Die Größenlogik besteht nun aus unveränderter Übernahme der Quell-Punktgröße,
ohne Skalierungsberechnung oder feste 2x-Annahme. Eine zusätzliche reine
Identitätsfunktion wurde deshalb nicht eingeführt. Die gemeinsame Kodierung ist
in `Sources/Models/ImageExport.swift` isoliert und über die Exporttests prüfbar.
Die Vorschau-/Exportabweichungen anderer Anmerkungen bleiben außerhalb des Umfangs.

## Testgetriebenes Vorgehen und Review

1. Zuerst `Tests/SnapboardTests/EditorExportTests.swift` und ein abhängigkeitsfreies
   XCTest-Target in `Package.swift` ergänzt, danach den Produktionscode geändert.
2. Vor dem Fix statisch nachvollzogen: Für 320×180 Pixel auf 2x erwartet der
   Render-Test 160×90 Punkte; der alte Renderer liefert 320×180 Punkte. Das ist
   **kein ausgeführter Red-Nachweis**. Die Tests der Fehlerwege verwenden neue
   Injektionsparameter und waren auf dem ursprünglichen Code noch nicht kompilierbar.
3. Testfälle: Renderer ohne/mit Anmerkung, PNG-/TIFF-Pasteboarddaten einschließlich
   Reihenfolge und DPI, gespeichertes PNG, Renderfehler beider Aktionen, Schreibfehler
   mit erhaltenen Anmerkungen/Undo und Abbruch des Speicherdialogs.
4. Tests verwenden ein benanntes, isoliertes Pasteboard und temporäre Dateipfade;
   sie ersetzen keine echte Aufnahme oder den Notes-Vergleich. PNG-DPI wird mit
   0,02 dpi Toleranz geprüft, da PNG ganzzahlige Pixel-pro-Meter-Werte speichert.
5. Statischer Review: PNG und TIFF werden vor dem Leeren des Pasteboards erzeugt;
   beide stammen aus derselben Bitmap mit Quell-Punktgröße. Schreib-, Render- und
   Kodierfehler ändern weder Anmerkungen noch Undo/Redo. Das Text-Harness vergleicht
   CGImage-Pixel, nicht die geänderte NSImage-Punktgröße.
6. `git diff --check` erfolgreich. Die vier neuen Schlüssel sind in allen zehn
   Sprachdateien vorhanden, ohne Formatplatzhalter; dies ersetzt kein `plutil`-Lint.

## Nachzuholende Prüfungen auf macOS

```bash
swift test --filter EditorExportTests
scripts/check-localizations.sh
scripts/screenshots/render.sh --verify-text
```

Zusätzlich muss der bestehende CI-Job `build-macos` grün sein. Das Build-Skript
baut die App; es führt das neue Testtarget nicht automatisch aus.

Manuell auf einem Retina-Mac:

1. Identischen Bereich mit ⌘⇧1 und ⌘⇧2 aufnehmen; ohne Anmerkung in Notes einfügen
   und Größe/Schärfe vergleichen. Mit Anmerkungen wiederholen.
2. Nach Editor-Kopie `NSPasteboard.general.types` prüfen: mindestens `public.png`
   und `public.tiff`, PNG vor TIFF; zusätzliche Plattform-Aliase sind zulässig.
3. Editor-PNG speichern und `sips -g pixelWidth -g dpiWidth "/Pfad/Export.png"`
   prüfen: Aufnahme-Pixelbreite, 144 dpi. Pixelhöhe ebenfalls mit Aufnahme vergleichen.
4. Als normaler Benutzer in einen schreibgeschützten Testordner speichern:
   lokalisierter Alert mit Systembeschreibung und einzigem „OK“-Button;
   Editor einschließlich Anmerkungen und Undo bleibt erhalten.
5. Für einen kontrollierten Renderfehler im Debugger/Testpfad ein Bild ohne
   Bitmap-Repräsentation verwenden; beide Aktionen melden den Fehler und bleiben offen.
6. Auf einem echten 1x-Bildschirm wiederholen: ursprüngliche Punkt-/Pixelmaße,
   72 dpi. Ein skalierter Retina-Modus allein ist kein sicherer 1x-Nachweis.

Status: Code und Regressionstests liegen zur Review im Arbeitsbaum; Laufzeit-,
CI- und GitHub-Thread/PR-Nachweise sind offen. Kein Commit, Push oder PR angelegt.
