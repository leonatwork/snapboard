# Screenie 📸

> Die schlanke, native macOS Screenshot- & Anmerkungs-App als perfekter Ersatz für Greenshot.

**Screenie** kombiniert blitzschnelles Kopieren von Screenshots in die Zwischenablage mit einem integrierten Editor für Pfeile, Einkreisen, Textmarker, Zensieren/Blur und Schrittzähler – **vollständig ohne Dateien auf der Festplatte zu speichern**.

---

## ⌨️ Globale Tastaturkürzel

| Shortcut | Modus | Verhalten |
| :--- | :--- | :--- |
| **`⌘ + ⇧ + 1`** | **Direkt-Modus** | Bereich markieren → **Sofort in die Zwischenablage** (0 Klicks) |
| **`⌘ + ⇧ + 2`** | **Editor-Modus** | Bereich markieren → **Öffnet den Screenie-Editor** |

---

## 🎨 Editor-Werkzeuge (`⌘ ⇧ 2`)

Im Editor stehen dir alle wichtigen Werkzeuge direkt zur Verfügung:

- ⭕ **Einkreisen / Ellipse**: Zum Hervorheben runder Elemente oder Icons.
- ⬜ **Rechteck / Rahmen**: Zum Einrahmen von Absätzen, Buttons oder Tabellen.
- ➡️ **Pfeile**: Zeigt präzise auf wichtige Stellen.
- 🖊️ **Stift (Freihand)**: Freies Skizzieren und Zeichnen.
- 🖍️ **Highlighter / Textmarker**: Halbtransparentes Markieren von Textzeilen.
- 🌫️ **Zensieren / Blur**: Sensible Informationen (Passwörter, IBANs, Namen) mit einem Klick unkenntlich machen.
- 🔤 **Textfelder**: Beliebige Beschriftungen und Notizen einfügen.
- ① **Schrittzähler (1, 2, 3...)**: Automatisch hochzählende Nummern-Badges für Schritt-für-Schritt Anleitungen.
- 🎨 **Farbauswahl & Strichstärken**: 8 Farben (Rot, Gelb, Grün, Blau, Weiß, Schwarz etc.) + 3 Strichstärken.
- ↩️ **Undo / Redo**: Volle Unterstützung für `⌘ Z` und `⌘ ⇧ Z`.

---

## 🚀 Schnelle Tasten im Editor

- **`⌘ + C`** oder **`Enter`**: Kopiert das fertig bearbeitete Bild in voller Auflösung in die Zwischenablage und schließt das Fenster.
- **`⌘ + S`**: Optionales "Speichern als Datei..." (falls man doch mal eine PNG benötigt).
- **`ESC`**: Editor ohne Kopieren schließen.

---

## 🛠️ Bauen & Installieren

### 1-Klick Installation:
```bash
./scripts/install.sh
```

### Manuelles Bauen:
```bash
./scripts/build_app.sh
```
Das fertige Bundle liegt in `build/Screenie.app`.
