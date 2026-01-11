import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { register, unregisterAll } from "@tauri-apps/plugin-global-shortcut";
import "./App.css";

const DEFAULT_SAVE_DIR = `${window.location.origin.includes("localhost") ? "/tmp" : ""}/Pictures/BetterShot`;

function App() {
  const [saveDir, setSaveDir] = useState(DEFAULT_SAVE_DIR);
  const [copyToClipboard, setCopyToClipboard] = useState(true);
  const [lastSavedPath, setLastSavedPath] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isCapturing, setIsCapturing] = useState(false);

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
          {isCapturing ? "Capturing..." : "Capture Screen"}
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
