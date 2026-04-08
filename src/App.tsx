import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { migrateStoredValue, isAssetId, isDataUrl } from "@/lib/asset-registry";
import { hasCompletedOnboarding } from "@/lib/onboarding";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { availableMonitors } from "@tauri-apps/api/window";
import { getCurrentWindow, LogicalSize, PhysicalPosition } from "@tauri-apps/api/window";
import { register, unregister } from "@tauri-apps/plugin-global-shortcut";
import { Store } from "@tauri-apps/plugin-store";
import type { KeyboardShortcut } from "./components/preferences/KeyboardShortcutManager";
import { SettingsIcon } from "./components/SettingsIcon";
import { AppWindowMac, Crop, ImageUp, Monitor } from "lucide-react";
import { toast } from "sonner";
import { lazy, Suspense, useCallback, useEffect, useRef, useState } from "react";
import { editorActions } from "@/stores/editorStore";

// Lazy load heavy components
const ImageEditor = lazy(() => import("./components/ImageEditor").then(m => ({ default: m.ImageEditor })));
const OnboardingFlow = lazy(() => import("./components/onboarding/OnboardingFlow").then(m => ({ default: m.OnboardingFlow })));
const PreferencesPage = lazy(() => import("./components/preferences/PreferencesPage").then(m => ({ default: m.PreferencesPage })));

type AppMode = "main" | "editing" | "preferences";
type CaptureMode = "region" | "fullscreen" | "window";

// Loading fallback for lazy loaded components
function LoadingFallback() {
  return (
    <div className="min-h-dvh flex items-center justify-center bg-background">
      <div className="flex items-center gap-2 text-muted-foreground">
        <svg className="animate-spin size-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span>Loading...</span>
      </div>
    </div>
  );
}

const DEFAULT_SHORTCUTS: KeyboardShortcut[] = [
  { id: "region", action: "Capture Region", shortcut: "CommandOrControl+Shift+2", enabled: true },
  { id: "fullscreen", action: "Capture Screen", shortcut: "CommandOrControl+Shift+F", enabled: false },
  { id: "window", action: "Capture Window", shortcut: "CommandOrControl+Shift+D", enabled: false },
];

function formatShortcut(shortcut: string): string {
  return shortcut
    .replace(/CommandOrControl/g, "⌘")
    .replace(/Command/g, "⌘")
    .replace(/Control/g, "⌃")
    .replace(/Shift/g, "⇧")
    .replace(/Alt/g, "⌥")
    .replace(/Option/g, "⌥")
    .replace(/\+/g, "");
}

async function restoreWindowOnScreen(mouseX?: number, mouseY?: number) {
  const appWindow = getCurrentWindow();
  const windowWidth = 1200;
  const windowHeight = 800;
  await appWindow.setSize(new LogicalSize(windowWidth, windowHeight));
  if (mouseX !== undefined && mouseY !== undefined) {
    try {
      const monitors = await availableMonitors();
      
      const targetMonitor = monitors.find((monitor) => {
        const pos = monitor.position;
        const size = monitor.size;
        return (
          mouseX >= pos.x &&
          mouseX < pos.x + size.width &&
          mouseY >= pos.y &&
          mouseY < pos.y + size.height
        );
      });

      if (targetMonitor) {
        const scaleFactor = targetMonitor.scaleFactor;
        const physicalWindowWidth = windowWidth * scaleFactor;
        const physicalWindowHeight = windowHeight * scaleFactor;
        const centerX = targetMonitor.position.x + (targetMonitor.size.width - physicalWindowWidth) / 2;
        const centerY = targetMonitor.position.y + (targetMonitor.size.height - physicalWindowHeight) / 2;
        
        await appWindow.setPosition(new PhysicalPosition(centerX, centerY));
      } else {
        await appWindow.center();
      }
    } catch {
      await appWindow.center();
    }
  } else {
    await appWindow.center();
  }

  await appWindow.show();
  await appWindow.setFocus();
}

async function restoreWindow() {
  await restoreWindowOnScreen();
}

function App() {
  const [mode, setMode] = useState<AppMode>("main");
  const [saveDir, setSaveDir] = useState<string>("");
  const [filenamePrefix, setFilenamePrefix] = useState<string>("bettershot");
  const [copyToClipboard, setCopyToClipboard] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isCapturing, setIsCapturing] = useState(false);
  const [tempScreenshotPath, setTempScreenshotPath] = useState<string | null>(null);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [shortcuts, setShortcuts] = useState<KeyboardShortcut[]>(DEFAULT_SHORTCUTS);
  const [settingsVersion, setSettingsVersion] = useState(0);
  const [tempDir, setTempDir] = useState<string>("/tmp");
  const [isSelectingFile, setIsSelectingFile] = useState(false);

  // Refs to hold current values for use in callbacks that may have stale closures
  const settingsRef = useRef({ saveDir, copyToClipboard, tempDir, filenamePrefix });
  const registeredShortcutsRef = useRef<Set<string>>(new Set());

  // Keep ref in sync with state
  useEffect(() => {
    settingsRef.current = { saveDir, copyToClipboard, tempDir, filenamePrefix };
  }, [saveDir, copyToClipboard, tempDir, filenamePrefix]);

  // Load settings function
  const loadSettings = useCallback(async () => {
    try {
      const store = await Store.load("settings.json", {
        defaults: {
          copyToClipboard: true,
        },
        autoSave: true,
      });

      const savedCopyToClip = await store.get<boolean>("copyToClipboard");
      if (savedCopyToClip !== null && savedCopyToClip !== undefined) {
        setCopyToClipboard(savedCopyToClip);
      }

      const savedSaveDir = await store.get<string>("saveDir");
      if (savedSaveDir) {
        setSaveDir(savedSaveDir);
      }

      const savedFilenamePrefix = await store.get<string>("filenamePrefix");
      if (savedFilenamePrefix && savedFilenamePrefix.trim() !== "") {
        setFilenamePrefix(savedFilenamePrefix.trim());
      }

      const savedShortcuts = await store.get<KeyboardShortcut[]>("keyboardShortcuts");
      if (savedShortcuts && savedShortcuts.length > 0) {
        // Merge saved shortcuts with defaults, preserving all saved values
        // Only add missing default shortcuts that don't exist in saved
        const savedIds = new Set(savedShortcuts.map((s) => s.id));
        const missingDefaults = DEFAULT_SHORTCUTS.filter((d) => !savedIds.has(d.id));
        const finalShortcuts = [...savedShortcuts, ...missingDefaults];
        setShortcuts(finalShortcuts);
      } else {
        setShortcuts(DEFAULT_SHORTCUTS);
      }
    } catch (err) {
      console.error("Failed to load settings:", err);
    }
  }, []);

  // Initial app setup
  useEffect(() => {
    const initializeApp = async () => {
      // First get the desktop path as the default
      let desktopPath = "";
      try {
        desktopPath = await invoke<string>("get_desktop_directory");
      } catch (err) {
        console.error("Failed to get Desktop directory:", err);
        setError(`Failed to get Desktop directory: ${err instanceof Error ? err.message : String(err)}`);
      }

      // Get the system temp directory (canonicalized to resolve symlinks)
      try {
        const systemTempDir = await invoke<string>("get_temp_directory");
        setTempDir(systemTempDir);
      } catch (err) {
        console.error("Failed to get temp directory, using fallback:", err);
        // Keep the default /tmp fallback
      }

      // Load settings from store
      try {
        const store = await Store.load("settings.json", {
          defaults: {
            copyToClipboard: true,
          },
          autoSave: true,
        });

        const savedCopyToClip = await store.get<boolean>("copyToClipboard");
        if (savedCopyToClip !== null && savedCopyToClip !== undefined) {
          setCopyToClipboard(savedCopyToClip);
        }

        // Only use saved directory if it's a non-empty string, otherwise use desktop
        const savedSaveDir = await store.get<string>("saveDir");
        if (savedSaveDir && savedSaveDir.trim() !== "") {
          setSaveDir(savedSaveDir);
        } else {
          // Use desktop as default and save it
          setSaveDir(desktopPath);
          if (desktopPath) {
            await store.set("saveDir", desktopPath);
          }
        }

        const savedFilenamePrefix = await store.get<string>("filenamePrefix");
        const finalPrefix = savedFilenamePrefix && savedFilenamePrefix.trim() !== ""
          ? savedFilenamePrefix.trim()
          : "bettershot";
        setFilenamePrefix(finalPrefix);
        await store.set("filenamePrefix", finalPrefix);
        await store.save();

        const savedShortcuts = await store.get<KeyboardShortcut[]>("keyboardShortcuts");
        if (savedShortcuts && savedShortcuts.length > 0) {
          setShortcuts(savedShortcuts);
        }

        // Migrate legacy background image paths to asset IDs
        const savedBackgroundImage = await store.get<string>("defaultBackgroundImage");
        if (savedBackgroundImage && !isAssetId(savedBackgroundImage) && !isDataUrl(savedBackgroundImage)) {
          // This is a legacy path that needs migration
          const migratedValue = migrateStoredValue(savedBackgroundImage);
          if (migratedValue && migratedValue !== savedBackgroundImage) {
            console.log(`Migrating background image: ${savedBackgroundImage} -> ${migratedValue}`);
            await store.set("defaultBackgroundImage", migratedValue);
            await store.save();
          }
        }
      } catch (err) {
        console.error("Failed to load settings:", err);
        // Still set desktop as fallback
        if (desktopPath) {
          setSaveDir(desktopPath);
        }
      }
    };

    initializeApp();

    const shouldShowOnboarding = !hasCompletedOnboarding();
    if (shouldShowOnboarding) {
      setShowOnboarding(true);
    }

    // DEV ONLY: Uncomment to test editor with any image file
    // setTempScreenshotPath("/Users/montimage/Desktop/bettershot_1768263844426.png");
    // setMode("editing");
  }, []);


  const handleCapture = useCallback(async (captureMode: CaptureMode = "region") => {
    if (isCapturing) return;
    
    setIsCapturing(true);
    setError(null);

    const appWindow = getCurrentWindow();
    
    // Read current settings from ref to avoid stale closure issues
    const { tempDir: currentTempDir } = settingsRef.current;

    try {
      await appWindow.hide();
      await new Promise((resolve) => setTimeout(resolve, 400));

      const commandMap: Record<CaptureMode, string> = {
        region: "native_capture_interactive",
        fullscreen: "native_capture_fullscreen",
        window: "native_capture_window",
      };

      const screenshotPath = await invoke<string>(commandMap[captureMode], {
        saveDir: currentTempDir,
      });

      // Get mouse position IMMEDIATELY after screenshot completes
      // This captures where the user finished their selection
      let mouseX: number | undefined;
      let mouseY: number | undefined;
      try {
        const [x, y] = await invoke<[number, number]>("get_mouse_position");
        mouseX = x;
        mouseY = y;
      } catch {
        // Silently fail - will fall back to centering
      }

      invoke("play_screenshot_sound").catch(console.error);

      setTempScreenshotPath(screenshotPath);
      setMode("editing");
      try {
        await invoke("move_window_to_active_space");
      } catch {
      }
      await restoreWindowOnScreen(mouseX, mouseY);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      if (errorMessage.includes("cancelled") || errorMessage.includes("was cancelled")) {
        await restoreWindow();
      } else if (errorMessage.includes("already in progress")) {
        setError("Please wait for the current screenshot to complete");
        await restoreWindow();
      } else if (
        errorMessage.toLowerCase().includes("permission") ||
        errorMessage.toLowerCase().includes("access") ||
        errorMessage.toLowerCase().includes("denied")
      ) {
        setError(
          "Screen Recording permission required. Please go to System Settings > Privacy & Security > Screen Recording and enable access for Better Shot, then restart the app."
        );
        await restoreWindow();
      } else {
        setError(errorMessage);
        await restoreWindow();
      }
    } finally {
      setIsCapturing(false);
    }
  }, [isCapturing]);

  // Setup hotkeys whenever settings change
  useEffect(() => {
    const setupHotkeys = async () => {
      try {
        const shortcutsToUnregister = Array.from(registeredShortcutsRef.current);
        if (shortcutsToUnregister.length > 0) {
          try {
            await unregister(shortcutsToUnregister);
          } catch (err) {
            console.error("Failed to unregister shortcuts:", err);
          }
        }
        registeredShortcutsRef.current.clear();
        
        const actionMap: Record<string, CaptureMode> = {
          "Capture Region": "region",
          "Capture Screen": "fullscreen",
          "Capture Window": "window",
        };

        for (const shortcut of shortcuts) {
          if (!shortcut.enabled) continue;
          
          const action = actionMap[shortcut.action];
          if (action) {
            try {
              await register(shortcut.shortcut, () => handleCapture(action));
              registeredShortcutsRef.current.add(shortcut.shortcut);
            } catch (err) {
              console.error(`Failed to register shortcut ${shortcut.shortcut}:`, err);
            }
          }
        }
      } catch (err) {
        console.error("Failed to setup hotkeys:", err);
        setError(`Hotkey registration failed: ${err instanceof Error ? err.message : String(err)}`);
      }
    };

    setupHotkeys();

    return () => {
      const shortcutsToUnregister = Array.from(registeredShortcutsRef.current);
      if (shortcutsToUnregister.length > 0) {
        unregister(shortcutsToUnregister).catch(console.error);
      }
      registeredShortcutsRef.current.clear();
    };
  }, [shortcuts, settingsVersion, handleCapture]);

  // Setup tray menu event listeners - only once on mount
  // Use a ref to hold the latest handleCapture to avoid re-registering listeners
  const handleCaptureRef = useRef(handleCapture);
  useEffect(() => {
    handleCaptureRef.current = handleCapture;
  }, [handleCapture]);

  useEffect(() => {
    let unlisten1: (() => void) | null = null;
    let unlisten2: (() => void) | null = null;
    let unlisten3: (() => void) | null = null;
    let mounted = true;

    const setupListeners = async () => {
      // Use refs to always call the latest handler without re-registering
      unlisten1 = await listen("capture-triggered", () => {
        if (mounted) handleCaptureRef.current("region");
      });
      unlisten2 = await listen("capture-fullscreen", () => {
        if (mounted) handleCaptureRef.current("fullscreen");
      });
      unlisten3 = await listen("capture-window", () => {
        if (mounted) handleCaptureRef.current("window");
      });
    };

    setupListeners();

    return () => {
      mounted = false;
      unlisten1?.();
      unlisten2?.();
      unlisten3?.();
    };
  }, []); // Empty dependency array - only run once on mount

  // Reload settings when coming back from preferences
  const handleSettingsChange = useCallback(async () => {
    await loadSettings();
    setSettingsVersion(v => v + 1);
  }, [loadSettings]);

  const handleBackFromPreferences = useCallback(async () => {
    await loadSettings();
    setSettingsVersion(v => v + 1);
    setMode("main");
  }, [loadSettings]);

  const handleSaveDirChange = useCallback(async (newDir: string) => {
    setSaveDir(newDir);
    try {
      const store = await Store.load("settings.json");
      await store.set("saveDir", newDir);
      await store.save();
    } catch (err) {
      console.error("Failed to save directory:", err);
      toast.error("Failed to update save directory");
    }
  }, []);

  const [isPermissionDialogOpen, setIsPermissionDialogOpen] = useState(false);

  const handleUploadButtonClick = useCallback(() => {
    setIsPermissionDialogOpen(true);
  }, []);

  const handlePermissionDialogClose = useCallback(() => {
    if (!isSelectingFile) {
      setIsPermissionDialogOpen(false);
    }
  }, [isSelectingFile]);

  const handlePermissionDialogConfirm = useCallback(async () => {
    if (isSelectingFile) return;

    setError(null);
    setIsSelectingFile(true);

    try {
      const selected = await invoke<string | null>("open_image_file_dialog");

      if (!selected) {
        setIsPermissionDialogOpen(false);
        return;
      }

      const sandboxedPath = await invoke<string>("copy_file_to_temp_workspace", {
        sourcePath: selected,
      });

      setTempScreenshotPath(sandboxedPath);
      setMode("editing");
      await restoreWindow();
      setIsPermissionDialogOpen(false);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(errorMessage);
      toast.error("Failed to open image", {
        description: errorMessage,
        duration: 5000,
      });
    } finally {
      setIsSelectingFile(false);
    }
  }, [isSelectingFile]);

  async function handleEditorSave(editedImageData: string, filenameOverride?: string) {
    try {
      const savedPath = await invoke<string>("save_edited_image", {
        imageData: editedImageData,
        saveDir,
        copyToClip: copyToClipboard,
        prefix: "bettershot",
        filename: filenameOverride,
      });

      toast.success("Image saved", {
        description: savedPath,
        duration: 4000,
      });

      // Clean up sandboxed temp file if it came from the upload flow
      if (tempScreenshotPath?.includes("bettershot-uploads")) {
        invoke("delete_temp_workspace_file", { filePath: tempScreenshotPath }).catch(console.error);
      }

      editorActions.reset();
      setMode("main");
      setTempScreenshotPath(null);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(errorMessage);
      toast.error("Failed to save image", {
        description: errorMessage,
        duration: 5000,
      });
      editorActions.reset();
      setMode("main");
    }
  }

  async function handleEditorCancel() {
    // Clean up sandboxed temp file if it came from the upload flow
    if (tempScreenshotPath?.includes("bettershot-uploads")) {
      invoke("delete_temp_workspace_file", { filePath: tempScreenshotPath }).catch(console.error);
    }
    editorActions.reset();
    setMode("main");
    setTempScreenshotPath(null);
  }

  // Get shortcut display for a specific action
  const getShortcutDisplay = (actionId: string): string => {
    const shortcut = shortcuts.find(s => s.id === actionId);
    if (shortcut && shortcut.enabled) {
      return formatShortcut(shortcut.shortcut);
    }
    // Fallback to defaults
    const defaultShortcut = DEFAULT_SHORTCUTS.find(s => s.id === actionId);
    return defaultShortcut ? formatShortcut(defaultShortcut.shortcut) : "—";
  };

  if (mode === "editing" && tempScreenshotPath) {
    return (
      <Suspense fallback={<LoadingFallback />}>
        <ImageEditor
          imagePath={tempScreenshotPath}
          onSave={handleEditorSave}
          onCancel={handleEditorCancel}
          saveDir={saveDir}
          onSaveDirChange={handleSaveDirChange}
        />
      </Suspense>
    );
  }

  if (showOnboarding) {
    return (
      <Suspense fallback={<LoadingFallback />}>
        <OnboardingFlow
          onComplete={() => {
            setShowOnboarding(false);
          }}
        />
      </Suspense>
    );
  }

  if (mode === "preferences") {
    return (
      <Suspense fallback={<LoadingFallback />}>
        <PreferencesPage 
          onBack={handleBackFromPreferences} 
          onSettingsChange={handleSettingsChange}
        />
      </Suspense>
    );
  }

  return (
    <>
      <main className="min-h-dvh flex flex-col items-center justify-center p-8 bg-background text-foreground">
        <div className="w-full max-w-2xl space-y-6">
        <div className="relative text-center space-y-2">
          <div className="absolute top-0 right-0">
            <SettingsIcon onClick={() => setMode("preferences")} />
          </div>
          <div className="flex flex-col items-center gap-1">
            <div className="flex items-center gap-2">
              <h1 className="text-5xl font-bold text-foreground text-balance">Better Shot</h1>
              <span className="rounded-full border border-border bg-card px-2 py-0.5 text-xs font-medium text-muted-foreground tabular-nums">
                v{__APP_VERSION__}
              </span>
            </div>
            <p className="text-muted-foreground text-sm text-pretty">Capture, edit, and enhance your screenshots with professional quality.</p>
          </div>
        </div>

        <Card className="bg-card border-border">
          <CardContent className="p-6 space-y-6">
            <div className="grid grid-cols-3 gap-3">
              <Button
                onClick={() => handleCapture("region")}
                disabled={isCapturing}
                variant="cta"
                size="lg"
                className="py-3 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <Crop className="size-4" aria-hidden="true" />
                Region
              </Button>
              <Button
                onClick={() => handleCapture("fullscreen")}
                disabled={isCapturing}
                variant="cta"
                size="lg"
                className="py-3 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <Monitor className="size-4" aria-hidden="true" />
                Screen
              </Button>
              <Button
                onClick={() => handleCapture("window")}
                disabled={isCapturing}
                variant="cta"
                size="lg"
                className="py-3 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <AppWindowMac className="size-4" aria-hidden="true" />
                Window
              </Button>
            </div>

        <div className="space-y-1">
          <Button
            onClick={handleUploadButtonClick}
            disabled={isCapturing || isSelectingFile}
            variant="outline"
            size="lg"
            className="w-full justify-center py-3 disabled:cursor-not-allowed"
          >
            <ImageUp className="size-4" aria-hidden="true" />
            Upload photo to edit
          </Button>
          <p className="text-xs text-muted-foreground text-center text-pretty">
            Bring an existing image into the editor without taking a new screenshot.
          </p>
        </div>

            {isCapturing && (
              <div className="flex items-center justify-center gap-2 text-muted-foreground text-sm">
                <svg className="animate-spin size-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Waiting for selection...
              </div>
            )}

            {error && (
              <div className="p-4 bg-red-950/30 border border-red-800/50 rounded-lg">
                <div className="font-medium text-red-300 mb-1">Error</div>
                <div className="text-red-400 text-sm text-pretty">{error}</div>
              </div>
            )}
          </CardContent>
        </Card>

        <Card className="bg-card border-border">
          <CardContent className="p-5 space-y-4">
            <h3 className="font-medium text-foreground text-sm">Keyboard Shortcuts</h3>
            
            {/* Capture Shortcuts */}
            <div className="space-y-2">
              <p className="text-xs text-muted-foreground uppercase tracking-wide">Capture</p>
              <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Region</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">
                    {getShortcutDisplay("region")}
                  </kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Screen</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">
                    {getShortcutDisplay("fullscreen")}
                  </kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Window</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">
                    {getShortcutDisplay("window")}
                  </kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Cancel</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">Esc</kbd>
                </div>
              </div>
            </div>

            {/* Editor Shortcuts */}
            <div className="space-y-2">
              <p className="text-xs text-muted-foreground uppercase tracking-wide">Editor</p>
              <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Save</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">⌘S</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Copy</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">⇧⌘C</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Undo</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">⌘Z</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Redo</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">⇧⌘Z</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Delete annotation</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">⌫</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Close editor</span>
                  <kbd className="px-2 py-1 bg-secondary border border-border rounded text-foreground font-mono text-xs tabular-nums">Esc</kbd>
                </div>
              </div>
          </div>
        </CardContent>
      </Card>

      <Dialog
        open={isPermissionDialogOpen}
          onOpenChange={(open) => {
            if (!open) {
              handlePermissionDialogClose();
            } else {
              setIsPermissionDialogOpen(true);
            }
          }}
      >
        <DialogContent className="max-w-lg rounded-lg space-y-4">
          <DialogHeader>
            <DialogTitle className="text-lg text-foreground text-balance">Grant photo access</DialogTitle>
            <DialogDescription className="text-sm text-muted-foreground text-pretty">
              Better Shot needs to copy the photo into a secure temporary folder ($TEMP/bettershot) so it can safely render it in the editor without needing permanent access to the original directory.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2 text-sm text-muted-foreground text-pretty">
            <p>We will:</p>
            <ul className="list-disc list-inside">
              <li>Ask you to pick the photo via Finder.</li>
              <li>Copy it into a sandboxed temp folder that is already trusted.</li>
              <li>Open the copied file inside the editor and delete it once you close the session.</li>
            </ul>
          </div>
          <DialogFooter className="flex justify-end gap-2">
            <Button
              variant="ghost"
              onClick={handlePermissionDialogClose}
              disabled={isSelectingFile}
            >
              Cancel
            </Button>
            <Button
              variant="cta"
              onClick={handlePermissionDialogConfirm}
              disabled={isSelectingFile}
            >
              {isSelectingFile ? "Opening picker…" : "Grant access & pick photo"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      </div>
    </main>
    </>
  );
}

export default App;
