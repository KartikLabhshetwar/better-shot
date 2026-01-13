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
  setShadowBlurTransient: (blur: number) => void;
  setShadowOffsetXTransient: (offsetX: number) => void;
  setShadowOffsetYTransient: (offsetY: number) => void;
  setShadowOpacityTransient: (opacity: number) => void;
  
  // Commit settings (on slider release)
  setBlurAmount: (amount: number) => void;
  setNoiseAmount: (amount: number) => void;
  setBorderRadius: (radius: number) => void;
  setShadowBlur: (blur: number) => void;
  setShadowOffsetX: (offsetX: number) => void;
  setShadowOffsetY: (offsetY: number) => void;
  setShadowOpacity: (opacity: number) => void;
  
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
  shadow: {
    blur: 20,
    offsetX: 0,
    offsetY: 10,
    opacity: 30,
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
          const storedBg = await store.get<string>("defaultBackgroundImage");
          if (storedBg) {
            const resolvedPath = resolveBackgroundPath(storedBg);
            set((state) => {
              state.settings.selectedImageSrc = resolvedPath;
              state._isInitialized = true;
            });
          } else {
            set((state) => {
              state._isInitialized = true;
            });
          }
        } catch (err) {
          console.error("Failed to load default background from store:", err);
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
          Object.assign(state, INITIAL_STATE);
          state._isInitialized = true;
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
export const useBlurAmount = () => useEditorStore((state) => state.settings.blurAmount);
export const useNoiseAmount = () => useEditorStore((state) => state.settings.noiseAmount);
export const useBorderRadius = () => useEditorStore((state) => state.settings.borderRadius);
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
  get setShadowBlur() { return useEditorStore.getState().setShadowBlur; },
  get setShadowBlurTransient() { return useEditorStore.getState().setShadowBlurTransient; },
  get setShadowOffsetX() { return useEditorStore.getState().setShadowOffsetX; },
  get setShadowOffsetXTransient() { return useEditorStore.getState().setShadowOffsetXTransient; },
  get setShadowOffsetY() { return useEditorStore.getState().setShadowOffsetY; },
  get setShadowOffsetYTransient() { return useEditorStore.getState().setShadowOffsetYTransient; },
  get setShadowOpacity() { return useEditorStore.getState().setShadowOpacity; },
  get setShadowOpacityTransient() { return useEditorStore.getState().setShadowOpacityTransient; },
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
