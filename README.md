# Better Shot

A cross-platform screenshot capture and editing application built with Tauri, React, and TypeScript. Better Shot provides powerful tools for capturing screenshots, selecting regions, and editing images with customizable backgrounds.

## Features

- **Cross-Platform Support**: Works on macOS, Linux, and Windows
- **Multiple Capture Modes**:
  - Quick capture of primary monitor (hotkey: `Cmd/Ctrl+Shift+S`)
  - Region selection across multiple monitors
  - Full monitor capture with geometry information
- **Image Editing**: Edit screenshots with customizable backgrounds:
  - Transparent background
  - Solid colors (white, black, gray)
  - Gradient backgrounds
  - Custom color backgrounds
- **Automatic Desktop Saving**: Screenshots are automatically saved to your Desktop directory (cross-platform detection)
- **Clipboard Integration**: Option to copy screenshots to clipboard automatically
- **Multi-Monitor Support**: Capture and select regions across multiple displays
- **Global Hotkeys**: Quick access via keyboard shortcuts

## Installation

### Prerequisites

- **Rust** (latest stable version) - [Install Rust](https://www.rust-lang.org/tools/install)
- **Node.js** (v18 or later) - [Install Node.js](https://nodejs.org/)
- **pnpm** - Install via `npm install -g pnpm`
- **Platform-specific dependencies**:
  - **macOS**: Xcode Command Line Tools (`xcode-select --install`)
  - **Linux**: Development tools and libraries (varies by distribution)
  - **Windows**: Microsoft Visual C++ Build Tools

### Building from Source

1. Clone the repository:
```bash
git clone <repository-url>
cd better-shot
```

2. Install dependencies:
```bash
pnpm install
```

3. Build the application:
```bash
pnpm tauri build
```

The built application will be available in `src-tauri/target/release/bundle/` with platform-specific installers.

## Usage

### Quick Capture

Press `Cmd+Shift+S` (macOS) or `Ctrl+Shift+S` (Windows/Linux) to quickly capture your primary monitor. The screenshot will be saved to your Desktop and optionally copied to clipboard.

### Region Selection

1. Click the "Capture Region" button in the application window
2. The application will hide and display a selection overlay across all monitors
3. Click and drag to select the region you want to capture
4. The selected region will open in the image editor

### Image Editing

After capturing a region, you can:
- Choose from various background options (transparent, solid colors, gradients, custom)
- Preview your changes in real-time
- Save the edited image to your Desktop
- Optionally copy to clipboard

### Save Directory

By default, all screenshots are saved to your Desktop directory. The application automatically detects the Desktop path on:
- **macOS**: `~/Desktop`
- **Linux**: `~/Desktop` (or `~/desktop` depending on locale)
- **Windows**: `%USERPROFILE%\Desktop`

You can change the save directory in the application settings if needed.

## Development

### Running in Development Mode

```bash
pnpm tauri dev
```

This command will:
- Start the Vite development server for the frontend
- Compile the Rust backend in debug mode
- Launch the Tauri application window
- Enable hot-reload for frontend changes

### Project Structure

```
better-shot/
├── src/                    # Frontend React/TypeScript code
│   ├── components/         # React components
│   ├── App.tsx            # Main application component
│   └── App.css            # Application styles
├── src-tauri/              # Tauri backend (Rust)
│   ├── src/
│   │   ├── commands.rs    # Tauri command handlers
│   │   ├── screenshot.rs  # Screenshot capture logic
│   │   ├── image.rs       # Image processing utilities
│   │   ├── clipboard.rs   # Clipboard operations
│   │   ├── utils.rs       # Utility functions
│   │   └── lib.rs         # Application entry point
│   ├── Cargo.toml         # Rust dependencies
│   └── tauri.conf.json    # Tauri configuration
├── package.json           # Node.js dependencies
└── README.md             # This file
```

### Testing

**Rust Tests:**
```bash
cd src-tauri
cargo test
```

**Type Checking:**
```bash
pnpm lint:ci
```

### IDE Setup

#### VS Code (Recommended)

VS Code configuration files are included in `.vscode/` directory. When you open the project in VS Code, you'll be prompted to install recommended extensions:

1. **Install Recommended Extensions:**
   - Open VS Code in this project directory
   - Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
   - Type "Extensions: Show Recommended Extensions"
   - Install all recommended extensions:
     - [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) - Tauri framework support
     - [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer) - Rust language support
     - [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) - Debugging support for Rust
     - [Prettier](https://marketplace.visualstudio.com/items?itemName=esbenp.prettier-vscode) - Code formatter

2. **Debugging:**
   - Press `F5` or go to Run and Debug panel
   - Select "Tauri Development Debug" configuration
   - This will build the Rust backend and start the frontend dev server

3. **Tasks:**
   - Press `Cmd+Shift+P` / `Ctrl+Shift+P`
   - Type "Tasks: Run Task"
   - Available tasks:
     - `build:debug` - Build Rust backend in debug mode
     - `ui:dev` - Start frontend dev server
     - `ui:build` - Build frontend for production
     - `dev` - Combined task (build + dev server)

#### Alternative IDEs

- **Cursor**: Can use the same VS Code configuration files
- **Neovim**: See [Tauri debugging guide](https://v2.tauri.app/develop/debug/neovim) for nvim-dap setup

## Platform-Specific Notes

### macOS

**Permissions Required:**
- Screen Recording: Required for capturing screenshots
  - Go to System Settings → Privacy & Security → Screen Recording
  - Enable Better Shot (or Terminal if running from terminal)

**Building:**
- Requires Xcode Command Line Tools
- May require code signing for distribution

### Linux

**Dependencies:**
- Development headers for X11 or Wayland
- GTK libraries (for some distributions)
- libxcb, libxcb-shm, libxcb-xfixes

**Distribution-Specific:**
- **Ubuntu/Debian**: `sudo apt-get install libgtk-3-dev libwebkit2gtk-4.0-dev libappindicator3-dev librsvg2-dev`
- **Fedora**: `sudo dnf install webkit2gtk3-devel.x86_64 openssl-devel curl libappindicator-gtk3 librsvg2-devel`
- **Arch**: `sudo pacman -S webkit2gtk base-devel curl libappindicator-gtk3 librsvg libvips`

### Windows

**Requirements:**
- Microsoft Visual C++ Build Tools
- Windows SDK
- WebView2 runtime (usually pre-installed on Windows 10/11)

## Troubleshooting

### Build Failures

**Clean Build Cache:**
```bash
cd src-tauri
cargo clean
cd ..
pnpm tauri dev
```

**Permission Errors (macOS):**
- Ensure Screen Recording permission is granted in System Settings
- Restart the application after granting permissions

**Missing Dependencies (Linux):**
- Install platform-specific dependencies listed above
- Ensure all development headers are installed

### Runtime Issues

**Screenshots Not Saving:**
- Verify Desktop directory exists and is writable
- Check application logs for error messages
- Ensure sufficient disk space

**Hotkey Not Working:**
- Check if another application is using the same hotkey
- Verify global shortcut permissions (may require additional permissions on some systems)

**Multi-Monitor Issues:**
- Ensure all monitors are properly detected by the system
- Try restarting the application if monitor configuration changed

## Building for Production

```bash
pnpm tauri build
```

This creates platform-specific installers:
- **macOS**: `.dmg` and `.app` bundle
- **Linux**: `.deb`, `.AppImage`, or `.rpm` (depending on target)
- **Windows**: `.msi` installer

Output location: `src-tauri/target/release/bundle/`

## Contributing

Contributions are welcome! Please ensure that:
- Code follows existing style and patterns
- Tests pass for any new functionality
- Documentation is updated as needed

## License

see [LICENSE](LICENSE) file for full details.
