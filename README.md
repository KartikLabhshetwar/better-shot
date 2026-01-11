# Better Shot

A fast, lightweight screenshot tool for macOS with region selection and image editing.

## Features

- **Region Capture** - Select any area of your screen with pixel-perfect precision
- **Image Editor** - Add backgrounds, gradients, and effects to enhance your screenshots
- **Clipboard Support** - Automatically copy screenshots to clipboard
- **Global Hotkey** - Quick capture with `Cmd+Shift+2` from anywhere
- **Lightweight** - Built with Tauri for native performance and minimal resource usage
- **Professional Quality** - Export high-quality images perfect for presentations and documentation

## Installation

### For End Users

#### Option 1: Download Pre-built Binary (Recommended)

1. Download the latest release from the [Releases page](https://github.com/yourusername/better-shot/releases)
2. Extract the `.dmg` file
3. Drag **Better Shot** to your **Applications** folder
4. Open from Applications (first launch may require right-click → Open due to macOS security)

#### Option 2: Build from Source

If you prefer to build from source, you'll need:

**Prerequisites:**
- [Rust](https://www.rust-lang.org/tools/install) (latest stable)
- [Node.js](https://nodejs.org/) (v18 or higher)
- [pnpm](https://pnpm.io/)

**Build Steps:**

```bash
# Clone the repository
git clone https://github.com/yourusername/better-shot.git
cd better-shot

# Install dependencies
pnpm install

# Build the application
pnpm tauri build
```

The installer will be located in `src-tauri/target/release/bundle/`

### Required Permissions

On first launch, macOS will request **Screen Recording** permission:

1. Go to **System Settings → Privacy & Security → Screen Recording**
2. Enable **Better Shot**
3. Restart the application if needed

This permission is required for the app to capture screenshots of your screen.

## Usage

### Quick Start

1. **Launch the app** - Open Better Shot from Applications
2. **Capture a region** - Press `Cmd+Shift+2` or click "Capture Region"
3. **Select area** - Click and drag to select the area you want to capture
4. **Edit** - Add backgrounds, effects, or adjust styling
5. **Save** - Press `Cmd+S` to save or `Cmd+Shift+C` to copy to clipboard

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Capture Region | `⌘⇧2` |
| Save Image | `⌘S` |
| Copy to Clipboard | `⌘⇧C` |
| Cancel | `Esc` |

### Workflow

1. **Capture**: Use the global hotkey or click "Capture Region" button
2. **Select**: Click and drag to select the area you want to screenshot
3. **Edit**: Customize with backgrounds, gradients, effects, and roundness controls
4. **Export**: Save to disk or copy directly to clipboard for instant sharing

## Development

To run the app in development mode:

```bash
pnpm tauri dev
```

This will:
- Start the Vite dev server for the frontend
- Compile the Rust backend
- Launch the Tauri application window with hot-reload

## License

See [LICENSE](LICENSE)
