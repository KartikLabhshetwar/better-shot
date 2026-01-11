# Setup Instructions for Better Shot

## Step 1: Install Dependencies

Make sure all dependencies are installed:

```bash
# Install frontend dependencies
pnpm install

# Rust dependencies will be installed automatically when building
```

## Step 2: Run the Application

### Option A: Using pnpm (Recommended)

```bash
pnpm tauri dev
```

This will:
1. Start the Vite dev server for the frontend
2. Compile the Rust backend
3. Launch the Tauri application window

### Option B: Using VS Code

1. Open the project in VS Code:
   ```bash
   code .
   ```

2. Install recommended extensions (VS Code will prompt you)

3. Press `F5` or go to Run and Debug panel
   - Select "Tauri Development Debug"
   - This will build and run the app

### Option C: Using Cargo directly

```bash
cd src-tauri
cargo build
cargo run
```

## Troubleshooting

### If build fails:

1. **Clean build cache:**
   ```bash
   cd src-tauri
   cargo clean
   cd ..
   ```

2. **Rebuild:**
   ```bash
   pnpm tauri dev
   ```

### If you get permission errors:

On macOS, you'll need to grant screen recording permissions:
1. Go to System Settings → Privacy & Security → Screen Recording
2. Enable Better Shot (or Terminal if running from terminal)

## Development Workflow

1. **Start dev server:**
   ```bash
   pnpm tauri dev
   ```

2. **Make changes:**
   - Frontend changes (React/TypeScript) will hot-reload automatically
   - Rust changes require a rebuild (automatic with `tauri dev`)

3. **Stop the app:**
   - Press `Ctrl+C` in the terminal

## Building for Production

```bash
pnpm tauri build
```

This creates platform-specific installers in `src-tauri/target/release/bundle/`
