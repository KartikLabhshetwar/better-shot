<img width="3600" height="2025" alt="stage-1768238789948" src="https://github.com/user-attachments/assets/3051266a-5179-440f-a747-7980abd7bac3" />


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
- **Shadow Effects** - Add depth with customizable shadows (blur, offset, opacity)
- **Border Radius** - Control image roundness for modern aesthetics
- **High-Quality Export** - Export at maximum quality for presentations and documentation

### Annotation Tools

- **Drawing Tools** - Circle, rectangle, line, and arrow annotations
- **Text Annotations** - Add customizable text with adjustable font size
- **Number Labels** - Auto-incrementing numbered badges for step-by-step guides
- **Customizable Properties** - Full control over colors, opacity, borders, and alignment
- **Interactive Editing** - Select, move, and delete annotations with mouse or keyboard
- **Professional Styling** - Fine-tune fill colors, border widths, and opacity for each annotation

### Workflow

- **Global Hotkeys** - Capture from anywhere, even when the app is hidden
- **Customizable Shortcuts** - Configure your own keyboard shortcuts in Preferences
- **Auto-apply Background** - Instantly apply default background with shadow effects and save without opening editor
- **Clipboard Integration** - Automatically copy screenshots to clipboard
- **Custom Save Directory** - Choose where your screenshots are saved (defaults to Desktop)
- **Settings Persistence** - All preferences are saved and restored automatically
- **System Tray Integration** - Access from the menu bar
- **Native Performance** - Built with Rust and Tauri for minimal resource usage

### Preferences

- **General Settings** - Configure save directory and clipboard behavior
- **Default Background** - Set a default background for auto-apply mode
- **Keyboard Shortcuts** - Customize capture shortcuts with enable/disable toggles

### Why Better Shot?

- **100% Free & Open Source** - No subscriptions, no paywalls
- **Lightweight** - Minimal resource usage compared to Electron apps
- **Beautiful UI** - Modern, dark-themed interface
- **Privacy First** - All processing happens locally, no cloud uploads
- **Fast** - Native performance with Rust backend

## Installation

### Download Pre-built Release

1. Go to [Releases](https://github.com/KartikLabhshetwar/better-shot/releases)
2. Download the appropriate DMG file:
   - **Apple Silicon** (M1, M2, M3): `bettershot_*_aarch64.dmg`
   - **Intel Mac**: `bettershot_*_x64.dmg`
3. Open the DMG and drag Better Shot to Applications
4. **First Launch** (choose one method):
   
   **Option A: Right-Click Method** (Easiest)
   - Right-click the app → **Open** → Click **Open** in the dialog
   
   **Option B: Terminal Method** (One command, no dialogs) (recommended)
   ```bash
   xattr -d com.apple.quarantine /Applications/bettershot.app
   ```
   
5. Grant Screen Recording permission when prompted

> **Note**: Better Shot is ad-hoc signed (free indie app). macOS Gatekeeper shows a warning for apps not notarized through Apple's $99/year developer program. The app is safe - you can [view the source code](https://github.com/KartikLabhshetwar/better-shot) and build it yourself.

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
4. **Edit** - Add backgrounds, effects, blur, shadows, and adjust border radius
5. **Annotate** - Use the annotation toolbar to add shapes, arrows, text, and numbered labels
6. **Customize** - Select any annotation to adjust colors, opacity, borders, and other properties
7. **Export** - Press `⌘S` to save or `⌘⇧C` to copy to clipboard

### Quick Workflow with Auto-apply

For faster workflows, enable **Auto-apply background** on the main screen:

1. Toggle on "Auto-apply background" on the main page
2. Set your preferred default background in Preferences
3. Capture a screenshot - it will automatically apply the background and save instantly
4. No editor needed - perfect for quick captures with consistent styling

### Keyboard Shortcuts

Shortcuts are customizable in Preferences. Default shortcuts:

| Action | Shortcut |
| --- | --- |
| Capture Region | `⌘⇧2` |
| Capture Fullscreen | `⌘⇧3` |
| Capture Window | `⌘⇧4` |
| Save Image | `⌘S` |
| Copy to Clipboard | `⌘⇧C` |
| Delete Annotation | `Delete` or `Backspace` |
| Cancel | `Esc` |

### Typical Workflow

1. **Capture**: Use global hotkeys from anywhere or click buttons in the app
2. **Select**: For region capture, click and drag to select the area you want
3. **Edit**: Customize with backgrounds, gradients, blur effects, shadows, and roundness controls
4. **Annotate**: Add shapes, arrows, text, and numbered labels to highlight important areas
5. **Customize**: Select annotations to adjust colors, opacity, borders, and alignment
6. **Export**: Save to your chosen directory or copy directly to clipboard for instant sharing

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
  - `image` - Image processing
  - `@tauri-apps/plugin-store` - Settings persistence
  - `@tauri-apps/plugin-global-shortcut` - Global hotkeys

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
