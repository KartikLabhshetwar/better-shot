import { useState, useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow, LogicalSize, LogicalPosition } from "@tauri-apps/api/window";
import { availableMonitors } from "@tauri-apps/api/window";
import { register, unregisterAll } from "@tauri-apps/plugin-global-shortcut";
import { Store } from "@tauri-apps/plugin-store";
import { toast } from "sonner";
import { ImageEditor } from "./components/ImageEditor";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { OnboardingFlow } from "./components/onboarding/OnboardingFlow";
import { hasCompletedOnboarding } from "@/lib/onboarding";
import { processScreenshotWithDefaultBackground } from "@/lib/auto-process";
import { SettingsIcon } from "./components/SettingsIcon";
import { PreferencesPage } from "./components/preferences/PreferencesPage";
import { migrateStoredValue, isAssetId, isDataUrl } from "@/lib/asset-registry";
import type { KeyboardShortcut } from "./components/preferences/KeyboardShortcutManager";
import { Crop, Monitor, AppWindowMac } from "lucide-react";

type AppMode = "main" | "editing" | "preferences";
type CaptureMode = "region" | "fullscreen" | "window";

const DEFAULT_SHORTCUTS: KeyboardShortcut[] = [
  { id: "region", action: "Capture Region", shortcut: "CommandOrControl+Shift+2", enabled: true },
  { id: "fullscreen", action: "Capture Screen", shortcut: "CommandOrControl+Shift+3", enabled: false },
  { id: "window", action: "Capture Window", shortcut: "CommandOrControl+Shift+4", enabled: false },
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
  await appWindow.setSize(new LogicalSize(1200, 800));

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
        const windowWidth = 1200;
        const windowHeight = 800;
        const centerX = targetMonitor.position.x + (targetMonitor.size.width - windowWidth) / 2;
        const centerY = targetMonitor.position.y + (targetMonitor.size.height - windowHeight) / 2;
        
        await appWindow.setPosition(new LogicalPosition(centerX, centerY));
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
  const [copyToClipboard, setCopyToClipboard] = useState(true);
  const [autoApplyBackground, setAutoApplyBackground] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isCapturing, setIsCapturing] = useState(false);
  const [tempScreenshotPath, setTempScreenshotPath] = useState<string | null>(null);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [shortcuts, setShortcuts] = useState<KeyboardShortcut[]>(DEFAULT_SHORTCUTS);
  const [settingsVersion, setSettingsVersion] = useState(0);
  const [tempDir, setTempDir] = useState<string>("/tmp");

  // Refs to hold current values for use in callbacks that may have stale closures
  const settingsRef = useRef({ autoApplyBackground, saveDir, copyToClipboard, tempDir });
  
  // Keep ref in sync with state
  useEffect(() => {
    settingsRef.current = { autoApplyBackground, saveDir, copyToClipboard, tempDir };
  }, [autoApplyBackground, saveDir, copyToClipboard, tempDir]);

  // Load settings function
  const loadSettings = useCallback(async () => {
    try {
      const store = await Store.load("settings.json", {
        defaults: {
          copyToClipboard: true,
          autoApplyBackground: false,
        },
        autoSave: true,
      });

      const savedCopyToClip = await store.get<boolean>("copyToClipboard");
      if (savedCopyToClip !== null && savedCopyToClip !== undefined) {
        setCopyToClipboard(savedCopyToClip);
      }

      const savedAutoApply = await store.get<boolean>("autoApplyBackground");
      if (savedAutoApply !== null && savedAutoApply !== undefined) {
        setAutoApplyBackground(savedAutoApply);
      }

      const savedSaveDir = await store.get<string>("saveDir");
      if (savedSaveDir) {
        setSaveDir(savedSaveDir);
      }

      const savedShortcuts = await store.get<KeyboardShortcut[]>("keyboardShortcuts");
      if (savedShortcuts && savedShortcuts.length > 0) {
        const mergedShortcuts = savedShortcuts.map((savedShortcut) => {
          const defaultShortcut = DEFAULT_SHORTCUTS.find((d) => d.id === savedShortcut.id);
          if (defaultShortcut) {
            return { ...savedShortcut, enabled: defaultShortcut.enabled };
          }
          return savedShortcut;
        });
        const defaultIds = new Set(DEFAULT_SHORTCUTS.map((d) => d.id));
        const customShortcuts = savedShortcuts.filter((s) => !defaultIds.has(s.id));
        const finalShortcuts = [...mergedShortcuts, ...customShortcuts];
        setShortcuts(finalShortcuts);
        await store.set("keyboardShortcuts", finalShortcuts);
        await store.save();
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
            autoApplyBackground: false,
          },
          autoSave: true,
        });

        const savedCopyToClip = await store.get<boolean>("copyToClipboard");
        if (savedCopyToClip !== null && savedCopyToClip !== undefined) {
          setCopyToClipboard(savedCopyToClip);
        }

        const savedAutoApply = await store.get<boolean>("autoApplyBackground");
        if (savedAutoApply !== null && savedAutoApply !== undefined) {
          setAutoApplyBackground(savedAutoApply);
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
            await store.save();
          }
        }

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

    if (!hasCompletedOnboarding()) {
      setShowOnboarding(true);
    }
  }, []);

  // Setup hotkeys whenever settings change
  useEffect(() => {
    const setupHotkeys = async () => {
      try {
        await unregisterAll();
        
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

    const unlisten1 = listen("capture-triggered", () => handleCapture("region"));
    const unlisten2 = listen("capture-fullscreen", () => handleCapture("fullscreen"));
    const unlisten3 = listen("capture-window", () => handleCapture("window"));

    return () => {
      unlisten1.then((fn) => fn());
      unlisten2.then((fn) => fn());
      unlisten3.then((fn) => fn());
      unregisterAll().catch(console.error);
    };
  }, [shortcuts, settingsVersion]);

  // Reload settings when coming back from preferences
  const handleSettingsChange = useCallback(async () => {
    await loadSettings();
    setSettingsVersion(v => v + 1);
  }, [loadSettings]);

  // Toggle auto-apply from main page
  const handleAutoApplyToggle = useCallback(async (checked: boolean) => {
    setAutoApplyBackground(checked);
    try {
      const store = await Store.load("settings.json");
      await store.set("autoApplyBackground", checked);
      await store.save();
    } catch (err) {
      console.error("Failed to save auto-apply setting:", err);
      toast.error("Failed to save setting");
    }
  }, []);

  const handleBackFromPreferences = useCallback(async () => {
    await loadSettings();
    setSettingsVersion(v => v + 1);
    setMode("main");
  }, [loadSettings]);

  async function handleCapture(captureMode: CaptureMode = "region") {
    if (isCapturing) return;
    
    setIsCapturing(true);
    setError(null);

    const appWindow = getCurrentWindow();
    
    // Read current settings from ref to avoid stale closure issues
    const { autoApplyBackground: shouldAutoApply, saveDir: currentSaveDir, copyToClipboard: shouldCopyToClipboard, tempDir: currentTempDir } = settingsRef.current;

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

      if (shouldAutoApply) {
        
        try {
          const processedImageData = await processScreenshotWithDefaultBackground(screenshotPath);
          
          const savedPath = await invoke<string>("save_edited_image", {
            imageData: processedImageData,
            saveDir: currentSaveDir,
            copyToClip: shouldCopyToClipboard,
          });

          toast.success("Screenshot processed and saved", {
            description: savedPath,
            duration: 3000,
          });
          
          // Ensure window stays hidden after auto-apply
          await appWindow.hide();
        } catch (err) {
          const errorMessage = err instanceof Error ? err.message : String(err);
          setError(`Failed to process screenshot: ${errorMessage}`);
          toast.error("Failed to process screenshot", {
            description: errorMessage,
            duration: 5000,
          });
          // Even on error, keep window hidden in auto-apply mode
          await appWindow.hide();
        } finally {
          setIsCapturing(false);
        }
        return;
      }

      setTempScreenshotPath(screenshotPath);
      setMode("editing");
      await restoreWindowOnScreen(mouseX, mouseY);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      if (errorMessage.includes("cancelled") || errorMessage.includes("was cancelled")) {
        // Only restore window if not in auto-apply mode
        if (!shouldAutoApply) {
          await restoreWindow();
        }
      } else if (errorMessage.includes("already in progress")) {
        setError("Please wait for the current screenshot to complete");
        if (!shouldAutoApply) {
          await restoreWindow();
        }
      } else if (
        errorMessage.toLowerCase().includes("permission") ||
        errorMessage.toLowerCase().includes("access") ||
        errorMessage.toLowerCase().includes("denied")
      ) {
        setError(
          "Screen Recording permission required. Please go to System Settings > Privacy & Security > Screen Recording and enable access for Better Shot, then restart the app."
        );
        // Always show window for permission errors so user can see the message
        await restoreWindow();
      } else {
        setError(errorMessage);
        if (!shouldAutoApply) {
          await restoreWindow();
        }
      }
    } finally {
      setIsCapturing(false);
    }
  }

  async function handleEditorSave(editedImageData: string) {
    try {
      const savedPath = await invoke<string>("save_edited_image", {
        imageData: editedImageData,
        saveDir,
        copyToClip: copyToClipboard,
      });

      toast.success("Image saved", {
        description: savedPath,
        duration: 4000,
      });

      setMode("main");
      setTempScreenshotPath(null);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setError(errorMessage);
      toast.error("Failed to save image", {
        description: errorMessage,
        duration: 5000,
      });
      setMode("main");
    }
  }

  async function handleEditorCancel() {
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
      <ImageEditor
        imagePath={tempScreenshotPath}
        onSave={handleEditorSave}
        onCancel={handleEditorCancel}
      />
    );
  }

  if (showOnboarding) {
    return <OnboardingFlow onComplete={() => setShowOnboarding(false)} />;
  }

  if (mode === "preferences") {
    return (
      <PreferencesPage 
        onBack={handleBackFromPreferences} 
        onSettingsChange={handleSettingsChange}
      />
    );
  }

  return (
    <main className="min-h-dvh flex flex-col items-center justify-center p-8 bg-zinc-950 text-zinc-50">
      <div className="w-full max-w-2xl space-y-6">
        <div className="relative text-center space-y-2">
          <div className="absolute top-0 right-0">
            <SettingsIcon onClick={() => setMode("preferences")} />
          </div>
          <h1 className="text-5xl font-bold text-zinc-50 text-balance">Better Shot</h1>
          <p className="text-zinc-400 text-sm text-pretty">Professional screenshot workflow</p>
        </div>

        <Card className="bg-zinc-900 border-zinc-800">
          <CardContent className="p-6 space-y-6">
            <div className="grid grid-cols-3 gap-3">
              <Button
                onClick={() => handleCapture("region")}
                disabled={isCapturing}
                className="bg-zinc-800 hover:bg-zinc-700 text-zinc-50 py-3 font-medium disabled:opacity-50 disabled:cursor-not-allowed border border-zinc-700 transition-all flex items-center justify-center gap-2"
              >
                <Crop className="size-4" aria-hidden="true" />
                Region
              </Button>
              <Button
                onClick={() => handleCapture("fullscreen")}
                disabled={isCapturing}
                className="bg-zinc-800 hover:bg-zinc-700 text-zinc-50 py-3 font-medium disabled:opacity-50 disabled:cursor-not-allowed border border-zinc-700 transition-all flex items-center justify-center gap-2"
              >
                <Monitor className="size-4" aria-hidden="true" />
                Screen
              </Button>
              <Button
                onClick={() => handleCapture("window")}
                disabled={isCapturing}
                className="bg-zinc-800 hover:bg-zinc-700 text-zinc-50 py-3 font-medium disabled:opacity-50 disabled:cursor-not-allowed border border-zinc-700 transition-all flex items-center justify-center gap-2"
              >
                <AppWindowMac className="size-4" aria-hidden="true" />
                Window
              </Button>
            </div>

            {/* Quick Toggle for Auto-apply */}
            <div className="flex items-center justify-between py-2 px-1">
              <div className="flex-1">
                <label htmlFor="auto-apply-toggle" className="text-sm font-medium text-zinc-300 cursor-pointer block">
                  Auto-apply background
                </label>
                <p className="text-xs text-zinc-500">Apply default background and save instantly</p>
              </div>
              <Switch
                id="auto-apply-toggle"
                checked={autoApplyBackground}
                onCheckedChange={handleAutoApplyToggle}
              />
            </div>

            {isCapturing && (
              <div className="flex items-center justify-center gap-2 text-zinc-400 text-sm">
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

        <Card className="bg-zinc-900 border-zinc-800">
          <CardContent className="p-5 space-y-4">
            <h3 className="font-medium text-zinc-200 text-sm">Keyboard Shortcuts</h3>
            
            {/* Capture Shortcuts */}
            <div className="space-y-2">
              <p className="text-xs text-zinc-500 uppercase tracking-wide">Capture</p>
              <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Region</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">
                    {getShortcutDisplay("region")}
                  </kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Screen</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">
                    {getShortcutDisplay("fullscreen")}
                  </kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Window</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">
                    {getShortcutDisplay("window")}
                  </kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Cancel</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">Esc</kbd>
                </div>
              </div>
            </div>

            {/* Editor Shortcuts */}
            <div className="space-y-2">
              <p className="text-xs text-zinc-500 uppercase tracking-wide">Editor</p>
              <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Save</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘S</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Copy</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⇧⌘C</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Undo</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘Z</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Redo</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⇧⌘Z</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Delete annotation</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌫</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Close editor</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">Esc</kbd>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}

export default App;
