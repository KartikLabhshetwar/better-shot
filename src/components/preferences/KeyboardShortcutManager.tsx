import { useState, useEffect, useCallback } from "react";
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

function parseShortcutInput(input: string): string {
  return input
    .replace(/⌘/g, "CommandOrControl+")
    .replace(/⌃/g, "Control+")
    .replace(/⇧/g, "Shift+")
    .replace(/⌥/g, "Alt+")
    .replace(/\s+/g, "")
    .replace(/\+$/, "");
}

export function KeyboardShortcutManager({ onShortcutsChange }: KeyboardShortcutManagerProps) {
  const [shortcuts, setShortcuts] = useState<KeyboardShortcut[]>(DEFAULT_SHORTCUTS);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState("");

  useEffect(() => {
    const loadShortcuts = async () => {
      try {
        const store = await Store.load("settings.json");
        const saved = await store.get<KeyboardShortcut[]>("keyboardShortcuts");
        if (saved && saved.length > 0) {
          const mergedShortcuts = saved.map((savedShortcut) => {
            const defaultShortcut = DEFAULT_SHORTCUTS.find((d) => d.id === savedShortcut.id);
            if (defaultShortcut) {
              return { ...savedShortcut, enabled: defaultShortcut.enabled };
            }
            return savedShortcut;
          });
          const defaultIds = new Set(DEFAULT_SHORTCUTS.map((d) => d.id));
          const customShortcuts = saved.filter((s) => !defaultIds.has(s.id));
          setShortcuts([...mergedShortcuts, ...customShortcuts]);
          await store.set("keyboardShortcuts", [...mergedShortcuts, ...customShortcuts]);
          await store.save();
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

  const handleEdit = useCallback((shortcut: KeyboardShortcut) => {
    setEditingId(shortcut.id);
    setEditValue(formatShortcut(shortcut.shortcut));
  }, []);

  const handleSaveEdit = useCallback(async (id: string) => {
    const parsed = parseShortcutInput(editValue);
    if (!parsed) {
      toast.error("Invalid shortcut format");
      return;
    }

    const newShortcuts = shortcuts.map((s) =>
      s.id === id ? { ...s, shortcut: parsed } : s
    );
    setShortcuts(newShortcuts);
    setEditingId(null);
    setEditValue("");
    await saveShortcuts(newShortcuts);
    toast.success("Shortcut updated");
  }, [editValue, shortcuts, saveShortcuts]);

  const handleCancelEdit = useCallback(() => {
    setEditingId(null);
    setEditValue("");
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
    setEditingId(newId);
    setEditValue(formatShortcut(newShortcut.shortcut));
    saveShortcuts(newShortcuts);
  }, [shortcuts, saveShortcuts]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-zinc-200">Keyboard Shortcuts</label>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={handleAdd}
          className="border-zinc-700 text-zinc-300 hover:bg-zinc-800 hover:text-zinc-50"
        >
          <Plus className="size-3 mr-1" aria-hidden="true" />
          Add
        </Button>
      </div>

      <div className="space-y-2">
        {shortcuts.map((shortcut) => (
          <Card key={shortcut.id} className="bg-zinc-800 border-zinc-700">
            <CardContent className="p-3">
              <div className="flex items-center justify-between gap-3">
                <div className="flex-1 min-w-0">
                  {editingId === shortcut.id ? (
                    <div className="flex items-center gap-2">
                      <input
                        type="text"
                        value={editValue}
                        onChange={(e) => setEditValue(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") {
                            handleSaveEdit(shortcut.id);
                          } else if (e.key === "Escape") {
                            handleCancelEdit();
                          }
                        }}
                        className="flex-1 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-zinc-100 text-sm focus:outline-none focus:ring-2 focus:ring-zinc-600"
                        autoFocus
                      />
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => handleSaveEdit(shortcut.id)}
                        className="text-zinc-300 hover:text-zinc-50"
                      >
                        Save
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={handleCancelEdit}
                        className="text-zinc-300 hover:text-zinc-50"
                      >
                        Cancel
                      </Button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-3">
                      <span className="text-sm text-zinc-300 flex-1">{shortcut.action}</span>
                      <button
                        onClick={() => handleEdit(shortcut)}
                        className="px-2 py-1 bg-zinc-900 border border-zinc-700 rounded text-zinc-300 font-mono text-xs tabular-nums hover:bg-zinc-800 hover:border-zinc-600 transition-colors"
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
                        : "text-zinc-500 hover:text-zinc-400"
                    )}
                  >
                    {shortcut.enabled ? "Enabled" : "Disabled"}
                  </Button>
                  {shortcut.id.startsWith("custom-") && (
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => handleDelete(shortcut.id)}
                      className="text-red-400 hover:text-red-300"
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
