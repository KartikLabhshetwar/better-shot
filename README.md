# Better Shot

> An open-source alternative to CleanShot X for macOS. Capture, edit, and enhance your screenshots with professional quality.

Better Shot is a fast, lightweight screenshot tool built with Tauri and React. It provides a powerful yet simple interface for capturing screenshots, editing them with beautiful backgrounds and effects, and sharing them instantly.

## Features

### Capture Modes

- **Region Capture** - Select any area of your screen with pixel-perfect precision (`⌘⇧2`)
- **Fullscreen Capture** - Capture your entire screen instantly (`⌘⇧3`)
- **Window Capture** - Capture a specific window with one click (`⌘⇧4`)

### Image Editing

- **Background Library** - Choose from curated wallpapers, Mac assets, and mesh patterns
- **Custom Backgrounds** - Solid colors, gradients, or transparent checkerboard
- **Visual Effects** - Adjustable blur and noise for professional polish
- **Border Radius** - Control image roundness for modern aesthetics
- **High-Quality Export** - Export at maximum quality for presentations and documentation

### Workflow

- **Global Hotkeys** - Capture from anywhere, even when the app is hidden
- **Clipboard Integration** - Automatically copy screenshots to clipboard
- **Custom Save Directory** - Choose where your screenshots are saved
- **System Tray Integration** - Access from the menu bar
- **Native Performance** - Built with Rust and Tauri for minimal resource usage

### Why Better Shot?

- **100% Free & Open Source** - No subscriptions, no paywalls
- **Lightweight** - Minimal resource usage compared to Electron apps
- **Beautiful UI** - Modern, dark-themed interface
- **Privacy First** - All processing happens locally, no cloud uploads
- **Fast** - Native performance with Rust backend

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot

# Install dependencies
pnpm install

# Build the application
pnpm tauri build
```

The installer will be located in `src-tauri/target/release/bundle/`

### Requirements

- **macOS**: 10.15 or later
- **Node.js**: 18 or higher
- **pnpm**: Latest version
- **Rust**: Latest stable version (for building from source)

### Required Permissions

On first launch, macOS will request **Screen Recording** permission:

1. Go to **System Settings → Privacy & Security → Screen Recording**
2. Enable **Better Shot**
3. Restart the application if needed

This permission is required for the app to capture screenshots of your screen.

## Usage

### Quick Start

1. **Launch the app** - Open Better Shot from Applications or use the menu bar icon
2. **Capture** - Use global hotkeys (`⌘⇧2`, `⌘⇧3`, or `⌘⇧4`) or click buttons in the app
3. **Select** - For region capture, click and drag to select the area
4. **Edit** - Add backgrounds, effects, blur, and adjust border radius
5. **Export** - Press `⌘S` to save or `⌘⇧C` to copy to clipboard

### Keyboard Shortcuts

| Action              | Shortcut   |
| ------------------- | ---------- |
| Capture Region      | `⌘⇧2`      |
| Capture Fullscreen  | `⌘⇧3`      |
| Capture Window      | `⌘⇧4`      |
| Save Image          | `⌘S`       |
| Copy to Clipboard   | `⌘⇧C`      |
| Cancel              | `Esc`      |

### Typical Workflow

1. **Capture**: Use global hotkeys from anywhere or click buttons in the app
2. **Select**: For region capture, click and drag to select the area you want
3. **Edit**: Customize with backgrounds, gradients, blur effects, and roundness controls
4. **Export**: Save to your chosen directory or copy directly to clipboard for instant sharing

## Development

To run the app in development mode:

```bash
pnpm tauri dev
```

This will:

- Start the Vite dev server for the frontend
- Compile the Rust backend
- Launch the Tauri application window with hot-reload

### Development Setup

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed development setup and contribution guidelines.

### Tech Stack

- **Frontend**: React 19, TypeScript, Tailwind CSS 4, Vite
- **Backend**: Rust, Tauri 2
- **Key Libraries**:
  - `xcap` - Screenshot capture
  - `arboard` - Clipboard operations
  - `image` - Image processing

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a pull request.

### Ways to Contribute

- Report bugs
- Suggest new features
- Submit pull requests
- Improve documentation
- Star the project

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

---
