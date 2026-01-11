# Better Shot

An open-source, cross-platform screenshot application built with Tauri, React, and scap.

## Development

### Prerequisites

- Rust (for Tauri backend)
- Node.js and pnpm (for frontend)
- **macOS**: Full Xcode installation (not just Command Line Tools) - required by `scap` dependency `cidre`
  - Install from App Store or [developer.apple.com](https://developer.apple.com/xcode/)
  - After installation, verify with: `xcode-select -p`
  - If it shows `/Library/Developer/CommandLineTools`, switch to Xcode:

    ```bash
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
    ```

  - Accept Xcode license: `sudo xcodebuild -license accept`
- Platform-specific screen capture permissions

### Running

```bash
pnpm install
pnpm tauri dev
```

### Testing

- **Rust tests**: `pnpm test:rust` or `cd src-tauri && cargo test`
- **Type checking**: `pnpm lint:ci` (requires eslint setup)

### Building

```bash
pnpm tauri build
```

## Recommended IDE Setup

- [VS Code](https://code.visualstudio.com/) + [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)
