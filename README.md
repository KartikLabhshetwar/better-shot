# Better Shot

A fast, lightweight screenshot tool for macOS with region selection and image editing.

## Features

- **Region Capture** - Select any area of your screen
- **Image Editor** - Add backgrounds, gradients, and effects
- **Clipboard Support** - Auto-copy screenshots
- **Global Hotkey** - `Cmd+Shift+2` for quick capture

## Install

### Prerequisites

- [Rust](https://www.rust-lang.org/tools/install)
- [Node.js](https://nodejs.org/) (v18+)
- [pnpm](https://pnpm.io/)

### Build

```bash
pnpm install
pnpm tauri build
```

## Usage

1. Press `Cmd+Shift+2` or click "Capture Region"
2. Click and drag to select area
3. Edit with backgrounds/effects
4. Save or copy to clipboard

## Development

```bash
pnpm tauri dev
```

## Permissions

On macOS, enable **Screen Recording** permission:
System Settings > Privacy & Security > Screen Recording

## License

See [LICENSE](LICENSE)
