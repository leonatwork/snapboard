# Screenie 📸

> Schlanke, native macOS Menüleisten-App als Ersatz für Greenshot.

**Screenie** wurde speziell entwickelt, um Bildschirmausschnitte blitzschnell mit dem gewohnten Tastaturkürzel **`Cmd + Shift + 1`** (`⌘ ⇧ 1`) aufzunehmen und direkt in die **Zwischenablage** zu kopieren – **vollständig ohne Dateien auf der Festplatte zu speichern**.

---

## ✨ Features

- ⚡ **Globaler Shortcut `⌘ ⇧ 1`**: Funktioniert überall im System, ohne Fokus-Verlust.
- 📋 **Direkt in die Zwischenablage**: Nach der Bereichsauswahl liegt das Bild sofort in `NSPasteboard` bereit für `⌘ V`.
- 🛡️ **Kein Festplattenmüll**: Speichert garantiert keine Dateien auf dem Schreibtisch oder in Ordnern.
- 🪶 **Schlank & Nativ**: Läuft unauffällig als Menüleisten-Symbol (`LSUIElement`), keine störenden Dock-Icons oder Fenster.
- 🔔 **Audio-Feedback**: Dezenter Sound bei erfolgreicher Aufnahme (im Menü umschaltbar).
- 🚀 **Autostart-Unterstützung**: Kann mit einem Klick so eingestellt werden, dass es beim Mac-Start automatisch läuft.
- ⚙️ **Modernes Einstellungsfenster**: Schnelle Konfiguration über SwiftUI.

---

## ⌨️ Bedienung

| Aktion | Tastenkombination |
| :--- | :--- |
| **Bereich aufnehmen** | `⌘ + ⇧ + 1` (`Cmd + Shift + 1`) |
| **Ganzes Fenster auswählen** | `Leertaste` während des Auswahlmodus |
| **Aufnahme abbrechen** | `ESC` |
| **Bild einfügen** | `⌘ + V` in beliebiger App (Slack, Pages, Teams, Photoshop, etc.) |

---

## 🛠️ Bauen & Installieren

### 1-Klick Installation nach `/Applications`:
```bash
./scripts/install.sh
```

### Manuelles Bauen:
```bash
./scripts/build_app.sh
```
Das fertige Bundle liegt anschließend in `build/Screenie.app`.
