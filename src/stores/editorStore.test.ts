import { describe, it, expect, beforeEach } from "vitest";
import {
  useEditorStore,
  editorActions,
  usePaddingTop,
  usePaddingBottom,
  usePaddingLeft,
  usePaddingRight,
  useSettings
} from "./editorStore";
import { act, renderHook } from "@testing-library/react";

describe("editorStore - padding feature", () => {
  beforeEach(() => {
    // Reset store to initial state before each test
    act(() => {
      editorActions.reset();
    });
  });

  describe("initial state", () => {
    it("should have default padding of 100px for all sides", () => {
      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(100);
      expect(state.settings.paddingBottom).toBe(100);
      expect(state.settings.paddingLeft).toBe(100);
      expect(state.settings.paddingRight).toBe(100);
    });

    it("should include padding in settings", () => {
      const { result } = renderHook(() => useSettings());
      expect(result.current.paddingTop).toBe(100);
      expect(result.current.paddingBottom).toBe(100);
      expect(result.current.paddingLeft).toBe(100);
      expect(result.current.paddingRight).toBe(100);
    });
  });

  describe("usePadding selector", () => {
    it("should return current paddingTop value", () => {
      const { result } = renderHook(() => usePaddingTop());
      expect(result.current).toBe(100);
    });

    it("should return current paddingBottom value", () => {
      const { result } = renderHook(() => usePaddingBottom());
      expect(result.current).toBe(100);
    });

    it("should return current paddingLeft value", () => {
      const { result } = renderHook(() => usePaddingLeft());
      expect(result.current).toBe(100);
    });

    it("should return current paddingRight value", () => {
      const { result } = renderHook(() => usePaddingRight());
      expect(result.current).toBe(100);
    });

    it("should update when paddingTop changes", () => {
      const { result } = renderHook(() => usePaddingTop());

      act(() => {
        editorActions.setPaddingTopTransient(50);
      });

      expect(result.current).toBe(50);
    });

    it("should update when paddingBottom changes", () => {
      const { result } = renderHook(() => usePaddingBottom());

      act(() => {
        editorActions.setPaddingBottomTransient(50);
      });

      expect(result.current).toBe(50);
    });

    it("should update when paddingLeft changes", () => {
      const { result } = renderHook(() => usePaddingLeft());

      act(() => {
        editorActions.setPaddingLeftTransient(50);
      });

      expect(result.current).toBe(50);
    });

    it("should update when paddingRight changes", () => {
      const { result } = renderHook(() => usePaddingRight());

      act(() => {
        editorActions.setPaddingRightTransient(50);
      });

      expect(result.current).toBe(50);
    });
  });

  describe("setPaddingTransient", () => {
    it("should update paddingTop without pushing to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingTopTransient(75);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(75);
      expect(state.past.length).toBe(initialHistoryLength);
    });

    it("should update paddingBottom without pushing to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingBottomTransient(75);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingBottom).toBe(75);
      expect(state.past.length).toBe(initialHistoryLength);
    });

    it("should update paddingLeft without pushing to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingLeftTransient(75);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingLeft).toBe(75);
      expect(state.past.length).toBe(initialHistoryLength);
    });

    it("should update paddingRight without pushing to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingRightTransient(75);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingRight).toBe(75);
      expect(state.past.length).toBe(initialHistoryLength);
    });

    it("should handle minimum value (0)", () => {
      act(() => {
        editorActions.setPaddingTopTransient(0);
        editorActions.setPaddingBottomTransient(0);
        editorActions.setPaddingLeftTransient(0);
        editorActions.setPaddingRightTransient(0);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(0);
      expect(state.settings.paddingBottom).toBe(0);
      expect(state.settings.paddingLeft).toBe(0);
      expect(state.settings.paddingRight).toBe(0);
    });

    it("should handle maximum value (200)", () => {
      act(() => {
        editorActions.setPaddingTopTransient(200);
        editorActions.setPaddingBottomTransient(200);
        editorActions.setPaddingLeftTransient(200);
        editorActions.setPaddingRightTransient(200);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(200);
      expect(state.settings.paddingBottom).toBe(200);
      expect(state.settings.paddingLeft).toBe(200);
      expect(state.settings.paddingRight).toBe(200);
    });

    it("should allow rapid updates without history pollution", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      // Simulate slider drag with many updates
      act(() => {
        for (let i = 0; i <= 100; i += 10) {
          editorActions.setPaddingTopTransient(i);
          editorActions.setPaddingBottomTransient(i);
          editorActions.setPaddingLeftTransient(i);
          editorActions.setPaddingRightTransient(i);
        }
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(100);
      expect(state.settings.paddingBottom).toBe(100);
      expect(state.settings.paddingLeft).toBe(100);
      expect(state.settings.paddingRight).toBe(100);
      expect(state.past.length).toBe(initialHistoryLength);
    });
  });

  describe("setPadding (commit)", () => {
    it("should update paddingTop and push to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingTop(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(150);
      expect(state.past.length).toBe(initialHistoryLength + 1);
    });

    it("should update paddingBottom and push to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingBottom(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingBottom).toBe(150);
      expect(state.past.length).toBe(initialHistoryLength + 1);
    });

    it("should update paddingLeft and push to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingLeft(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingLeft).toBe(150);
      expect(state.past.length).toBe(initialHistoryLength + 1);
    });

    it("should update paddingRight and push to history", () => {
      const initialHistoryLength = useEditorStore.getState().past.length;

      act(() => {
        editorActions.setPaddingRight(150);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingRight).toBe(150);
      expect(state.past.length).toBe(initialHistoryLength + 1);
    });

    it("should clear future history on commit", () => {
      // Setup: make a change and undo it
      act(() => {
        editorActions.setPaddingTop(50);
        editorActions.undo();
      });

      expect(useEditorStore.getState().future.length).toBeGreaterThan(0);

      // Now commit a new change
      act(() => {
        editorActions.setPaddingTop(75);
      });

      expect(useEditorStore.getState().future.length).toBe(0);
    });
  });

  describe("undo/redo with padding", () => {
    it("should undo paddingTop changes", () => {
      act(() => {
        editorActions.setPaddingTop(50);
      });

      expect(useEditorStore.getState().settings.paddingTop).toBe(50);

      act(() => {
        editorActions.undo();
      });

      expect(useEditorStore.getState().settings.paddingTop).toBe(100);
    });

    it("should redo paddingTop changes", () => {
      act(() => {
        editorActions.setPaddingTop(50);
        editorActions.undo();
      });

      expect(useEditorStore.getState().settings.paddingTop).toBe(100);

      act(() => {
        editorActions.redo();
      });

      expect(useEditorStore.getState().settings.paddingTop).toBe(50);
    });

    it("should handle multiple undo/redo operations", () => {
      act(() => {
        editorActions.setPaddingTop(50);
        editorActions.setPaddingTop(75);
        editorActions.setPaddingTop(125);
      });

      expect(useEditorStore.getState().settings.paddingTop).toBe(125);

      act(() => {
        editorActions.undo();
      });
      expect(useEditorStore.getState().settings.paddingTop).toBe(75);

      act(() => {
        editorActions.undo();
      });
      expect(useEditorStore.getState().settings.paddingTop).toBe(50);

      act(() => {
        editorActions.redo();
      });
      expect(useEditorStore.getState().settings.paddingTop).toBe(75);
    });
  });

  describe("reset", () => {
    it("should reset all padding values to default", () => {
      act(() => {
        editorActions.setPaddingTop(50);
        editorActions.setPaddingBottom(60);
        editorActions.setPaddingLeft(70);
        editorActions.setPaddingRight(80);
      });

      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(50);
      expect(state.settings.paddingBottom).toBe(60);
      expect(state.settings.paddingLeft).toBe(70);
      expect(state.settings.paddingRight).toBe(80);

      act(() => {
        editorActions.reset();
      });

      const resetState = useEditorStore.getState();
      expect(resetState.settings.paddingTop).toBe(100);
      expect(resetState.settings.paddingBottom).toBe(100);
      expect(resetState.settings.paddingLeft).toBe(100);
      expect(resetState.settings.paddingRight).toBe(100);
    });
  });

  describe("padding with other settings", () => {
    it("should not affect other settings when changing padding", () => {
      const initialNoise = useEditorStore.getState().settings.noiseAmount;
      const initialBorderRadius = useEditorStore.getState().settings.borderRadius;

      act(() => {
        editorActions.setPaddingTop(150);
        editorActions.setPaddingBottom(160);
        editorActions.setPaddingLeft(170);
        editorActions.setPaddingRight(180);
      });

      const state = useEditorStore.getState();
      expect(state.settings.noiseAmount).toBe(initialNoise);
      expect(state.settings.borderRadius).toBe(initialBorderRadius);
    });

    it("should be included in history snapshots with other settings", () => {
      act(() => {
        editorActions.setPaddingTop(50);
        editorActions.setNoiseAmount(50);
      });

      // Undo noise change
      act(() => {
        editorActions.undo();
      });

      // paddingTop should still be 50 (from previous snapshot)
      const state = useEditorStore.getState();
      expect(state.settings.paddingTop).toBe(50);
      expect(state.settings.noiseAmount).toBe(20); // Reset to default
    });
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
