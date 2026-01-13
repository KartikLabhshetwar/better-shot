import { useState, useEffect, useCallback } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { ArrowLeft, Folder } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { BackgroundImageSelector } from "./BackgroundImageSelector";
import { KeyboardShortcutManager } from "./KeyboardShortcutManager";
import type { KeyboardShortcut } from "./KeyboardShortcutManager";

interface PreferencesPageProps {
  onBack: () => void;
  onSettingsChange?: () => void;
}

interface GeneralSettings {
  saveDir: string;
  copyToClipboard: boolean;
}

export function PreferencesPage({ onBack, onSettingsChange }: PreferencesPageProps) {
  const [settings, setSettings] = useState<GeneralSettings>({
    saveDir: "",
    copyToClipboard: true,
  });
  const [isLoading, setIsLoading] = useState(true);

  // Load settings on mount
  useEffect(() => {
    const loadSettings = async () => {
      try {
        const store = await Store.load("settings.json");
        
        const copyToClip = await store.get<boolean>("copyToClipboard");
        const saveDir = await store.get<string>("saveDir");
        
        setSettings({
          saveDir: saveDir || "",
          copyToClipboard: copyToClip ?? true,
        });
      } catch (err) {
        console.error("Failed to load settings:", err);
      } finally {
        setIsLoading(false);
      }
    };
    loadSettings();
  }, []);

  const updateSetting = useCallback(async <K extends keyof GeneralSettings>(
    key: K,
    value: GeneralSettings[K]
  ) => {
    setSettings(prev => ({ ...prev, [key]: value }));
    
    try {
      const store = await Store.load("settings.json");
      await store.set(key, value);
      await store.save();
      onSettingsChange?.();
    } catch (err) {
      console.error(`Failed to save ${key}:`, err);
      toast.error(`Failed to save setting`);
    }
  }, [onSettingsChange]);

  const handleShortcutsChange = useCallback((_shortcuts: KeyboardShortcut[]) => {
    // Notify parent to re-register shortcuts
    onSettingsChange?.();
  }, [onSettingsChange]);

  const handleImageSelect = useCallback(async (_imageSrc: string) => {
    try {
      // The BackgroundImageSelector now handles converting to storable value
      // and saving to store, so we just need to notify of the change
      onSettingsChange?.();
    } catch (err) {
      console.error("Failed to save default background:", err);
      toast.error("Failed to save default background");
    }
  }, [onSettingsChange]);

  if (isLoading) {
    return (
      <main className="min-h-dvh flex items-center justify-center bg-zinc-950">
        <div className="text-zinc-400">Loading settings...</div>
      </main>
    );
  }

  return (
    <main className="min-h-dvh bg-zinc-950 text-zinc-50">
      <div className="max-w-4xl mx-auto p-6 space-y-6">
        {/* Header */}
        <div className="flex items-center gap-4 pb-2 border-b border-zinc-800">
          <Button
            variant="ghost"
            size="icon"
            onClick={onBack}
            className="text-zinc-400 hover:text-zinc-50 hover:bg-zinc-800"
            aria-label="Back to main"
          >
            <ArrowLeft className="size-5" aria-hidden="true" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold text-zinc-50">Preferences</h1>
            <p className="text-zinc-500 text-sm">Configure your app settings</p>
          </div>
        </div>

        {/* General Settings */}
        <Card className="bg-zinc-900 border-zinc-800">
          <CardHeader className="pb-4">
            <CardTitle className="text-lg font-semibold text-zinc-100">General</CardTitle>
          </CardHeader>
          <CardContent className="space-y-5">
            {/* Save Directory */}
            <div className="space-y-2">
              <label htmlFor="save-dir" className="text-sm font-medium text-zinc-300 flex items-center gap-2">
                <Folder className="size-4" aria-hidden="true" />
                Save Directory
              </label>
              <input
                id="save-dir"
                type="text"
                value={settings.saveDir}
                onChange={(e) => updateSetting("saveDir", e.target.value)}
                placeholder="Enter save directory path (e.g., ~/Desktop)"
                className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-lg text-zinc-100 placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500 transition-all font-mono text-sm"
              />
              <p className="text-xs text-zinc-500">Screenshots will be saved to this directory</p>
            </div>

            {/* Copy to Clipboard */}
            <div className="flex items-center justify-between py-2">
              <div>
                <label htmlFor="copy-clipboard" className="text-sm font-medium text-zinc-300 cursor-pointer block">
                  Copy to clipboard
                </label>
                <p className="text-xs text-zinc-500">Automatically copy screenshots to clipboard after saving</p>
              </div>
              <Switch
                id="copy-clipboard"
                checked={settings.copyToClipboard}
                onCheckedChange={(checked) => updateSetting("copyToClipboard", checked)}
              />
            </div>
          </CardContent>
        </Card>

        {/* Default Background */}
        <Card className="bg-zinc-900 border-zinc-800">
          <CardHeader className="pb-4">
            <CardTitle className="text-lg font-semibold text-zinc-100">Default Background</CardTitle>
          </CardHeader>
          <CardContent>
            <BackgroundImageSelector onImageSelect={handleImageSelect} />
          </CardContent>
        </Card>

        {/* Keyboard Shortcuts */}
        <Card className="bg-zinc-900 border-zinc-800">
          <CardHeader className="pb-4">
            <CardTitle className="text-lg font-semibold text-zinc-100">Keyboard Shortcuts</CardTitle>
          </CardHeader>
          <CardContent className="space-y-6">
            <KeyboardShortcutManager onShortcutsChange={handleShortcutsChange} />
            
            {/* Editor Shortcuts Reference */}
            <div className="space-y-3 pt-4 border-t border-zinc-800">
              <div>
                <p className="text-xs text-zinc-500 uppercase tracking-wide mb-3">Editor</p>
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
            </div>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
