import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow, PhysicalSize, LogicalSize, PhysicalPosition } from "@tauri-apps/api/window";
import { register, unregisterAll } from "@tauri-apps/plugin-global-shortcut";
import { RegionSelector } from "./components/RegionSelector";
import { ImageEditor } from "./components/ImageEditor";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

type AppMode = "main" | "selecting" | "editing";
type MonitorShot = {
  id: number;
  x: number;
  y: number;
  width: number;
  height: number;
  scale_factor: number;
  path: string;
};

function App() {
  const [mode, setMode] = useState<AppMode>("main");
  const [saveDir, setSaveDir] = useState<string>("");
  const [copyToClipboard, setCopyToClipboard] = useState(true);
  const [lastSavedPath, setLastSavedPath] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isCapturing, setIsCapturing] = useState(false);
  const [tempScreenshotPath, setTempScreenshotPath] = useState<string | null>(null);
  const [monitorShots, setMonitorShots] = useState<MonitorShot[]>([]);

  useEffect(() => {
    const initializeDesktopPath = async () => {
      try {
        const desktopPath = await invoke<string>("get_desktop_directory");
        setSaveDir(desktopPath);
      } catch (err) {
        console.error("Failed to get Desktop directory:", err);
        setError(`Failed to get Desktop directory: ${err instanceof Error ? err.message : String(err)}`);
      }
    };
    initializeDesktopPath();
  }, []);

  useEffect(() => {
    const setupHotkeys = async () => {
      try {
        await register("CommandOrControl+Shift+2", () => {
          // Use the same workflow as the Capture Region button
          handleCapture();
        });
      } catch (err) {
        console.error("Failed to register hotkey:", err);
        setError(`Hotkey registration failed: ${err instanceof Error ? err.message : String(err)}`);
      }
    };

    setupHotkeys();

    const unlisten = listen("capture-triggered", () => {
      handleCapture();
    });

    return () => {
      unlisten.then((fn) => fn());
      unregisterAll().catch(console.error);
    };
  }, [saveDir, copyToClipboard]);

  async function handleCapture() {
    setIsCapturing(true);
    setError(null);

    const appWindow = getCurrentWindow();

    try {
      // Prepare window properties first (while still hidden) - this reduces jitter
      await Promise.all([
        appWindow.setDecorations(false),
        appWindow.setAlwaysOnTop(true),
      ]);

      // Hide the window before taking screenshot
      await appWindow.hide();

      // Minimal delay - just enough for window to hide
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Capture all monitors
      const shots = await invoke<MonitorShot[]>("capture_all_monitors", {
        saveDir: "/tmp",
      });

      // Calculate total bounds across all monitors
      const bounds = shots.reduce(
        (acc, s) => ({
          minX: Math.min(acc.minX, s.x),
          minY: Math.min(acc.minY, s.y),
          maxX: Math.max(acc.maxX, s.x + s.width),
          maxY: Math.max(acc.maxY, s.y + s.height),
        }),
        { minX: Number.POSITIVE_INFINITY, minY: Number.POSITIVE_INFINITY, maxX: Number.NEGATIVE_INFINITY, maxY: Number.NEGATIVE_INFINITY }
      );

      const width = bounds.maxX - bounds.minX;
      const height = bounds.maxY - bounds.minY;

      // Set position and size together, then fullscreen
      await appWindow.setPosition(new PhysicalPosition(bounds.minX, bounds.minY));
      await appWindow.setSize(new PhysicalSize(width, height));
      
      // Set mode BEFORE showing window so React renders immediately
      setMonitorShots(shots);
      setMode("selecting");
      
      // Small delay for React to render, then show
      await new Promise((resolve) => setTimeout(resolve, 10));
      await appWindow.setFullscreen(true);
      await appWindow.show();
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      // Check if it's a permission-related error
      if (errorMessage.toLowerCase().includes("permission") || 
          errorMessage.toLowerCase().includes("access") ||
          errorMessage.toLowerCase().includes("denied")) {
        setError(
          "Screen Recording permission required. Please go to System Settings > Privacy & Security > Screen Recording and enable access for Better Shot, then restart the app."
        );
      } else {
        setError(errorMessage);
      }
      setLastSavedPath(null);
      // Restore window on error
      await appWindow.setFullscreen(false);
      await appWindow.setDecorations(true);
      await appWindow.setSize(new LogicalSize(1200, 800));
      await appWindow.center();
      await appWindow.show().catch(() => {});
    } finally {
      setIsCapturing(false);
    }
  }

  async function handleRegionSelect(region: { x: number; y: number; width: number; height: number }) {
    if (!monitorShots.length) return;

    const appWindow = getCurrentWindow();

    try {
      // First, reset window state before processing
      await appWindow.setFullscreen(false);
      await appWindow.setAlwaysOnTop(false);
      await appWindow.setDecorations(true);
      
      // Find which monitor contains most of the selection
      const target = monitorShots.reduce(
        (best, shot) => {
          const overlapX = Math.max(region.x, shot.x);
          const overlapY = Math.max(region.y, shot.y);
          const overlapRight = Math.min(region.x + region.width, shot.x + shot.width);
          const overlapBottom = Math.min(region.y + region.height, shot.y + shot.height);
          
          const overlapWidth = Math.max(0, overlapRight - overlapX);
          const overlapHeight = Math.max(0, overlapBottom - overlapY);
          const area = overlapWidth * overlapHeight;
          
          if (area > best.area) {
            return { shot, area };
          }
          return best;
        },
        { shot: monitorShots[0], area: 0 }
      ).shot;

      // Convert absolute screen coordinates to coordinates relative to the monitor's screenshot
      // Apply scale factor for Retina displays (image is captured at physical pixels)
      const scaleFactor = target.scale_factor || 1;
      const relX = Math.max(0, Math.floor((region.x - target.x) * scaleFactor));
      const relY = Math.max(0, Math.floor((region.y - target.y) * scaleFactor));
      const relWidth = Math.max(1, Math.floor(region.width * scaleFactor));
      const relHeight = Math.max(1, Math.floor(region.height * scaleFactor));

      const croppedPath = await invoke<string>("capture_region", {
        screenshotPath: target.path,
        x: relX,
        y: relY,
        width: relWidth,
        height: relHeight,
        saveDir: "/tmp",
      });
      
      console.log("Cropped screenshot path:", croppedPath);
      
      // Resize window to fit the editor
      await appWindow.setSize(new LogicalSize(1200, 800));
      await appWindow.center();
      await appWindow.show();
      
      setTempScreenshotPath(croppedPath);
      setMode("editing");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      await appWindow.setFullscreen(false);
      await appWindow.setAlwaysOnTop(false);
      await appWindow.setDecorations(true);
      await appWindow.setSize(new LogicalSize(1200, 800));
      await appWindow.center();
      await appWindow.show();
      setMode("main");
      setMonitorShots([]);
    }
  }

  async function handleRegionCancel() {
    const appWindow = getCurrentWindow();
    await appWindow.setFullscreen(false);
    await appWindow.setAlwaysOnTop(false);
    await appWindow.setDecorations(true);
    await appWindow.setSize(new LogicalSize(1200, 800));
    await appWindow.center();
    await appWindow.show();
    setMode("main");
    setTempScreenshotPath(null);
    setMonitorShots([]);
  }

  async function handleEditorSave(editedImageData: string) {
    const appWindow = getCurrentWindow();
    try {
      const savedPath = await invoke<string>("save_edited_image", {
        imageData: editedImageData,
        saveDir,
        copyToClip: copyToClipboard,
      });
      setLastSavedPath(savedPath);
      
      await appWindow.setFullscreen(false);
      await appWindow.setAlwaysOnTop(false);
      await appWindow.setDecorations(true);
      await appWindow.setSize(new LogicalSize(1200, 800));
      await appWindow.center();
      await appWindow.show();
      setMode("main");
      setTempScreenshotPath(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      await appWindow.setFullscreen(false);
      await appWindow.setAlwaysOnTop(false);
      await appWindow.setDecorations(true);
      await appWindow.setSize(new LogicalSize(1200, 800));
      await appWindow.center();
      await appWindow.show();
      setMode("main");
    }
  }

  async function handleEditorCancel() {
    const appWindow = getCurrentWindow();
    await appWindow.setFullscreen(false);
    await appWindow.setAlwaysOnTop(false);
    await appWindow.setDecorations(true);
    await appWindow.setSize(new LogicalSize(1200, 800));
    await appWindow.center();
    await appWindow.show();
    setMode("main");
    setTempScreenshotPath(null);
  }

  if (mode === "selecting") {
    return (
      <RegionSelector
        onSelect={handleRegionSelect}
        onCancel={handleRegionCancel}
        monitorShots={monitorShots}
      />
    );
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

  return (
    <main className="min-h-dvh flex flex-col items-center justify-center p-8 bg-zinc-950 text-zinc-50">
      <div className="w-full max-w-2xl space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-4xl font-bold text-zinc-50 font-mono text-balance">Better Shot</h1>
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

            <div className="flex items-center gap-3 p-3 bg-zinc-800 rounded-lg border border-zinc-700">
              <input
                type="checkbox"
                id="copy-clipboard"
                checked={copyToClipboard}
                onChange={(e) => setCopyToClipboard(e.target.checked)}
                disabled={isCapturing}
                className="size-4 rounded border-zinc-700 bg-zinc-800 text-zinc-400 focus:ring-2 focus:ring-zinc-600 disabled:opacity-50 cursor-pointer"
              />
              <label htmlFor="copy-clipboard" className="text-sm text-zinc-300 cursor-pointer flex-1">
                Copy to clipboard
              </label>
            </div>

            <Button
              onClick={handleCapture}
              disabled={isCapturing}
              className="w-full bg-zinc-800 hover:bg-zinc-700 text-zinc-50 py-3 text-base font-medium disabled:opacity-50 disabled:cursor-not-allowed border border-zinc-700 transition-all"
            >
              {isCapturing ? (
                <span className="flex items-center justify-center gap-2">
                  <svg className="animate-spin size-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Capturing...
                </span>
              ) : (
                "Capture Region"
              )}
            </Button>

            {error && (
              <div className="p-4 bg-red-950/30 border border-red-800/50 rounded-lg text-red-400 text-sm text-pretty">
                <div className="font-medium text-red-300 mb-1">Error</div>
                {error}
              </div>
            )}
            
            {lastSavedPath && (
              <div className="p-4 bg-emerald-950/30 border border-emerald-800/50 rounded-lg text-emerald-400 text-sm break-all text-pretty">
                <div className="font-medium text-emerald-300 mb-1">Saved successfully</div>
                {lastSavedPath}
              </div>
            )}
          </CardContent>
        </Card>

        <div className="grid grid-cols-2 gap-4">
          <Card className="bg-zinc-900 border-zinc-800">
            <CardContent className="p-5">
              <h3 className="font-medium text-zinc-200 mb-4 text-sm">Quick Actions</h3>
              <div className="space-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Capture</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘⇧2</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Save</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums">⌘S</kbd>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card className="bg-zinc-900 border-zinc-800">
            <CardContent className="p-5">
              <h3 className="font-medium text-zinc-200 mb-4 text-sm">Editor Controls</h3>
              <div className="space-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Copy</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs">⌘⇧C</kbd>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-400">Cancel</span>
                  <kbd className="px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-zinc-300 font-mono text-xs">Esc</kbd>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </main>
  );
}

export default App;
