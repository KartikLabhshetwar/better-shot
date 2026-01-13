import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/**
 * Detect if running on macOS
 * Uses navigator.platform for browser context
 */
export function isMacOS(): boolean {
  if (typeof navigator !== 'undefined') {
    return navigator.platform.toLowerCase().includes('mac');
  }
  return false;
}

/**
 * Format keyboard shortcut for display based on platform
 * Converts from Tauri format to human-readable format
 */
export function formatShortcutForPlatform(shortcut: string): string {
  const isMac = isMacOS();
  
  if (isMac) {
    return shortcut
      .replace(/CommandOrControl/g, "⌘")
      .replace(/Command/g, "⌘")
      .replace(/Control/g, "⌃")
      .replace(/Shift/g, "⇧")
      .replace(/Alt/g, "⌥")
      .replace(/Option/g, "⌥")
      .replace(/\+/g, "");
  } else {
    return shortcut
      .replace(/CommandOrControl/g, "Ctrl")
      .replace(/Command/g, "Ctrl")
      .replace(/Control/g, "Ctrl")
      .replace(/Shift/g, "Shift")
      .replace(/Alt/g, "Alt")
      .replace(/Option/g, "Alt")
      .replace(/\+/g, "+");
  }
}
