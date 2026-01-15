import { useState, useEffect, useCallback, useRef } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export interface KeyboardShortcut {
  id: string;
  action: string;
  shortcut: string;
  enabled: boolean;
}

interface KeyboardShortcutManagerProps {
  onShortcutsChange?: (shortcuts: KeyboardShortcut[]) => void;
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

// Convert a keyboard event to Tauri shortcut format
function keyEventToShortcut(e: KeyboardEvent): string | null {
  const parts: string[] = [];
  
  // Build modifier string
  if (e.metaKey || e.ctrlKey) {
    parts.push("CommandOrControl");
  }
  if (e.shiftKey) {
    parts.push("Shift");
  }
  if (e.altKey) {
    parts.push("Alt");
  }
  
  // Get the key - ignore modifier-only presses
  const key = e.key;
  if (["Control", "Shift", "Alt", "Meta", "Command"].includes(key)) {
    return null; // Still waiting for the main key
  }
  
  // Need at least one modifier for a valid shortcut
  if (parts.length === 0) {
    return null;
  }
  
  // Convert key to proper format
  let keyName = key.toUpperCase();
  
  // Handle special keys
  if (key === " ") keyName = "Space";
  else if (key === "ArrowUp") keyName = "Up";
  else if (key === "ArrowDown") keyName = "Down";
  else if (key === "ArrowLeft") keyName = "Left";
  else if (key === "ArrowRight") keyName = "Right";
  else if (key === "Escape") keyName = "Escape";
  else if (key === "Enter") keyName = "Enter";
  else if (key === "Tab") keyName = "Tab";
  else if (key === "Backspace") keyName = "Backspace";
  else if (key === "Delete") keyName = "Delete";
  else if (key.length === 1) keyName = key.toUpperCase();
  else if (key.startsWith("F") && !isNaN(parseInt(key.slice(1)))) keyName = key; // F1-F12
  
  parts.push(keyName);
  
  return parts.join("+");
}

export function KeyboardShortcutManager({ onShortcutsChange }: KeyboardShortcutManagerProps) {
  const [shortcuts, setShortcuts] = useState<KeyboardShortcut[]>(DEFAULT_SHORTCUTS);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [recordedShortcut, setRecordedShortcut] = useState<string | null>(null);
  const [isRecording, setIsRecording] = useState(false);
  const recordingRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const loadShortcuts = async () => {
      try {
        const store = await Store.load("settings.json");
        const saved = await store.get<KeyboardShortcut[]>("keyboardShortcuts");
        if (saved && saved.length > 0) {
          // Merge saved shortcuts with defaults, preserving all saved values
          // Only add missing default shortcuts that don't exist in saved
          const savedIds = new Set(saved.map((s) => s.id));
          const missingDefaults = DEFAULT_SHORTCUTS.filter((d) => !savedIds.has(d.id));
          const mergedShortcuts = [...saved, ...missingDefaults];
          setShortcuts(mergedShortcuts);
        } else {
          setShortcuts(DEFAULT_SHORTCUTS);
        }
      } catch (err) {
        console.error("Failed to load shortcuts:", err);
        setShortcuts(DEFAULT_SHORTCUTS);
      }
    };
    loadShortcuts();
  }, []);

  // Keyboard recording effect
  useEffect(() => {
    if (!isRecording || !editingId) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();

      // Escape cancels recording
      if (e.key === "Escape") {
        setIsRecording(false);
        setEditingId(null);
        setRecordedShortcut(null);
        return;
      }

      const shortcut = keyEventToShortcut(e);
      if (shortcut) {
        setRecordedShortcut(shortcut);
      }
    };

    const handleKeyUp = async (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();

      // Only save when we have a recorded shortcut and user releases a key
      if (recordedShortcut && editingId) {
        const newShortcuts = shortcuts.map((s) =>
          s.id === editingId ? { ...s, shortcut: recordedShortcut } : s
        );
        setShortcuts(newShortcuts);
        
        try {
          const store = await Store.load("settings.json");
          await store.set("keyboardShortcuts", newShortcuts);
          await store.save();
          onShortcutsChange?.(newShortcuts);
          toast.success("Shortcut updated");
        } catch (err) {
          console.error("Failed to save shortcuts:", err);
          toast.error("Failed to save shortcuts");
        }

        setIsRecording(false);
        setEditingId(null);
        setRecordedShortcut(null);
      }
    };

    window.addEventListener("keydown", handleKeyDown, true);
    window.addEventListener("keyup", handleKeyUp, true);

    return () => {
      window.removeEventListener("keydown", handleKeyDown, true);
      window.removeEventListener("keyup", handleKeyUp, true);
    };
  }, [isRecording, editingId, recordedShortcut, shortcuts, onShortcutsChange]);

  const saveShortcuts = useCallback(async (newShortcuts: KeyboardShortcut[]) => {
    try {
      const store = await Store.load("settings.json");
      await store.set("keyboardShortcuts", newShortcuts);
      await store.save();
      onShortcutsChange?.(newShortcuts);
    } catch (err) {
      console.error("Failed to save shortcuts:", err);
      toast.error("Failed to save shortcuts");
    }
  }, [onShortcutsChange]);

  const handleStartRecording = useCallback((shortcut: KeyboardShortcut) => {
    setEditingId(shortcut.id);
    setRecordedShortcut(null);
    setIsRecording(true);
    // Focus the recording button to capture keyboard events
    setTimeout(() => recordingRef.current?.focus(), 0);
  }, []);

  const handleCancelRecording = useCallback(() => {
    setIsRecording(false);
    setEditingId(null);
    setRecordedShortcut(null);
  }, []);

  const handleToggle = useCallback(async (id: string) => {
    const newShortcuts = shortcuts.map((s) =>
      s.id === id ? { ...s, enabled: !s.enabled } : s
    );
    setShortcuts(newShortcuts);
    await saveShortcuts(newShortcuts);
  }, [shortcuts, saveShortcuts]);

  const handleDelete = useCallback(async (id: string) => {
    const newShortcuts = shortcuts.filter((s) => s.id !== id);
    setShortcuts(newShortcuts);
    await saveShortcuts(newShortcuts);
    toast.success("Shortcut removed");
  }, [shortcuts, saveShortcuts]);

  const handleAdd = useCallback(() => {
    const newId = `custom-${Date.now()}`;
    const newShortcut: KeyboardShortcut = {
      id: newId,
      action: "New Action",
      shortcut: "CommandOrControl+Shift+5",
      enabled: false,
    };
    const newShortcuts = [...shortcuts, newShortcut];
    setShortcuts(newShortcuts);
    saveShortcuts(newShortcuts);
    // Start recording for the new shortcut
    setTimeout(() => handleStartRecording(newShortcut), 100);
  }, [shortcuts, saveShortcuts, handleStartRecording]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-foreground">Keyboard Shortcuts</label>
        <Button
          type="button"
          variant="cta"
          size="lg"
          onClick={handleAdd}
        >
          <Plus className="size-3 mr-1" aria-hidden="true" />
          Add
        </Button>
      </div>

      <div className="space-y-2">
        {shortcuts.map((shortcut) => (
          <Card key={shortcut.id} className="bg-secondary border-border">
            <CardContent className="p-3">
              <div className="flex items-center justify-between gap-3">
                <div className="flex-1 min-w-0">
                  {editingId === shortcut.id && isRecording ? (
                    <div className="flex items-center gap-2">
                      <button
                        ref={recordingRef}
                        className="flex-1 px-2 py-1 bg-card border-2 border-blue-500 rounded text-card-foreground text-sm focus:outline-none animate-pulse text-left"
                        autoFocus
                      >
                        {recordedShortcut ? formatShortcut(recordedShortcut) : "Press shortcut..."}
                      </button>
                      <Button
                        variant="cta"
                        size="lg"
                        onClick={handleCancelRecording}
                      >
                        Cancel
                      </Button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-3">
                      <span className="text-sm text-foreground flex-1">{shortcut.action}</span>
                      <button
                        onClick={() => handleStartRecording(shortcut)}
                        className="px-2 py-1 bg-card border border-border rounded text-foreground font-mono text-xs tabular-nums hover:bg-secondary hover:border-ring transition-colors"
                        title="Click to record new shortcut"
                      >
                        {formatShortcut(shortcut.shortcut)}
                      </button>
                    </div>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => handleToggle(shortcut.id)}
                    className={cn(
                      "text-xs",
                      shortcut.enabled
                        ? "text-green-400 hover:text-green-300"
                        : "text-foreground0 hover:text-muted-foreground"
                    )}
                  >
                    {shortcut.enabled ? "Enabled" : "Disabled"}
                  </Button>
                  {shortcut.id.startsWith("custom-") && (
                    <Button
                      variant="cta"
                      size="lg"
                      onClick={() => handleDelete(shortcut.id)}
                      aria-label="Delete shortcut"
                    >
                      <Trash2 className="size-3" aria-hidden="true" />
                    </Button>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
