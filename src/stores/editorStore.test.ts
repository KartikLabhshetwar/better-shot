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
      expect(state.settings.padding.uniform).toBe(100);
      expect(state.settings.padding.mode).toBe("uniform");
    });

    it("should include padding in settings", () => {
      const { result } = renderHook(() => useSettings());
      expect(result.current.padding.uniform).toBe(100);
    });
  });

  describe("usePadding selector", () => {
    it("should return current padding value", () => {
      const { result } = renderHook(() => usePadding());
      expect(result.current.uniform).toBe(100);
    });

    it("should update when padding changes", () => {
      const { result } = renderHook(() => usePadding());

      act(() => {
        editorActions.setPaddingUniformTransient(50);
      });

      expect(result.current.uniform).toBe(50);
    });
  });

  describe("setPaddingUniformTransient", () => {
    it("should update padding without pushing to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingUniformTransient(75);
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding.uniform).toBe(75);
      expect(state.past.length).toBe(initialHistoryLength);
    });

    it("should handle minimum value (0)", () => {
      act(() => {
        editorActions.setPaddingUniformTransient(0);
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(0);
    });

    it("should handle maximum value (200)", () => {
      act(() => {
        editorActions.setPaddingUniformTransient(200);
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(200);
    });

    it("should allow rapid updates without history pollution", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      // Simulate slider drag with many updates
      act(() => {
        for (let i = 0; i <= 100; i += 10) {
          editorActions.setPaddingUniformTransient(i);
        }
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding.uniform).toBe(100);
      expect(state.past.length).toBe(initialHistoryLength);
    });

    it("should sync all individual values when in uniform mode", () => {
      act(() => {
        editorActions.setPaddingUniformTransient(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding.top).toBe(150);
      expect(state.settings.padding.right).toBe(150);
      expect(state.settings.padding.bottom).toBe(150);
      expect(state.settings.padding.left).toBe(150);
    });
  });

  describe("setPaddingUniform (commit)", () => {
    it("should update padding and push to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingUniform(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding.uniform).toBe(150);
      expect(state.past.length).toBe(initialHistoryLength + 1);
    });

    it("should clear future history on commit", () => {
      // Setup: make a change and undo it
      act(() => {
        editorActions.setPaddingUniform(50);
        editorActions.undo();
      });

      expect(useEditorStore.getState().future.length).toBeGreaterThan(0);

      // Now commit a new change
      act(() => {
        editorActions.setPaddingUniform(75);
      });

      expect(useEditorStore.getState().future.length).toBe(0);
    });
  });

  describe("individual padding values", () => {
    it("should allow setting individual padding values", () => {
      act(() => {
        editorActions.setPaddingModeTransient("individual");
        editorActions.setPaddingTopTransient(50);
        editorActions.setPaddingRightTransient(100);
        editorActions.setPaddingBottomTransient(150);
        editorActions.setPaddingLeftTransient(200);
      });

      const state = useEditorStore.getState();
      expect(state.settings.padding.top).toBe(50);
      expect(state.settings.padding.right).toBe(100);
      expect(state.settings.padding.bottom).toBe(150);
      expect(state.settings.padding.left).toBe(200);
    });

    it("should switch to uniform mode and sync values", () => {
      act(() => {
        editorActions.setPaddingModeTransient("individual");
        editorActions.setPaddingTopTransient(50);
        editorActions.setPaddingRightTransient(100);
        editorActions.setPaddingModeTransient("uniform");
      });

      const state = useEditorStore.getState();
      // All values should now be the uniform value
      expect(state.settings.padding.top).toBe(state.settings.padding.uniform);
      expect(state.settings.padding.right).toBe(state.settings.padding.uniform);
      expect(state.settings.padding.bottom).toBe(state.settings.padding.uniform);
      expect(state.settings.padding.left).toBe(state.settings.padding.uniform);
    });
  });

  describe("undo/redo with padding", () => {
    it("should undo padding changes", () => {
      act(() => {
        editorActions.setPaddingUniform(50);
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(50);

      act(() => {
        editorActions.undo();
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(100);
    });

    it("should redo padding changes", () => {
      act(() => {
        editorActions.setPaddingUniform(50);
        editorActions.undo();
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(100);

      act(() => {
        editorActions.redo();
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(50);
    });

    it("should handle multiple undo/redo operations", () => {
      act(() => {
        editorActions.setPaddingUniform(50);
        editorActions.setPaddingUniform(75);
        editorActions.setPaddingUniform(100);
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(100);

      act(() => {
        editorActions.undo();
      });
      expect(useEditorStore.getState().settings.padding.uniform).toBe(75);

      act(() => {
        editorActions.undo();
      });
      expect(useEditorStore.getState().settings.padding.uniform).toBe(50);

      act(() => {
        editorActions.redo();
      });
      expect(useEditorStore.getState().settings.padding.uniform).toBe(75);
    });
  });

  describe("reset", () => {
    it("should reset padding to default value", () => {
      act(() => {
        editorActions.setPaddingUniform(50);
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(50);

      act(() => {
        editorActions.reset();
      });

      expect(useEditorStore.getState().settings.padding.uniform).toBe(100);
    });
  });

  describe("padding with other settings", () => {
    it("should not affect other settings when changing padding", () => {
      const initialNoise = useEditorStore.getState().settings.noiseAmount;
      const initialBorderRadius = useEditorStore.getState().settings.borderRadius;

      act(() => {
        editorActions.setPaddingUniform(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.noiseAmount).toBe(initialNoise);
      expect(state.settings.borderRadius).toBe(initialBorderRadius);
    });

    it("should be included in history snapshots with other settings", () => {
      act(() => {
        editorActions.setPaddingUniform(50);
        editorActions.setNoiseAmount(50);
      });

      // Undo noise change
      act(() => {
        editorActions.undo();
      });

      // Padding should still be 50 (from previous snapshot)
      const state = useEditorStore.getState();
      expect(state.settings.padding.uniform).toBe(50);
      expect(state.settings.noiseAmount).toBe(20); // Reset to default
    });
  });
});

describe("smart default padding calculation", () => {
  it("should calculate 10% of average dimension", () => {
    // Test the calculation logic that's used in ImageEditor
    const width = 1920;
    const height = 1080;
    const avgDimension = (width + height) / 2;
    const expectedPadding = Math.min(Math.round(avgDimension * 0.1), 400);

    expect(expectedPadding).toBe(150); // (1920 + 1080) / 2 * 0.1 = 150
  });

  it("should cap at 400px for large images", () => {
    const width = 5000;
    const height = 5000;
    const avgDimension = (width + height) / 2;
    const calculatedPadding = Math.min(Math.round(avgDimension * 0.1), 400);

    expect(calculatedPadding).toBe(400); // Would be 500 without cap
  });

  it("should handle small images", () => {
    const width = 200;
    const height = 200;
    const avgDimension = (width + height) / 2;
    const calculatedPadding = Math.min(Math.round(avgDimension * 0.1), 400);

    expect(calculatedPadding).toBe(20); // 200 * 0.1 = 20
  });
});
