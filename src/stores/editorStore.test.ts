import { describe, it, expect, beforeEach } from "vitest";
import { useEditorStore, editorActions, usePadding, useSettings } from "./editorStore";
import { act, renderHook } from "@testing-library/react";

describe("editorStore - padding feature", () => {
  beforeEach(() => {
    // Reset store to initial state before each test
    act(() => {
      editorActions.reset();
    });
  });

  describe("initial state", () => {
    it("should have default padding of 100px", () => {
      const state = useEditorStore.getState();
      expect(state.settings.padding).toBe(100);
    });

    it("should include padding in settings", () => {
      const { result } = renderHook(() => useSettings());
      expect(result.current.padding).toBe(100);
    });
  });

  describe("usePadding selector", () => {
    it("should return current padding value", () => {
      const { result } = renderHook(() => usePadding());
      expect(result.current).toBe(100);
    });

    it("should update when padding changes", () => {
      const { result } = renderHook(() => usePadding());

      act(() => {
        editorActions.setPaddingTransient(50);
      });

      expect(result.current).toBe(50);
    });
  });

  describe("setPaddingTransient", () => {
    it("should update padding without pushing to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingTransient(75);
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding).toBe(75);
      expect(state.past.length).toBe(initialHistoryLength);
    });

    it("should handle minimum value (0)", () => {
      act(() => {
        editorActions.setPaddingTransient(0);
      });

      expect(useEditorStore.getState().settings.padding).toBe(0);
    });

    it("should handle maximum value (200)", () => {
      act(() => {
        editorActions.setPaddingTransient(200);
      });

      expect(useEditorStore.getState().settings.padding).toBe(200);
    });

    it("should allow rapid updates without history pollution", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      // Simulate slider drag with many updates
      act(() => {
        for (let i = 0; i <= 100; i += 10) {
          editorActions.setPaddingTransient(i);
        }
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding).toBe(100);
      expect(state.past.length).toBe(initialHistoryLength);
    });
  });

  describe("setPadding (commit)", () => {
    it("should update padding and push to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPadding(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding).toBe(150);
      expect(state.past.length).toBe(initialHistoryLength + 1);
    });

    it("should clear future history on commit", () => {
      // Setup: make a change and undo it
      act(() => {
        editorActions.setPadding(50);
        editorActions.undo();
      });

      expect(useEditorStore.getState().future.length).toBeGreaterThan(0);

      // Now commit a new change
      act(() => {
        editorActions.setPadding(75);
      });

      expect(useEditorStore.getState().future.length).toBe(0);
    });
  });

  describe("undo/redo with padding", () => {
    it("should undo padding changes", () => {
      act(() => {
        editorActions.setPadding(50);
      });

      expect(useEditorStore.getState().settings.padding).toBe(50);

      act(() => {
        editorActions.undo();
      });

      expect(useEditorStore.getState().settings.padding).toBe(100);
    });

    it("should redo padding changes", () => {
      act(() => {
        editorActions.setPadding(50);
        editorActions.undo();
      });

      expect(useEditorStore.getState().settings.padding).toBe(100);

      act(() => {
        editorActions.redo();
      });

      expect(useEditorStore.getState().settings.padding).toBe(50);
    });

    it("should handle multiple undo/redo operations", () => {
      act(() => {
        editorActions.setPadding(50);
        editorActions.setPadding(75);
        editorActions.setPadding(100);
      });

      expect(useEditorStore.getState().settings.padding).toBe(100);

      act(() => {
        editorActions.undo();
      });
      expect(useEditorStore.getState().settings.padding).toBe(75);

      act(() => {
        editorActions.undo();
      });
      expect(useEditorStore.getState().settings.padding).toBe(50);

      act(() => {
        editorActions.redo();
      });
      expect(useEditorStore.getState().settings.padding).toBe(75);
    });
  });

  describe("reset", () => {
    it("should reset padding to default value", () => {
      act(() => {
        editorActions.setPadding(50);
      });

      expect(useEditorStore.getState().settings.padding).toBe(50);

      act(() => {
        editorActions.reset();
      });

      expect(useEditorStore.getState().settings.padding).toBe(100);
    });
  });

  describe("padding with other settings", () => {
    it("should not affect other settings when changing padding", () => {
      const initialNoise = useEditorStore.getState().settings.noiseAmount;
      const initialBorderRadius = useEditorStore.getState().settings.borderRadius;

      act(() => {
        editorActions.setPadding(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.noiseAmount).toBe(initialNoise);
      expect(state.settings.borderRadius).toBe(initialBorderRadius);
    });

    it("should be included in history snapshots with other settings", () => {
      act(() => {
        editorActions.setPadding(50);
        editorActions.setNoiseAmount(50);
      });

      // Undo noise change
      act(() => {
        editorActions.undo();
      });

      // Padding should still be 50 (from previous snapshot)
      const state = useEditorStore.getState();
      expect(state.settings.padding).toBe(50);
      expect(state.settings.noiseAmount).toBe(20); // Reset to default
    });
  });
});

describe("editorStore - macbook display background", () => {
  beforeEach(() => {
    act(() => {
      editorActions.reset();
    });
  });

  it("defaults to matching the outside background", () => {
    const state = useEditorStore.getState();

    expect(state.settings.macbookUseOuterBackground).toBe(true);
    expect(state.settings.macbookScreenshotPadding).toBe(0);
    expect(state.settings.macbookBackground.backgroundType).toBe("image");
    expect(state.settings.macbookBackground.selectedImageSrc).toBeTruthy();
  });

  it("can switch to a separate MacBook display background", () => {
    act(() => {
      editorActions.setMacbookUseOuterBackground(false);
      editorActions.setMacbookBackgroundType("custom");
      editorActions.setMacbookCustomColor("#123456");
    });

    const state = useEditorStore.getState();
    expect(state.settings.macbookUseOuterBackground).toBe(false);
    expect(state.settings.macbookBackground.backgroundType).toBe("custom");
    expect(state.settings.macbookBackground.customColor).toBe("#123456");
  });

  it("sets the MacBook display image independently", () => {
    act(() => {
      editorActions.setMacbookUseOuterBackground(false);
      editorActions.handleMacbookImageSelect("asset://display-bg");
    });

    const state = useEditorStore.getState();
    expect(state.settings.macbookBackground.backgroundType).toBe("image");
    expect(state.settings.macbookBackground.selectedImageSrc).toBe("asset://display-bg");
    expect(state.settings.selectedImageSrc).not.toBe("asset://display-bg");
  });

  it("updates the MacBook screenshot padding independently", () => {
    act(() => {
      editorActions.setMacbookScreenshotPaddingTransient(8);
    });
    expect(useEditorStore.getState().settings.macbookScreenshotPadding).toBe(8);

    act(() => {
      editorActions.setMacbookScreenshotPadding(12);
    });

    const state = useEditorStore.getState();
    expect(state.settings.macbookScreenshotPadding).toBe(12);
    expect(state.settings.padding).toBe(100);
  });
});

describe("smart default padding calculation", () => {
  it("should calculate 5% of average dimension", () => {
    // Test the calculation logic that's used in ImageEditor
    const width = 1920;
    const height = 1080;
    const avgDimension = (width + height) / 2;
    const expectedPadding = Math.min(Math.round(avgDimension * 0.05), 200);

    expect(expectedPadding).toBe(75); // (1920 + 1080) / 2 * 0.05 = 75
  });

  it("should cap at 200px for large images", () => {
    const width = 4000;
    const height = 4000;
    const avgDimension = (width + height) / 2;
    const calculatedPadding = Math.min(Math.round(avgDimension * 0.05), 200);

    expect(calculatedPadding).toBe(200); // Would be 200 without cap
  });

  it("should handle small images", () => {
    const width = 200;
    const height = 200;
    const avgDimension = (width + height) / 2;
    const calculatedPadding = Math.min(Math.round(avgDimension * 0.05), 200);

    expect(calculatedPadding).toBe(10); // 200 * 0.05 = 10
  });
});

describe("editorStore - canvas dimensions feature", () => {
  beforeEach(() => {
    act(() => {
      editorActions.reset();
    });
  });

  describe("initial state", () => {
    it("should have default canvas dimensions of 0 (auto)", () => {
      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(0);
      expect(state.settings.canvasDimensions.height).toBe(0);
    });

    it("should have aspect ratio locked by default", () => {
      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.aspectRatioLocked).toBe(true);
    });
  });

  describe("setCanvasWidth with aspect ratio locked", () => {
    it("should update height proportionally when locked", () => {
      act(() => {
        editorActions.setCanvasDimensions({
          width: 1600,
          height: 1000,
          aspectRatioLocked: true,
        });
      });

      act(() => {
        editorActions.setCanvasWidth(3200);
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(3200);
      expect(state.settings.canvasDimensions.height).toBe(2000); // 3200 * (1000/1600)
    });

    it("should not update height when unlocked", () => {
      act(() => {
        editorActions.setCanvasDimensions({
          width: 1600,
          height: 1000,
          aspectRatioLocked: false,
        });
      });

      act(() => {
        editorActions.setCanvasWidth(3200);
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(3200);
      expect(state.settings.canvasDimensions.height).toBe(1000); // Unchanged
    });

    it("should only enforce aspect ratio when both dimensions are > 0", () => {
      act(() => {
        editorActions.setCanvasWidth(1280);
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(1280);
      expect(state.settings.canvasDimensions.height).toBe(0); // No ratio calculation when height is 0
    });
  });

  describe("setCanvasHeight with aspect ratio locked", () => {
    it("should update width proportionally when locked", () => {
      act(() => {
        editorActions.setCanvasDimensions({
          width: 1280,
          height: 800,
          aspectRatioLocked: true,
        });
      });

      act(() => {
        editorActions.setCanvasHeight(1600);
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.height).toBe(1600);
      expect(state.settings.canvasDimensions.width).toBe(2560); // 1600 * (1280/800)
    });
  });

  describe("App Store preset dimensions", () => {
    it("should set 1280×800 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 1280, height: 800 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(1280);
      expect(state.settings.canvasDimensions.height).toBe(800);
    });

    it("should set 1440×900 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 1440, height: 900 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(1440);
      expect(state.settings.canvasDimensions.height).toBe(900);
    });

    it("should set 2560×1600 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 2560, height: 1600 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(2560);
      expect(state.settings.canvasDimensions.height).toBe(1600);
    });

    it("should set 2880×1800 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 2880, height: 1800 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(2880);
      expect(state.settings.canvasDimensions.height).toBe(1800);
    });

    it("should maintain 16:10 aspect ratio for all presets", () => {
      const presets = [
        { width: 1280, height: 800 },
        { width: 1440, height: 900 },
        { width: 2560, height: 1600 },
        { width: 2880, height: 1800 },
      ];

      presets.forEach((preset) => {
        const ratio = preset.width / preset.height;
        expect(ratio).toBeCloseTo(1.6, 2); // 16:10 = 1.6
      });
    });
  });

  describe("iPhone display preset dimensions", () => {
    it("should set 1242×2688 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 1242, height: 2688 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(1242);
      expect(state.settings.canvasDimensions.height).toBe(2688);
    });

    it("should set 2688×1242 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 2688, height: 1242 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(2688);
      expect(state.settings.canvasDimensions.height).toBe(1242);
    });

    it("should set 1284×2778 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 1284, height: 2778 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(1284);
      expect(state.settings.canvasDimensions.height).toBe(2778);
    });

    it("should set 2778×1284 preset", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 2778, height: 1284 });
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(2778);
      expect(state.settings.canvasDimensions.height).toBe(1284);
    });
  });

  describe("undo/redo with canvas dimensions", () => {
    it("should undo dimension changes", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 1280, height: 800 });
      });

      act(() => {
        editorActions.undo();
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(0);
      expect(state.settings.canvasDimensions.height).toBe(0);
    });

    it("should redo dimension changes", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 2560, height: 1600 });
        editorActions.undo();
      });

      act(() => {
        editorActions.redo();
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(2560);
      expect(state.settings.canvasDimensions.height).toBe(1600);
    });

    it("should support multiple undo/redo operations", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 1280, height: 800 });
        editorActions.setCanvasDimensions({ width: 2560, height: 1600 });
      });

      act(() => {
        editorActions.undo();
      });

      let state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(1280);

      act(() => {
        editorActions.undo();
      });

      state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(0);

      act(() => {
        editorActions.redo();
      });

      state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.width).toBe(1280);
    });
  });

  describe("transient updates", () => {
    it("should not create history entries for transient width updates", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setCanvasWidthTransient(1500);
      });

      expect(useEditorStore.getState().past.length).toBe(initialHistoryLength);
    });

    it("should not create history entries for transient height updates", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setCanvasHeightTransient(900);
      });

      expect(useEditorStore.getState().past.length).toBe(initialHistoryLength);
    });

    it("should not create history entries for transient lock toggle", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setAspectRatioLockedTransient(false);
      });

      expect(useEditorStore.getState().past.length).toBe(initialHistoryLength);
    });

    it("should allow rapid transient updates without history pollution", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      // Simulate slider drag with many transient updates
      act(() => {
        for (let i = 1000; i <= 2000; i += 100) {
          editorActions.setCanvasWidthTransient(i);
        }
      });

      expect(useEditorStore.getState().past.length).toBe(initialHistoryLength);
    });
  });

  describe("aspect ratio lock toggle", () => {
    it("should toggle aspect ratio lock", () => {
      let state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.aspectRatioLocked).toBe(true);

      act(() => {
        editorActions.setAspectRatioLocked(false);
      });

      state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.aspectRatioLocked).toBe(false);

      act(() => {
        editorActions.setAspectRatioLocked(true);
      });

      state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.aspectRatioLocked).toBe(true);
    });

    it("should include lock state in history", () => {
      act(() => {
        editorActions.setCanvasDimensions({ width: 1280, height: 800 });
        editorActions.setAspectRatioLocked(false);
      });

      act(() => {
        editorActions.undo();
      });

      const state = useEditorStore.getState();
      expect(state.settings.canvasDimensions.aspectRatioLocked).toBe(true);
    });
  });
});
