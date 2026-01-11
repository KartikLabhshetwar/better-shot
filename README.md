# Better Shot

An open-source, cross-platform screenshot application built with Tauri, React, and scap.

## Development

### Prerequisites

- Rust (for Tauri backend)
- Node.js and pnpm (for frontend)
- Platform-specific screen capture permissions (macOS will prompt automatically)

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

### VS Code (Recommended)

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

### Alternative IDEs

- **Cursor**: Can use the same VS Code configuration files
- **Neovim**: See [Tauri debugging guide](https://v2.tauri.app/develop/debug/neovim) for nvim-dap setup
