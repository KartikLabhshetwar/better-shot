import "@testing-library/jest-dom/vitest";
import { vi } from "vitest";

// Mock Tauri APIs
vi.mock("@tauri-apps/plugin-store", () => ({
  Store: {
    load: vi.fn().mockResolvedValue({
      get: vi.fn().mockResolvedValue(null),
      set: vi.fn().mockResolvedValue(undefined),
      save: vi.fn().mockResolvedValue(undefined),
    }),
  },
}));

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
  convertFileSrc: vi.fn((path: string) => `asset://${path}`),
}));

vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: vi.fn().mockReturnValue({
    setFullscreen: vi.fn().mockResolvedValue(undefined),
    setAlwaysOnTop: vi.fn().mockResolvedValue(undefined),
    setDecorations: vi.fn().mockResolvedValue(undefined),
  }),
  availableMonitors: vi.fn().mockResolvedValue([]),
  LogicalPosition: vi.fn(),
  LogicalSize: vi.fn(),
}));
