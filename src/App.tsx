import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow, PhysicalSize, LogicalSize, PhysicalPosition } from "@tauri-apps/api/window";
import { register, unregisterAll } from "@tauri-apps/plugin-global-shortcut";
import { RegionSelector } from "./components/RegionSelector";
import { ImageEditor } from "./components/ImageEditor";
import "./App.css";

const DEFAULT_SAVE_DIR = `${window.location.origin.includes("localhost") ? "/tmp" : ""}/Pictures/BetterShot`;

type AppMode = "main" | "selecting" | "editing";
type MonitorShot = {
  id: number;
  x: number;
  y: number;
  width: number;
  height: number;
  path: string;
};

function App() {
  const [mode, setMode] = useState<AppMode>("main");
  const [saveDir, setSaveDir] = useState(DEFAULT_SAVE_DIR);
  const [copyToClipboard, setCopyToClipboard] = useState(true);
  const [lastSavedPath, setLastSavedPath] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isCapturing, setIsCapturing] = useState(false);
  const [tempScreenshotPath, setTempScreenshotPath] = useState<string | null>(null);
  const [monitorShots, setMonitorShots] = useState<MonitorShot[]>([]);

  useEffect(() => {
    const setupHotkeys = async () => {
      try {
        await register("CommandOrControl+Shift+S", async () => {
          setIsCapturing(true);
          setError(null);

          try {
            const savedPath = await invoke<string>("capture_once", {
              saveDir,
              copyToClip: copyToClipboard,
            });
            setLastSavedPath(savedPath);
          } catch (err) {
            setError(err instanceof Error ? err.message : String(err));
            setLastSavedPath(null);
          } finally {
            setIsCapturing(false);
          }
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
      // Hide the window first before taking screenshot
      await appWindow.hide();

      // Small delay to ensure window is hidden
      await new Promise((resolve) => setTimeout(resolve, 150));

      // Capture all monitors
      const shots = await invoke<MonitorShot[]>("capture_all_monitors", {
        saveDir: "/tmp",
      });
      setMonitorShots(shots);

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

      // Position and size the window to cover all monitors
      const position = new PhysicalPosition(bounds.minX, bounds.minY);
      await appWindow.setPosition(position);
      
      const size = new PhysicalSize(width, height);
      await appWindow.setSize(size);

      // Make window fullscreen and always on top for selection
      await appWindow.setDecorations(false);
      await appWindow.setAlwaysOnTop(true);
      await appWindow.setFullscreen(true);
      await appWindow.show();

      setMode("selecting");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setLastSavedPath(null);
      // Restore window on error
      await appWindow.setFullscreen(false);
      await appWindow.setDecorations(true);
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
      const relX = Math.max(0, Math.floor(region.x - target.x));
      const relY = Math.max(0, Math.floor(region.y - target.y));
      const relWidth = Math.max(1, Math.floor(Math.min(region.width, target.width - relX)));
      const relHeight = Math.max(1, Math.floor(Math.min(region.height, target.height - relY)));

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
      await appWindow.setSize(new LogicalSize(900, 700));
      await appWindow.center();
      await appWindow.show();
      
      setTempScreenshotPath(croppedPath);
      setMode("editing");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      await appWindow.setSize(new LogicalSize(800, 600));
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
    await appWindow.setSize(new LogicalSize(800, 600));
    await appWindow.center();
    await appWindow.show();
    setMode("main");
    setTempScreenshotPath(null);
    setMonitorShots([]);
  }

  async function handleEditorSave(editedImageData: string) {
    try {
      const savedPath = await invoke<string>("save_edited_image", {
        imageData: editedImageData,
        saveDir,
        copyToClip: copyToClipboard,
      });
      setLastSavedPath(savedPath);
      setMode("main");
      setTempScreenshotPath(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  function handleEditorCancel() {
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
    <main className="container">
      <h1>Better Shot</h1>

      <div className="capture-section">
        <div className="form-group">
          <label htmlFor="save-dir">Save Directory:</label>
          <input
            id="save-dir"
            type="text"
            value={saveDir}
            onChange={(e) => setSaveDir(e.target.value)}
            placeholder="Enter save directory path"
            disabled={isCapturing}
          />
        </div>

        <div className="form-group">
          <label>
            <input
              type="checkbox"
              checked={copyToClipboard}
              onChange={(e) => setCopyToClipboard(e.target.checked)}
              disabled={isCapturing}
            />
            Copy to clipboard
          </label>
        </div>

        <button
          onClick={handleCapture}
          disabled={isCapturing}
          className="capture-button"
        >
          {isCapturing ? "Capturing..." : "Capture Region"}
        </button>

        {error && <p className="error">{error}</p>}
        {lastSavedPath && (
          <p className="success">Saved to: {lastSavedPath}</p>
        )}
      </div>
    </main>
  );
}

export default App;
