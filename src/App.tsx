import { useState, useEffect } from "react";
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

type AppMode = "main" | "editing";
type CaptureMode = "region" | "fullscreen" | "window";

async function restoreWindowOnScreen(mouseX?: number, mouseY?: number) {
  const appWindow = getCurrentWindow();
  await appWindow.setSize(new LogicalSize(1200, 800));

  // If we have mouse coordinates, position the window on the same screen
  if (mouseX !== undefined && mouseY !== undefined) {
    try {
      const monitors = await availableMonitors();
      
      // Find the monitor where the mouse cursor is
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
        // Center the window on the target monitor
        const windowWidth = 1200;
        const windowHeight = 800;
        const centerX = targetMonitor.position.x + (targetMonitor.size.width - windowWidth) / 2;
        const centerY = targetMonitor.position.y + (targetMonitor.size.height - windowHeight) / 2;
        
        await appWindow.setPosition(new LogicalPosition(centerX, centerY));
      } else {
        // Fallback to center on primary monitor
        await appWindow.center();
      }
    } catch {
      // Fallback to center
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

  useEffect(() => {
    const initializeApp = async () => {
      try {
        const desktopPath = await invoke<string>("get_desktop_directory");
        setSaveDir(desktopPath);
      } catch (err) {
        console.error("Failed to get Desktop directory:", err);
        setError(`Failed to get Desktop directory: ${err instanceof Error ? err.message : String(err)}`);
      }

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
      } catch (err) {
        console.error("Failed to load settings:", err);
      }
    };

    initializeApp();

    if (!hasCompletedOnboarding()) {
      setShowOnboarding(true);
    }
  }, []);

  useEffect(() => {
    const setupHotkeys = async () => {
      try {
        await register("CommandOrControl+Shift+2", () => handleCapture("region"));
        await register("CommandOrControl+Shift+3", () => handleCapture("fullscreen"));
        await register("CommandOrControl+Shift+4", () => handleCapture("window"));
      } catch (err) {
        console.error("Failed to register hotkey:", err);
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
  }, [saveDir, copyToClipboard, autoApplyBackground]);

  async function handleCapture(captureMode: CaptureMode = "region") {
    if (isCapturing) return;
    
    setIsCapturing(true);
    setError(null);

    const appWindow = getCurrentWindow();

    try {
      await appWindow.hide();
      await new Promise((resolve) => setTimeout(resolve, 400));

      const commandMap: Record<CaptureMode, string> = {
        region: "native_capture_interactive",
        fullscreen: "native_capture_fullscreen",
        window: "native_capture_window",
      };

      const screenshotPath = await invoke<string>(commandMap[captureMode], {
        saveDir: "/tmp",
      });

      invoke("play_screenshot_sound").catch(console.error);

      if (autoApplyBackground) {
        try {
          const processedImageData = await processScreenshotWithDefaultBackground(screenshotPath);
          
          const savedPath = await invoke<string>("save_edited_image", {
            imageData: processedImageData,
            saveDir,
            copyToClip: copyToClipboard,
          });

          toast.success("Screenshot processed and saved", {
            description: savedPath,
            duration: 3000,
          });

          // Don't restore window - keep running in background (accessible from system tray)
        } catch (err) {
          const errorMessage = err instanceof Error ? err.message : String(err);
          setError(`Failed to process screenshot: ${errorMessage}`);
          toast.error("Failed to process screenshot", {
            description: errorMessage,
            duration: 5000,
          });
          // Don't restore window on error either - keep running in background
        } finally {
          setIsCapturing(false);
        }
        return;
      }

      let mouseX: number | undefined;
      let mouseY: number | undefined;
      try {
        const [x, y] = await invoke<[number, number]>("get_mouse_position");
        mouseX = x;
        mouseY = y;
      } catch {
      }

      setTempScreenshotPath(screenshotPath);
      setMode("editing");
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

  return (
    <main className="min-h-dvh flex flex-col items-center justify-center p-8 bg-zinc-950 text-zinc-50">
      <div className="w-full max-w-2xl space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-5xl font-bold text-zinc-50 text-balance">Better Shot</h1>
          <p className="text-zinc-400 text-sm text-pretty">Professional screenshot workflow</p>
        </div>

        <Card className="bg-zinc-900 border-zinc-800">
          <CardContent className="p-6 space-y-6">
            <div className="space-y-2">
              <label htmlFor="save-dir" className="text-sm font-medium text-zinc-300 block">
                Save Directory
              </label>
              <input
                id="save-dir"
                type="text"
                value={saveDir}
                onChange={(e) => setSaveDir(e.target.value)}
                placeholder="Enter save directory path"
                disabled={isCapturing}
                className="w-full px-4 py-2.5 bg-zinc-800 border border-zinc-700 rounded-lg text-zinc-100 placeholder-zinc-600 focus:outline-none focus:ring-2 focus:ring-zinc-600 focus:border-zinc-600 transition-all disabled:opacity-50 disabled:cursor-not-allowed font-mono text-sm"
              />
            </div>

            <div className="flex items-center justify-between">
              <label htmlFor="copy-clipboard" className="text-sm text-zinc-300 cursor-pointer">
                Copy to clipboard
              </label>
              <Switch
                id="copy-clipboard"
                checked={copyToClipboard}
                onCheckedChange={async (checked) => {
                  setCopyToClipboard(checked);
                  try {
                    const store = await Store.load("settings.json");
                    await store.set("copyToClipboard", checked);
                    await store.save();
                  } catch (err) {
                    console.error("Failed to save setting:", err);
                  }
                }}
                disabled={isCapturing}
              />
            </div>

            <div className="flex items-center justify-between">
              <label htmlFor="auto-apply-bg" className="text-sm text-zinc-300 cursor-pointer">
                Auto-apply background
              </label>
              <Switch
                id="auto-apply-bg"
                checked={autoApplyBackground}
                onCheckedChange={async (checked) => {
                  setAutoApplyBackground(checked);
                  try {
                    const store = await Store.load("settings.json");
                    await store.set("autoApplyBackground", checked);
                    await store.save();
                  } catch (err) {
                    console.error("Failed to save setting:", err);
                  }
                }}
                disabled={isCapturing}
              />
            </div>

            <div className="grid grid-cols-3 gap-3">
              <Button
                onClick={() => handleCapture("region")}
                disabled={isCapturing}
                className="bg-zinc-800 hover:bg-zinc-700 text-zinc-50 py-3 font-medium disabled:opacity-50 disabled:cursor-not-allowed border border-zinc-700 transition-all"
              >
                Region
              </Button>
              <Button
                onClick={() => handleCapture("fullscreen")}
                disabled={isCapturing}
                className="bg-zinc-800 hover:bg-zinc-700 text-zinc-50 py-3 font-medium disabled:opacity-50 disabled:cursor-not-allowed border border-zinc-700 transition-all"
              >
                Screen
              </Button>
              <Button
                onClick={() => handleCapture("window")}
                disabled={isCapturing}
                className="bg-zinc-800 hover:bg-zinc-700 text-zinc-50 py-3 font-medium disabled:opacity-50 disabled:cursor-not-allowed border border-zinc-700 transition-all"
              >
                Window
              </Button>
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
          <CardContent className="p-5">
            <h3 className="font-medium text-zinc-200 mb-4 text-sm">Keyboard Shortcuts</h3>
            <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-zinc-400">Region</span>
                <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘⇧2</kbd>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-zinc-400">Screen</span>
                <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘⇧3</kbd>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-zinc-400">Window</span>
                <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘⇧4</kbd>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-zinc-400">Save</span>
                <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘S</kbd>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}

export default App;
