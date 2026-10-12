# Snapboard 📸⚡

[![Build Snapboard](https://github.com/leonatwork/snapboard/actions/workflows/build.yml/badge.svg)](https://github.com/leonatwork/snapboard/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/leonatwork/snapboard?color=success&label=Release)](https://github.com/leonatwork/snapboard/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows-lightgrey.svg)]()

> The lightweight, privacy-focused Greenshot alternative for **macOS** and **Windows**.
> Capture screen areas directly to your clipboard — **without saving unnecessary files to disk**.

*🇩🇪 [Deutsche Version](README.de.md)*

---

## 📥 Download & Installation

You can download Snapboard straight from GitHub and use it without touching a terminal:

| Platform | Download | Installation |
| :--- | :--- | :--- |
| 🍏 **macOS** (Apple Silicon & Intel) | [**Download Snapboard-macOS.zip**](https://github.com/leonatwork/snapboard/releases/latest/download/Snapboard-macOS.zip) | Unzip and drag `Snapboard.app` into your **Applications** folder |
| 🪟 **Windows** (x64) | [**Download Snapboard-Windows-x64.zip**](https://github.com/leonatwork/snapboard/releases/latest/download/Snapboard-Windows-x64.zip) | Unzip and double-click `Snapboard.exe` |

👉 All versions are also listed under [**GitHub Releases**](https://github.com/leonatwork/snapboard/releases).

---

## 🖼️ Screenshots

<div align="center">
  <h3>Annotation & Redaction Studio (⌘ ⇧ 2 / Ctrl + Shift + 2)</h3>
  <img src="docs/screenshots/editor.png" alt="Snapboard Editor" width="800" />
  <br /><br />
  <h3>Preferences & Global Shortcuts</h3>
  <img src="docs/screenshots/settings.png" alt="Snapboard Settings" width="480" />
</div>

---

## ✨ Features

- ⚡ **Zero-click clipboard capture**: select an area and paste it straight into any app with `⌘ V` / `Ctrl + V`.
- 🎨 **Built-in annotation studio**:
  - ⭕ **Circles & ellipses**
  - ⬜ **Rectangles & frames**
  - ➡️ **Arrows**
  - ✏️ **Freehand pen**
  - 🖍️ **Highlighter** (semi-transparent)
  - 🌫️ **Redaction / pixelate**: obscure passwords, bank details, names and the like
  - 🔤 **Text boxes**
  - ① **Step counter (1, 2, 3…)**: auto-incrementing badges for walkthroughs
- 🛡️ **No disk clutter**: works entirely in memory — no temporary or leftover screenshot files.
- 🪶 **Native & lightweight**: sits quietly in the menu bar (macOS) or system tray (Windows).
- 🚀 **Launch at login**: one click to start with the system.

---

## ⌨️ Shortcuts

### 🍎 macOS
| Shortcut | Mode | Action |
| :--- | :--- | :--- |
| **`⌘ + ⇧ + 1`** | **Direct capture** | Select an area → **straight to the clipboard** (zero clicks) |
| **`⌘ + ⇧ + 2`** | **Capture & edit** | Select an area → **opens the Snapboard editor** |
| `Space` | Window mode | Capture a specific window during selection |
| `ESC` | Cancel | Abort the capture without touching the clipboard |
| `⌘ + C` / `Enter` | Export (in editor) | Copy the edited image and close the editor |
| `⌘ + S` | Save as… | Optionally export as a PNG file |

### 🪟 Windows
| Shortcut | Mode | Action |
| :--- | :--- | :--- |
| **`Ctrl + Shift + 1`** | **Direct capture** | Select an area → **straight to the clipboard** (zero clicks) |
| **`Ctrl + Shift + 2`** | **Capture & edit** | Select an area → **opens the Snapboard editor** |
| `ESC` | Cancel | Abort the capture |
| `Ctrl + C` | Export (in editor) | Copy the edited image and close the editor |
| `Ctrl + S` | Save as… | Optionally export as a PNG file |

---

## 🛠️ Building from source

### 🍎 macOS
```bash
# one-click install into /Applications
./scripts/install.sh

# or build manually
./scripts/build_app.sh
```

### 🪟 Windows
```cmd
cd windows
dotnet publish Snapboard.Windows\Snapboard.Windows.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o bin\Release
```

---

## 🤝 Contributing

Bug reports and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## 💎 Open source & premium

Snapboard is and stays open source under the MIT License. Everything in this repository
remains free to use, modify and share.

Two ways to support the project are planned:

- **Sponsoring**: voluntary support for ongoing development. The link follows here as soon
  as it is set up.
- **Premium add-ons**: optional extra features, offered as a separate paid package. They
  build on the free core and never take features away from it.

---

## 📄 License

Released under the [MIT License](LICENSE).
