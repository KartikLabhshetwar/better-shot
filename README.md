# Better Shot

<img width="3600" height="2025" alt="stage-1768238789948" src="https://github.com/user-attachments/assets/3051266a-5179-440f-a747-7980abd7bac3" />

[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/zThjstVs) 
[![X (Twitter)](https://img.shields.io/badge/X-%231DA1F2.svg?style=for-the-badge&logo=X&logoColor=white)](https://x.com/code_kartik)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%23FFDD00.svg?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/code_kartik)

> An open-source alternative to CleanShot X for macOS. Capture, edit, and enhance your screenshots with professional quality.

Better Shot is a fast, lightweight screenshot tool built with Tauri + React. It provides a powerful yet simple workflow for capturing screenshots, editing them with backgrounds/effects/annotations, and exporting quickly.

## Table of contents

- [Better Shot](#better-shot)
  - [Table of contents](#table-of-contents)
  - [Background](#background)
  - [Features](#features)
    - [Capture Modes](#capture-modes)
    - [Image Editing](#image-editing)
    - [Annotation Tools](#annotation-tools)
    - [Workflow](#workflow)
  - [Install](#install)
    - [Download a release (recommended)](#download-a-release-recommended)
    - [Homebrew (macOS)](#homebrew-macos)
    - [Build from source](#build-from-source)
      - [Requirements](#requirements)
      - [Required permissions](#required-permissions)
  - [Usage](#usage)
    - [Quick Start](#quick-start)
    - [Auto-apply workflow](#auto-apply-workflow)
    - [Keyboard Shortcuts](#keyboard-shortcuts)
      - [Capture Shortcuts](#capture-shortcuts)
      - [Editor Shortcuts](#editor-shortcuts)
  - [Development](#development)
    - [Desktop app (Tauri)](#desktop-app-tauri)
    - [Landing site (Next.js)](#landing-site-nextjs)
  - [Contributing](#contributing)
  - [License](#license)
  - [Star history](#star-history)

## Background

Clean screenshot workflows usually need three things: capture fast, polish fast (background/shadow/roundness), and annotate fast (arrows, labels). Better Shot is a macOS-native app that keeps everything local and lightweight.

## Features

### Capture Modes

- **Region capture**: Select any area of your screen (`⌘⇧2`, enabled by default)
- **Fullscreen capture**: Capture your entire screen (`⌘⇧F`, enable in Preferences)
- **Window capture**: Capture a specific window (`⌘⇧D`, enable in Preferences)
- **OCR Region**: Extract text from a selected region using macOS Vision framework - automatically copies recognized text to clipboard (`⌘⇧O`, enable in Preferences)

### Image Editing

- **Background library**: Curated wallpapers, Mac assets, and mesh patterns
- **Custom backgrounds**: Solid colors and transparent checkerboard
- **Effects**: Blur + noise controls
- **Shadow + roundness**: Tune depth and corner radius
- **Export**: Save at high quality for docs, decks, and social

### Annotation Tools

- **Shapes**: Circle, rectangle, line, arrow
- **Text**: Add text with adjustable size
- **Numbered labels**: Auto-incrementing badges for step-by-step callouts
- **Editability**: Select, move, and delete annotations
- **Styling**: Colors, opacity, borders, alignment

### Workflow

- **Global shortcuts**: Capture from anywhere, even when hidden
- **Auto-apply**: Apply default background and save without opening the editor
- **OCR text extraction**: Extract and copy text from screenshots using native macOS Vision framework
- **Clipboard**: Copy to clipboard after capture/export
- **Preferences**: Save directory, defaults, and shortcut settings persist
- **Menu bar**: Accessible from the menu bar
- **Native performance**: Rust + Tauri

## Install

### Download a release (recommended)

1. Go to [Releases](https://github.com/KartikLabhshetwar/better-shot/releases)
2. Download the appropriate DMG file:
   - **Apple Silicon** (M1/M2/M3/M4/M5): `bettershot_*_aarch64.dmg`
   - **Intel**: `bettershot_*_x64.dmg`
3. Open the DMG and drag Better Shot to Applications
4. Launch Better Shot from Applications
5. Grant Screen Recording permission when prompted in System Settings

### Homebrew (macOS)

Install via Homebrew:

```bash
brew install --cask bettershot
```

**Requirements**: macOS >= 10.15

### Build from source

```bash
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot

pnpm install

pnpm tauri build
```

The installer will be located in `src-tauri/target/release/bundle/`

#### Requirements

- **Node.js**: 18+
- **pnpm**
- **Rust**: latest stable

#### Required permissions

On first launch, macOS will request **Screen Recording** permission:

1. Go to **System Settings → Privacy & Security → Screen Recording**
2. Enable **Better Shot**
3. Restart the application if needed

This permission is required for the app to capture screenshots of your screen.

## Usage

### Quick Start

1. Launch Better Shot from Applications (or use the menu bar icon)
2. Capture:
   - Default: `⌘⇧2` (region)
   - Optional (enable in Preferences): `⌘⇧F` (fullscreen), `⌘⇧D` (window)
3. Edit (background/effects/shadow/roundness)
4. Annotate (shapes, arrows, text, numbered labels)
5. Export: `⌘S` to save, `⇧⌘C` to copy to clipboard

### Auto-apply workflow

For faster workflows, enable **Auto-apply background** on the main screen:

1. Toggle on "Auto-apply background" on the main page
2. Set your preferred default background in Preferences
3. Capture a screenshot - it will automatically apply the background and save instantly
4. No editor needed - perfect for quick captures with consistent styling

### Keyboard Shortcuts

Capture shortcuts are customizable in Preferences.

#### Capture Shortcuts

| Action | Default Shortcut |
| --- | --- |
| Capture Region | `⌘⇧2` |
| Capture Fullscreen | `⌘⇧F` (disabled by default) |
| Capture Window | `⌘⇧D` (disabled by default) |
| OCR Region | `⌘⇧O` (disabled by default) |
| Cancel Selection | `Esc` |

#### Editor Shortcuts

| Action | Shortcut |
| --- | --- |
| Save Image | `⌘S` |
| Copy to Clipboard | `⇧⌘C` |
| Undo | `⌘Z` |
| Redo | `⇧⌘Z` |
| Delete Annotation | `Delete` or `Backspace` |
| Close Editor | `Esc` |

## Development

This repo contains:

- The **desktop app** (Tauri + Vite) at the repo root
- The **landing site** (Next.js) in `bettershot-landing/`

### Desktop app (Tauri)

```bash
pnpm tauri dev
```

Other useful commands:

```bash
pnpm lint:ci
pnpm test:rust
pnpm tauri build
```

### Landing site (Next.js)

```bash
cd bettershot-landing
pnpm install
pnpm dev
```

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

## Star history

<a href="https://www.star-history.com/#KartikLabhshetwar/better-shot&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&legend=top-left" />
 </picture>
</a>
