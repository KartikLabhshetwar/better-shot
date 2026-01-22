import { create } from "zustand";
import { subscribeWithSelector } from "zustand/middleware";
import { immer } from "zustand/middleware/immer";
import { Store } from "@tauri-apps/plugin-store";
import { gradientOptions, type GradientOption } from "@/components/editor/BackgroundSelector";
import { resolveBackgroundPath, getDefaultBackgroundPath } from "@/lib/asset-registry";
import { Annotation } from "@/types/annotations";

// ============================================================================
// Types
// ============================================================================

export type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom" | "image";

export interface ShadowSettings {
  blur: number;
  offsetX: number;
  offsetY: number;
  opacity: number;
}

export type PaddingMode = "uniform" | "individual";

export interface PaddingSettings {
  mode: PaddingMode;
  uniform: number;
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface EditorSettings {
  backgroundType: BackgroundType;
  customColor: string;
  selectedImageSrc: string | null;
  gradientId: string;
  gradientSrc: string;
  gradientColors: [string, string];
  blurAmount: number;
  noiseAmount: number;
  borderRadius: number;
  padding: PaddingSettings;
  shadow: ShadowSettings;
}

// Snapshot for undo/redo - stores complete state
interface HistorySnapshot {
  settings: EditorSettings;
  annotations: Annotation[];
}

interface EditorState {
  // Settings slice
  settings: EditorSettings;
  
  // Annotations slice
  annotations: Annotation[];
  
  // History slice
  past: HistorySnapshot[];
  future: HistorySnapshot[];
  
  // Transient state (not part of history)
  _isInitialized: boolean;
  _historyPaused: boolean;
}

interface EditorActions {
  // Initialization
  initialize: () => Promise<void>;

  // Settings actions - immediate updates (no history push)
  updateSettingsTransient: (updates: Partial<EditorSettings>) => void;

  // Settings actions - commit to history
  updateSettings: (updates: Partial<EditorSettings>) => void;
  setBackgroundType: (type: BackgroundType) => void;
  setCustomColor: (color: string) => void;
  setSelectedImage: (src: string) => void;
  setGradient: (gradient: GradientOption) => void;
  handleImageSelect: (imageSrc: string) => void;

  // Transient settings (during slider drag)
  setBlurAmountTransient: (amount: number) => void;
  setNoiseAmountTransient: (amount: number) => void;
  setBorderRadiusTransient: (radius: number) => void;
  setPaddingUniformTransient: (padding: number) => void;
  setPaddingTopTransient: (padding: number) => void;
  setPaddingRightTransient: (padding: number) => void;
  setPaddingBottomTransient: (padding: number) => void;
  setPaddingLeftTransient: (padding: number) => void;
  setPaddingModeTransient: (mode: PaddingMode) => void;
  setShadowBlurTransient: (blur: number) => void;
  setShadowOffsetXTransient: (offsetX: number) => void;
  setShadowOffsetYTransient: (offsetY: number) => void;
  setShadowOpacityTransient: (opacity: number) => void;

  // Commit settings (on slider release)
  setBlurAmount: (amount: number) => void;
  setNoiseAmount: (amount: number) => void;
  setBorderRadius: (radius: number) => void;
  setPaddingUniform: (padding: number) => void;
  setPaddingTop: (padding: number) => void;
  setPaddingRight: (padding: number) => void;
  setPaddingBottom: (padding: number) => void;
  setPaddingLeft: (padding: number) => void;
  setPaddingMode: (mode: PaddingMode) => void;
  setShadowBlur: (blur: number) => void;
  setShadowOffsetX: (offsetX: number) => void;
  setShadowOffsetY: (offsetY: number) => void;
  setShadowOpacity: (opacity: number) => void;

  // Persist effect settings as defaults
  saveEffectSettingsAsDefaults: () => Promise<void>;

  // Annotation actions
  addAnnotation: (annotation: Annotation) => void;
  updateAnnotationTransient: (annotation: Annotation) => void;
  updateAnnotation: (annotation: Annotation) => void;
  deleteAnnotation: (id: string) => void;
  setAnnotations: (annotations: Annotation[]) => void;

  // History actions
  undo: () => void;
  redo: () => void;
  pushHistory: () => void;
  pauseHistory: () => void;
  resumeHistory: () => void;

  // Reset
  reset: () => void;
}

export type EditorStore = EditorState & EditorActions;

// ============================================================================
// Constants
// ============================================================================

const MAX_HISTORY_SIZE = 50;
const DEFAULT_GRADIENT = gradientOptions[0];
const DEFAULT_IMAGE = getDefaultBackgroundPath();

const DEFAULT_SETTINGS: EditorSettings = {
  backgroundType: "image",
  customColor: "#667eea",
  selectedImageSrc: DEFAULT_IMAGE,
  gradientId: DEFAULT_GRADIENT.id,
  gradientSrc: DEFAULT_GRADIENT.src,
  gradientColors: DEFAULT_GRADIENT.colors,
  blurAmount: 0,
  noiseAmount: 20,
  borderRadius: 18,
  padding: {
    mode: "uniform",
    uniform: 100,
    top: 100,
    right: 100,
    bottom: 100,
    left: 100,
  },
  shadow: {
    blur: 33,
    offsetX: 18,
    offsetY: 23,
    opacity: 39,
  },
};

const INITIAL_STATE: EditorState = {
  settings: DEFAULT_SETTINGS,
  annotations: [],
  past: [],
  future: [],
  _isInitialized: false,
  _historyPaused: false,
};

// ============================================================================
// Store
// ============================================================================

export const useEditorStore = create<EditorStore>()(
  subscribeWithSelector(
    immer((set, get) => ({
      ...INITIAL_STATE,

      // ========================================
      // Initialization
      // ========================================
      initialize: async () => {
        if (get()._isInitialized) return;

        try {
          const store = await Store.load("settings.json");

          // Load background settings
          const storedBgType = await store.get<BackgroundType>("defaultBackgroundType");
          const storedCustomColor = await store.get<string>("defaultCustomColor");
          const storedBg = await store.get<string>("defaultBackgroundImage");

          // Load effect settings
          const storedBlurAmount = await store.get<number>("defaultBlurAmount");
          const storedNoiseAmount = await store.get<number>("defaultNoiseAmount");
          const storedBorderRadius = await store.get<number>("defaultBorderRadius");
          const storedPadding = await store.get<PaddingSettings>("defaultPadding");
          const storedShadow = await store.get<ShadowSettings>("defaultShadow");

          set((state) => {
            // Apply background settings
            if (storedBgType) {
              state.settings.backgroundType = storedBgType;
            }
            if (storedCustomColor) {
              state.settings.customColor = storedCustomColor;
            }
            if (storedBg) {
              if (storedBgType === "image") {
                const resolvedPath = resolveBackgroundPath(storedBg);
                state.settings.selectedImageSrc = resolvedPath;
              }

              if (storedBg.startsWith("gradient-")) {
                const gradientIndex = storedBg.replace("gradient-", "");
                const gradient = gradientOptions.find(
                  (option) => option.id === `mesh-${gradientIndex}`
                );

                if (gradient) {
                  state.settings.gradientId = gradient.id;
                  state.settings.gradientSrc = gradient.src;
                  state.settings.gradientColors = gradient.colors;
                }
              }
            }

            // Apply effect settings
            if (storedBlurAmount !== null && storedBlurAmount !== undefined) {
              state.settings.blurAmount = storedBlurAmount;
            }
            if (storedNoiseAmount !== null && storedNoiseAmount !== undefined) {
              state.settings.noiseAmount = storedNoiseAmount;
            }
            if (storedBorderRadius !== null && storedBorderRadius !== undefined) {
              state.settings.borderRadius = storedBorderRadius;
            }
            if (storedPadding) {
              state.settings.padding = storedPadding;
            }
            if (storedShadow) {
              state.settings.shadow = storedShadow;
            }

            state._isInitialized = true;
          });
        } catch (err) {
          console.error("Failed to load default settings from store:", err);
          set((state) => {
            state._isInitialized = true;
          });
        }
      },

      // ========================================
      // Settings - Transient (no history)
      // ========================================
      updateSettingsTransient: (updates) => {
        set((state) => {
          Object.assign(state.settings, updates);
        });
      },

      // ========================================
      // Settings - With History
      // ========================================
      updateSettings: (updates) => {
        const state = get();
        if (!state._historyPaused) {
          get().pushHistory();
        }
        set((state) => {
          Object.assign(state.settings, updates);
          state.future = [];
        });
      },

      setBackgroundType: (type) => {
        get().updateSettings({ backgroundType: type });
      },

      setCustomColor: (color) => {
        get().updateSettings({ customColor: color });
      },

      setSelectedImage: (src) => {
        get().updateSettings({ selectedImageSrc: src });
      },

      setGradient: (gradient) => {
        get().updateSettings({
          gradientId: gradient.id,
          gradientSrc: gradient.src,
          gradientColors: gradient.colors,
        });
      },

      handleImageSelect: (imageSrc) => {
        get().updateSettings({
          selectedImageSrc: imageSrc,
          backgroundType: "image",
        });
      },

      // ========================================
      // Slider Settings - Transient (during drag)
      // ========================================
      setBlurAmountTransient: (amount) => {
        set((state) => {
          state.settings.blurAmount = amount;
        });
      },

      setNoiseAmountTransient: (amount) => {
        set((state) => {
          state.settings.noiseAmount = amount;
        });
      },

      setBorderRadiusTransient: (radius) => {
        set((state) => {
          state.settings.borderRadius = radius;
        });
      },

      setPaddingUniformTransient: (padding) => {
        set((state) => {
          state.settings.padding.uniform = padding;
          // Sync individual values when in uniform mode
          if (state.settings.padding.mode === "uniform") {
            state.settings.padding.top = padding;
            state.settings.padding.right = padding;
            state.settings.padding.bottom = padding;
            state.settings.padding.left = padding;
          }
        });
      },

      setPaddingTopTransient: (padding) => {
        set((state) => {
          state.settings.padding.top = padding;
        });
      },

      setPaddingRightTransient: (padding) => {
        set((state) => {
          state.settings.padding.right = padding;
        });
      },

      setPaddingBottomTransient: (padding) => {
        set((state) => {
          state.settings.padding.bottom = padding;
        });
      },

      setPaddingLeftTransient: (padding) => {
        set((state) => {
          state.settings.padding.left = padding;
        });
      },

      setPaddingModeTransient: (mode) => {
        set((state) => {
          state.settings.padding.mode = mode;
          // When switching to uniform, sync all values to the uniform value
          if (mode === "uniform") {
            const uniformValue = state.settings.padding.uniform;
            state.settings.padding.top = uniformValue;
            state.settings.padding.right = uniformValue;
            state.settings.padding.bottom = uniformValue;
            state.settings.padding.left = uniformValue;
          }
        });
      },

      setShadowBlurTransient: (blur) => {
        set((state) => {
          state.settings.shadow.blur = blur;
        });
      },

      setShadowOffsetXTransient: (offsetX) => {
        set((state) => {
          state.settings.shadow.offsetX = offsetX;
        });
      },

      setShadowOffsetYTransient: (offsetY) => {
        set((state) => {
          state.settings.shadow.offsetY = offsetY;
        });
      },

      setShadowOpacityTransient: (opacity) => {
        set((state) => {
          state.settings.shadow.opacity = opacity;
        });
      },

      // ========================================
      // Slider Settings - Commit (on release)
      // ========================================
      setBlurAmount: (amount) => {
        get().updateSettings({ blurAmount: amount });
      },

      setNoiseAmount: (amount) => {
        get().updateSettings({ noiseAmount: amount });
      },

      setBorderRadius: (radius) => {
        get().updateSettings({ borderRadius: radius });
      },

      setPaddingUniform: (padding) => {
        const currentMode = get().settings.padding.mode;
        const newPadding: PaddingSettings = {
          mode: currentMode,
          uniform: padding,
          top: currentMode === "uniform" ? padding : get().settings.padding.top,
          right: currentMode === "uniform" ? padding : get().settings.padding.right,
          bottom: currentMode === "uniform" ? padding : get().settings.padding.bottom,
          left: currentMode === "uniform" ? padding : get().settings.padding.left,
        };
        get().updateSettings({ padding: newPadding });
      },

      setPaddingTop: (padding) => {
        const current = get().settings.padding;
        get().updateSettings({
          padding: { ...current, top: padding },
        });
      },

      setPaddingRight: (padding) => {
        const current = get().settings.padding;
        get().updateSettings({
          padding: { ...current, right: padding },
        });
      },

      setPaddingBottom: (padding) => {
        const current = get().settings.padding;
        get().updateSettings({
          padding: { ...current, bottom: padding },
        });
      },

      setPaddingLeft: (padding) => {
        const current = get().settings.padding;
        get().updateSettings({
          padding: { ...current, left: padding },
        });
      },

      setPaddingMode: (mode) => {
        const current = get().settings.padding;
        const newPadding: PaddingSettings = {
          ...current,
          mode,
          // Sync values when switching to uniform
          top: mode === "uniform" ? current.uniform : current.top,
          right: mode === "uniform" ? current.uniform : current.right,
          bottom: mode === "uniform" ? current.uniform : current.bottom,
          left: mode === "uniform" ? current.uniform : current.left,
        };
        get().updateSettings({ padding: newPadding });
      },

      setShadowBlur: (blur) => {
        get().pushHistory();
        set((s) => {
          s.settings.shadow.blur = blur;
          s.future = [];
        });
      },

      setShadowOffsetX: (offsetX) => {
        get().pushHistory();
        set((state) => {
          state.settings.shadow.offsetX = offsetX;
          state.future = [];
        });
      },

      setShadowOffsetY: (offsetY) => {
        get().pushHistory();
        set((state) => {
          state.settings.shadow.offsetY = offsetY;
          state.future = [];
        });
      },

      setShadowOpacity: (opacity) => {
        get().pushHistory();
        set((state) => {
          state.settings.shadow.opacity = opacity;
          state.future = [];
        });
      },

      // ========================================
      // Persist Effect Settings
      // ========================================
      saveEffectSettingsAsDefaults: async () => {
        const state = get();
        try {
          const store = await Store.load("settings.json");
          await store.set("defaultBlurAmount", state.settings.blurAmount);
          await store.set("defaultNoiseAmount", state.settings.noiseAmount);
          await store.set("defaultBorderRadius", state.settings.borderRadius);
          await store.set("defaultPadding", state.settings.padding);
          await store.set("defaultShadow", state.settings.shadow);
          await store.save();
        } catch (err) {
          console.error("Failed to save effect settings as defaults:", err);
          throw err;
        }
      },

      // ========================================
      // Annotations
      // ========================================
      addAnnotation: (annotation) => {
        get().pushHistory();
        set((state) => {
          state.annotations.push(annotation);
          state.future = [];
        });
      },

      updateAnnotationTransient: (annotation) => {
        set((state) => {
          const index = state.annotations.findIndex((a) => a.id === annotation.id);
          if (index !== -1) {
            state.annotations[index] = annotation;
          }
        });
      },

      updateAnnotation: (annotation) => {
        get().pushHistory();
        set((state) => {
          const index = state.annotations.findIndex((a) => a.id === annotation.id);
          if (index !== -1) {
            state.annotations[index] = annotation;
          }
          state.future = [];
        });
      },

      deleteAnnotation: (id) => {
        get().pushHistory();
        set((state) => {
          state.annotations = state.annotations.filter((a) => a.id !== id);
          state.future = [];
        });
      },

      setAnnotations: (annotations) => {
        get().pushHistory();
        set((state) => {
          state.annotations = annotations;
          state.future = [];
        });
      },

      // ========================================
      // History
      // ========================================
      pushHistory: () => {
        const state = get();
        if (state._historyPaused) return;
        
        const snapshot: HistorySnapshot = {
          settings: structuredClone(state.settings),
          annotations: structuredClone(state.annotations),
        };
        
        set((s) => {
          s.past = [...s.past, snapshot].slice(-MAX_HISTORY_SIZE);
        });
      },

      pauseHistory: () => {
        set((state) => {
          state._historyPaused = true;
        });
      },

      resumeHistory: () => {
        set((state) => {
          state._historyPaused = false;
        });
      },

      undo: () => {
        const state = get();
        if (state.past.length === 0) return;

        const previous = state.past[state.past.length - 1];
        const currentSnapshot: HistorySnapshot = {
          settings: structuredClone(state.settings),
          annotations: structuredClone(state.annotations),
        };

        set((s) => {
          s.past = s.past.slice(0, -1);
          s.future = [currentSnapshot, ...s.future].slice(0, MAX_HISTORY_SIZE);
          s.settings = previous.settings;
          s.annotations = previous.annotations;
        });
      },

      redo: () => {
        const state = get();
        if (state.future.length === 0) return;

        const next = state.future[0];
        const currentSnapshot: HistorySnapshot = {
          settings: structuredClone(state.settings),
          annotations: structuredClone(state.annotations),
        };

        set((s) => {
          s.future = s.future.slice(1);
          s.past = [...s.past, currentSnapshot].slice(-MAX_HISTORY_SIZE);
          s.settings = next.settings;
          s.annotations = next.annotations;
        });
      },

      // ========================================
      // Reset
      // ========================================
      reset: () => {
        set((state) => {
          state.settings = structuredClone(DEFAULT_SETTINGS);
          state.annotations = [];
          state.past = [];
          state.future = [];
          state._isInitialized = false;
        });
      },
    }))
  )
);

// ============================================================================
// Selectors (for optimized re-renders)
// ============================================================================

// Settings selectors
export const useSettings = () => useEditorStore((state) => state.settings);
export const useBackgroundType = () => useEditorStore((state) => state.settings.backgroundType);
export const useNoiseAmount = () => useEditorStore((state) => state.settings.noiseAmount);
export const useBorderRadius = () => useEditorStore((state) => state.settings.borderRadius);
export const usePadding = () => useEditorStore((state) => state.settings.padding);
export const useShadow = () => useEditorStore((state) => state.settings.shadow);
export const useSelectedImageSrc = () => useEditorStore((state) => state.settings.selectedImageSrc);
export const useGradientId = () => useEditorStore((state) => state.settings.gradientId);

// Annotation selectors
export const useAnnotations = () => useEditorStore((state) => state.annotations);

// History selectors
export const useCanUndo = () => useEditorStore((state) => state.past.length > 0);
export const useCanRedo = () => useEditorStore((state) => state.future.length > 0);

// Actions - accessed directly from store to ensure stable references
// These functions are defined once in the store and never change
export const editorActions = {
  get initialize() { return useEditorStore.getState().initialize; },
  get setBackgroundType() { return useEditorStore.getState().setBackgroundType; },
  get setCustomColor() { return useEditorStore.getState().setCustomColor; },
  get setSelectedImage() { return useEditorStore.getState().setSelectedImage; },
  get setGradient() { return useEditorStore.getState().setGradient; },
  get handleImageSelect() { return useEditorStore.getState().handleImageSelect; },
  get setBlurAmount() { return useEditorStore.getState().setBlurAmount; },
  get setBlurAmountTransient() { return useEditorStore.getState().setBlurAmountTransient; },
  get setNoiseAmount() { return useEditorStore.getState().setNoiseAmount; },
  get setNoiseAmountTransient() { return useEditorStore.getState().setNoiseAmountTransient; },
  get setBorderRadius() { return useEditorStore.getState().setBorderRadius; },
  get setBorderRadiusTransient() { return useEditorStore.getState().setBorderRadiusTransient; },
  get setPaddingUniform() { return useEditorStore.getState().setPaddingUniform; },
  get setPaddingUniformTransient() { return useEditorStore.getState().setPaddingUniformTransient; },
  get setPaddingTop() { return useEditorStore.getState().setPaddingTop; },
  get setPaddingTopTransient() { return useEditorStore.getState().setPaddingTopTransient; },
  get setPaddingRight() { return useEditorStore.getState().setPaddingRight; },
  get setPaddingRightTransient() { return useEditorStore.getState().setPaddingRightTransient; },
  get setPaddingBottom() { return useEditorStore.getState().setPaddingBottom; },
  get setPaddingBottomTransient() { return useEditorStore.getState().setPaddingBottomTransient; },
  get setPaddingLeft() { return useEditorStore.getState().setPaddingLeft; },
  get setPaddingLeftTransient() { return useEditorStore.getState().setPaddingLeftTransient; },
  get setPaddingMode() { return useEditorStore.getState().setPaddingMode; },
  get setPaddingModeTransient() { return useEditorStore.getState().setPaddingModeTransient; },
  get setShadowBlur() { return useEditorStore.getState().setShadowBlur; },
  get setShadowBlurTransient() { return useEditorStore.getState().setShadowBlurTransient; },
  get setShadowOffsetX() { return useEditorStore.getState().setShadowOffsetX; },
  get setShadowOffsetXTransient() { return useEditorStore.getState().setShadowOffsetXTransient; },
  get setShadowOffsetY() { return useEditorStore.getState().setShadowOffsetY; },
  get setShadowOffsetYTransient() { return useEditorStore.getState().setShadowOffsetYTransient; },
  get setShadowOpacity() { return useEditorStore.getState().setShadowOpacity; },
  get setShadowOpacityTransient() { return useEditorStore.getState().setShadowOpacityTransient; },
  get saveEffectSettingsAsDefaults() { return useEditorStore.getState().saveEffectSettingsAsDefaults; },
  get addAnnotation() { return useEditorStore.getState().addAnnotation; },
  get updateAnnotation() { return useEditorStore.getState().updateAnnotation; },
  get updateAnnotationTransient() { return useEditorStore.getState().updateAnnotationTransient; },
  get deleteAnnotation() { return useEditorStore.getState().deleteAnnotation; },
  get setAnnotations() { return useEditorStore.getState().setAnnotations; },
  get undo() { return useEditorStore.getState().undo; },
  get redo() { return useEditorStore.getState().redo; },
  get pushHistory() { return useEditorStore.getState().pushHistory; },
  get pauseHistory() { return useEditorStore.getState().pauseHistory; },
  get resumeHistory() { return useEditorStore.getState().resumeHistory; },
  get reset() { return useEditorStore.getState().reset; },
};

// Hook version - returns the stable actions object
export const useEditorActions = () => editorActions;
