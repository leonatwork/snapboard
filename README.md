# Snapboard 📸⚡

[![Build Snapboard](https://github.com/leonatwork/snapboard/actions/workflows/build.yml/badge.svg)](https://github.com/leonatwork/snapboard/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows-lightgrey.svg)]()

> The lightweight, privacy-focused Greenshot alternative for **macOS** and **Windows**. 
> Capture screen areas directly to your clipboard — **without saving unnecessary files to disk**.

---

## ✨ Features

- ⚡ **Zero-Click Clipboard Capture**: Select a region and have it immediately ready in your clipboard for `⌘ V` / `Ctrl + V`.
- 🎨 **Built-In Annotation & Redaction Studio**:
  - ⭕ **Circles & Ellipses**
  - ⬜ **Rectangles & Frames**
  - ➡️ **Arrows & Pointers**
  - ✏️ **Freehand Pen**
  - 🖍️ **Highlighter / Marker**
  - 🌫️ **Blur / Pixelate (Redact)**: Easily obscure sensitive info like passwords, IBANs, or names.
  - 🔤 **Text Callouts**
  - ① **Step Badges (1, 2, 3...)**: Auto-incrementing numbers for step-by-step guides.
- 🛡️ **Zero Disk Pollution**: Operates entirely in RAM; no leftover screenshots cluttering your Desktop or Downloads.
- 🪶 **Native & Lightweight**: Runs silently in the menu bar (macOS) or system tray (Windows).
- 🚀 **Autostart Support**: Toggle "Launch at Login" with a single click.

---

## ⌨️ Shortcuts

### 🍎 macOS
| Shortcut | Mode | Action |
| :--- | :--- | :--- |
| **`⌘ + ⇧ + 1`** | **Direct Capture** | Select region → **Instantly to Clipboard** (0 clicks) |
| **`⌘ + ⇧ + 2`** | **Capture & Edit** | Select region → **Opens Snapboard Editor** |
| `Space` | Window Mode | Capture specific window during selection |
| `ESC` | Cancel | Abort capture without touching clipboard |
| `⌘ + C` / `Enter` | Export (in Editor) | Copy edited image to clipboard and close |
| `⌘ + S` | Save As (in Editor) | Optional save to PNG file |

### 🪟 Windows
| Shortcut | Mode | Action |
| :--- | :--- | :--- |
| **`Ctrl + Shift + 1`** | **Direct Capture** | Select region → **Instantly to Clipboard** (0 clicks) |
| **`Ctrl + Shift + 2`** | **Capture & Edit** | Select region → **Opens Snapboard Editor** |
| `ESC` | Cancel | Abort capture |
| `Ctrl + C` | Export (in Editor) | Copy edited image to clipboard and close |
| `Ctrl + S` | Save As (in Editor) | Optional save to PNG file |

---

## 🚀 Installation & Getting Started

### 🍎 macOS

#### 1-Click Install to `/Applications`:
```bash
./scripts/install.sh
```

#### Manual Build:
```bash
./scripts/build_app.sh
```
The compiled bundle will be placed in `build/Snapboard.app`.

---

### 🪟 Windows

Requirements: [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

#### Build & Publish (Standalone EXE):
```cmd
cd windows
dotnet publish Snapboard.Windows\Snapboard.Windows.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o bin\Release
```

---

## 🛠️ Architecture

- **macOS**: Swift 6, SwiftUI, AppKit, Carbon HotKeys, CoreImage, ServiceManagement (`SMAppService`).
- **Windows**: C#, .NET 8, WPF / WinForms, Windows API HotKeys (`user32.dll`), Registry Autostart.

---

## 📄 License

Distributed under the [MIT License](LICENSE).
