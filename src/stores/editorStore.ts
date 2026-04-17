import { create } from "zustand";
import { subscribeWithSelector } from "zustand/middleware";
import { immer } from "zustand/middleware/immer";
import { Store } from "@tauri-apps/plugin-store";
import { gradientOptions, type GradientOption } from "@/components/editor/BackgroundSelector";
import { resolveBackgroundPath, getDefaultBackgroundPath, toStorableValue } from "@/lib/asset-registry";
import { Annotation } from "@/types/annotations";
import type { FrameType } from "@/lib/frame-utils";

// ============================================================================
// Types
// ============================================================================

export type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom" | "image";
export type ImageScalingMode = "none" | "fit" | "fit-with-border" | "cover" | "contain";
export type { FrameType };

export interface BackgroundFillSettings {
  backgroundType: BackgroundType;
  customColor: string;
  selectedImageSrc: string | null;
  gradientId: string;
  gradientSrc: string;
  gradientColors: [string, string];
}

export interface ShadowSettings {
  blur: number;
  offsetX: number;
  offsetY: number;
  opacity: number;
}

export interface CanvasDimensions {
  width: number;
  height: number;
  aspectRatioLocked: boolean;
}

export interface ImageOffset {
  x: number;
  y: number;
}

export interface EditorSettings {
  backgroundType: BackgroundType;
  customColor: string;
  selectedImageSrc: string | null;
  gradientId: string;
  gradientSrc: string;
  gradientColors: [string, string];
  macbookUseOuterBackground: boolean;
  macbookBackground: BackgroundFillSettings;
  macbookScreenshotPadding: number;
  noiseAmount: number;
  borderRadius: number;
  padding: number;
  shadow: ShadowSettings;
  canvasDimensions: CanvasDimensions;
  imageOffset: ImageOffset;
  imageScalingMode: ImageScalingMode;
  imageBorderSize: number;
  frameType: FrameType;
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
  setMacbookUseOuterBackground: (useOuterBackground: boolean) => void;
  setMacbookBackgroundType: (type: BackgroundType) => void;
  setMacbookCustomColor: (color: string) => void;
  setMacbookSelectedImage: (src: string) => void;
  setMacbookGradient: (gradient: GradientOption) => void;
  handleMacbookImageSelect: (imageSrc: string) => void;
  setMacbookScreenshotPaddingTransient: (padding: number) => void;
  setMacbookScreenshotPadding: (padding: number) => void;
  
  // Transient settings (during slider drag)
  setNoiseAmountTransient: (amount: number) => void;
  setBorderRadiusTransient: (radius: number) => void;
  setPaddingTransient: (padding: number) => void;
  setShadowBlurTransient: (blur: number) => void;
  setShadowOffsetXTransient: (offsetX: number) => void;
  setShadowOffsetYTransient: (offsetY: number) => void;
  setShadowOpacityTransient: (opacity: number) => void;
  
  // Commit settings (on slider release)
  setNoiseAmount: (amount: number) => void;
  setBorderRadius: (radius: number) => void;
  setPadding: (padding: number) => void;
  setShadowBlur: (blur: number) => void;
  setShadowOffsetX: (offsetX: number) => void;
  setShadowOffsetY: (offsetY: number) => void;
  setShadowOpacity: (opacity: number) => void;

  // Canvas dimensions - transient (during input)
  setCanvasWidthTransient: (width: number) => void;
  setCanvasHeightTransient: (height: number) => void;
  setAspectRatioLockedTransient: (locked: boolean) => void;

  // Canvas dimensions - commit (on release)
  setCanvasWidth: (width: number) => void;
  setCanvasHeight: (height: number) => void;
  setAspectRatioLocked: (locked: boolean) => void;
  setCanvasDimensions: (dimensions: Partial<CanvasDimensions>) => void;

  // Image offset - transient (during drag)
  setImageOffsetXTransient: (offsetX: number) => void;
  setImageOffsetYTransient: (offsetY: number) => void;

  // Image offset - commit (on release)
  setImageOffsetX: (offsetX: number) => void;
  setImageOffsetY: (offsetY: number) => void;
  setImageOffset: (offset: ImageOffset) => void;

  // Image scaling - commit (on release)
  setImageScalingMode: (mode: ImageScalingMode) => void;
  setImageBorderSize: (size: number) => void;

  // Frame
  setFrameType: (frameType: FrameType) => void;

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
const DEFAULT_BACKGROUND_FILL: BackgroundFillSettings = {
  backgroundType: "image",
  customColor: "#667eea",
  selectedImageSrc: DEFAULT_IMAGE,
  gradientId: DEFAULT_GRADIENT.id,
  gradientSrc: DEFAULT_GRADIENT.src,
  gradientColors: DEFAULT_GRADIENT.colors,
};

const DEFAULT_SETTINGS: EditorSettings = {
  ...DEFAULT_BACKGROUND_FILL,
  macbookUseOuterBackground: true,
  macbookBackground: structuredClone(DEFAULT_BACKGROUND_FILL),
  macbookScreenshotPadding: 0,
  noiseAmount: 20,
  borderRadius: 18,
  padding: 100,
  shadow: {
    blur: 33,
    offsetX: 18,
    offsetY: 23,
    opacity: 39,
  },
  canvasDimensions: {
    width: 0,
    height: 0,
    aspectRatioLocked: true,
  },
  imageOffset: {
    x: 0,
    y: 0,
  },
  imageScalingMode: "none",
  imageBorderSize: 0,
  frameType: "none",
};

const INITIAL_STATE: EditorState = {
  settings: DEFAULT_SETTINGS,
  annotations: [],
  past: [],
  future: [],
  _isInitialized: false,
  _historyPaused: false,
};

const SETTINGS_STORE_NAME = "settings.json";
const PERSISTED_SETTINGS_KEY = "lastEditorSettings";

type PersistedEditorSettings = {
  backgroundType?: BackgroundType;
  customColor?: string;
  selectedImage?: string | null;
  gradientId?: string;
  macbookUseOuterBackground?: boolean;
  macbookScreenshotPadding?: number;
  macbookBackground?: {
    backgroundType?: BackgroundType;
    customColor?: string;
    selectedImage?: string | null;
    gradientId?: string;
  };
  noiseAmount?: number;
  borderRadius?: number;
  padding?: number;
  shadow?: Partial<ShadowSettings>;
  canvasDimensions?: Partial<CanvasDimensions>;
  imageOffset?: Partial<ImageOffset>;
  imageScalingMode?: ImageScalingMode;
  imageBorderSize?: number;
  frameType?: FrameType;
};

function buildSettingsFromPersisted(stored: PersistedEditorSettings): EditorSettings {
  const gradientOption = gradientOptions.find((option) => option.id === stored.gradientId) ?? DEFAULT_GRADIENT;
  const macbookGradientOption =
    gradientOptions.find((option) => option.id === stored.macbookBackground?.gradientId) ?? DEFAULT_GRADIENT;
  return {
    backgroundType: stored.backgroundType ?? DEFAULT_SETTINGS.backgroundType,
    customColor: stored.customColor ?? DEFAULT_SETTINGS.customColor,
    selectedImageSrc: resolveBackgroundPath(stored.selectedImage ?? null),
    gradientId: gradientOption.id,
    gradientSrc: gradientOption.src,
    gradientColors: gradientOption.colors,
    macbookUseOuterBackground: stored.macbookUseOuterBackground ?? DEFAULT_SETTINGS.macbookUseOuterBackground,
    macbookScreenshotPadding: stored.macbookScreenshotPadding ?? DEFAULT_SETTINGS.macbookScreenshotPadding,
    macbookBackground: {
      backgroundType: stored.macbookBackground?.backgroundType ?? DEFAULT_SETTINGS.macbookBackground.backgroundType,
      customColor: stored.macbookBackground?.customColor ?? DEFAULT_SETTINGS.macbookBackground.customColor,
      selectedImageSrc: resolveBackgroundPath(stored.macbookBackground?.selectedImage ?? null),
      gradientId: macbookGradientOption.id,
      gradientSrc: macbookGradientOption.src,
      gradientColors: macbookGradientOption.colors,
    },
    noiseAmount: stored.noiseAmount ?? DEFAULT_SETTINGS.noiseAmount,
    borderRadius: stored.borderRadius ?? DEFAULT_SETTINGS.borderRadius,
    padding: stored.padding ?? DEFAULT_SETTINGS.padding,
    shadow: {
      blur: stored.shadow?.blur ?? DEFAULT_SETTINGS.shadow.blur,
      offsetX: stored.shadow?.offsetX ?? DEFAULT_SETTINGS.shadow.offsetX,
      offsetY: stored.shadow?.offsetY ?? DEFAULT_SETTINGS.shadow.offsetY,
      opacity: stored.shadow?.opacity ?? DEFAULT_SETTINGS.shadow.opacity,
    },
    canvasDimensions: {
      width: stored.canvasDimensions?.width ?? DEFAULT_SETTINGS.canvasDimensions.width,
      height: stored.canvasDimensions?.height ?? DEFAULT_SETTINGS.canvasDimensions.height,
      aspectRatioLocked: stored.canvasDimensions?.aspectRatioLocked ?? DEFAULT_SETTINGS.canvasDimensions.aspectRatioLocked,
    },
    imageOffset: {
      x: stored.imageOffset?.x ?? DEFAULT_SETTINGS.imageOffset.x,
      y: stored.imageOffset?.y ?? DEFAULT_SETTINGS.imageOffset.y,
    },
    imageScalingMode: stored.imageScalingMode ?? DEFAULT_SETTINGS.imageScalingMode,
    imageBorderSize: stored.imageBorderSize ?? DEFAULT_SETTINGS.imageBorderSize,
    frameType: stored.frameType ?? DEFAULT_SETTINGS.frameType,
  };
}

async function persistEditorSettings(settings: EditorSettings) {
  try {
    const store = await Store.load(SETTINGS_STORE_NAME);
    const storableImage = settings.selectedImageSrc ? toStorableValue(settings.selectedImageSrc) : null;
    const storableMacbookImage = settings.macbookBackground.selectedImageSrc
      ? toStorableValue(settings.macbookBackground.selectedImageSrc)
      : null;
    await store.set(PERSISTED_SETTINGS_KEY, {
      backgroundType: settings.backgroundType,
      customColor: settings.customColor,
      selectedImage: storableImage,
      gradientId: settings.gradientId,
      macbookUseOuterBackground: settings.macbookUseOuterBackground,
      macbookScreenshotPadding: settings.macbookScreenshotPadding,
      macbookBackground: {
        backgroundType: settings.macbookBackground.backgroundType,
        customColor: settings.macbookBackground.customColor,
        selectedImage: storableMacbookImage,
        gradientId: settings.macbookBackground.gradientId,
      },
      noiseAmount: settings.noiseAmount,
      borderRadius: settings.borderRadius,
      padding: settings.padding,
      shadow: {
        blur: settings.shadow.blur,
        offsetX: settings.shadow.offsetX,
        offsetY: settings.shadow.offsetY,
        opacity: settings.shadow.opacity,
      },
      canvasDimensions: {
        width: settings.canvasDimensions.width,
        height: settings.canvasDimensions.height,
        aspectRatioLocked: settings.canvasDimensions.aspectRatioLocked,
      },
      imageOffset: {
        x: settings.imageOffset.x,
        y: settings.imageOffset.y,
      },
      imageScalingMode: settings.imageScalingMode,
      imageBorderSize: settings.imageBorderSize,
      frameType: settings.frameType,
    });
    await store.save();
  } catch (err) {
    console.error("Failed to persist editor settings:", err);
  }
}

export async function clearPersistedEditorSettings(): Promise<boolean> {
  try {
    const store = await Store.load(SETTINGS_STORE_NAME);
    await store.delete(PERSISTED_SETTINGS_KEY);
    await store.save();
    return true;
  } catch (err) {
    console.error("Failed to clear persisted editor settings:", err);
    return false;
  }
}

// ============================================================================
// Store
// ============================================================================

export const useEditorStore = create<EditorStore>()(
  subscribeWithSelector(
    immer((set, get) => {
      const persistIfReady = () => {
        if (!get()._isInitialized) return;
        persistEditorSettings(get().settings);
      };

      return {
        ...INITIAL_STATE,

        // ========================================
        // Initialization
        // ========================================
        initialize: async () => {
        if (get()._isInitialized) return;

        try {
          const store = await Store.load(SETTINGS_STORE_NAME);
          const storedSettings = await store.get<PersistedEditorSettings>(PERSISTED_SETTINGS_KEY);

          if (storedSettings) {
            set((state) => {
              state.settings = buildSettingsFromPersisted(storedSettings);
              state._isInitialized = true;
            });
            return;
          }

          const storedBgType = await store.get<BackgroundType>("defaultBackgroundType");
          const storedCustomColor = await store.get<string>("defaultCustomColor");
          const storedBg = await store.get<string>("defaultBackgroundImage");

          set((state) => {
            if (storedBgType) {
              state.settings.backgroundType = storedBgType;
            }
            if (storedCustomColor) {
              state.settings.customColor = storedCustomColor;
            }
            if (storedBg && storedBgType === "image") {
              const resolvedPath = resolveBackgroundPath(storedBg);
              state.settings.selectedImageSrc = resolvedPath;
            }
            state._isInitialized = true;
          });
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
        persistIfReady();
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

      setMacbookUseOuterBackground: (useOuterBackground) => {
        get().updateSettings({ macbookUseOuterBackground: useOuterBackground });
      },

      setMacbookBackgroundType: (type) => {
        get().updateSettings({
          macbookBackground: {
            ...get().settings.macbookBackground,
            backgroundType: type,
          },
        });
      },

      setMacbookCustomColor: (color) => {
        get().updateSettings({
          macbookBackground: {
            ...get().settings.macbookBackground,
            customColor: color,
          },
        });
      },

      setMacbookSelectedImage: (src) => {
        get().updateSettings({
          macbookBackground: {
            ...get().settings.macbookBackground,
            selectedImageSrc: src,
          },
        });
      },

      setMacbookGradient: (gradient) => {
        get().updateSettings({
          macbookBackground: {
            ...get().settings.macbookBackground,
            gradientId: gradient.id,
            gradientSrc: gradient.src,
            gradientColors: gradient.colors,
          },
        });
      },

      handleMacbookImageSelect: (imageSrc) => {
        get().updateSettings({
          macbookBackground: {
            ...get().settings.macbookBackground,
            selectedImageSrc: imageSrc,
            backgroundType: "image",
          },
        });
      },

      setMacbookScreenshotPaddingTransient: (padding) => {
        set((state) => {
          state.settings.macbookScreenshotPadding = padding;
        });
      },

      setMacbookScreenshotPadding: (padding) => {
        get().updateSettings({ macbookScreenshotPadding: padding });
      },

      // ========================================
      // Slider Settings - Transient (during drag)
      // ========================================
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

      setPaddingTransient: (padding) => {
        set((state) => {
          state.settings.padding = padding;
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

      setCanvasWidthTransient: (width) => {
        set((state) => {
          const dims = state.settings.canvasDimensions;
          const oldWidth = dims.width;
          dims.width = width;
          if (dims.aspectRatioLocked && width > 0 && oldWidth > 0) {
            const ratio = dims.height / oldWidth;
            dims.height = Math.round(width * ratio);
          }
        });
      },

      setCanvasHeightTransient: (height) => {
        set((state) => {
          const dims = state.settings.canvasDimensions;
          const oldHeight = dims.height;
          dims.height = height;
          if (dims.aspectRatioLocked && height > 0 && oldHeight > 0) {
            const ratio = dims.width / oldHeight;
            dims.width = Math.round(height * ratio);
          }
        });
      },

      setAspectRatioLockedTransient: (locked) => {
        set((state) => {
          state.settings.canvasDimensions.aspectRatioLocked = locked;
        });
      },

      setImageOffsetXTransient: (offsetX) => {
        set((state) => {
          state.settings.imageOffset.x = offsetX;
        });
      },

      setImageOffsetYTransient: (offsetY) => {
        set((state) => {
          state.settings.imageOffset.y = offsetY;
        });
      },

      // ========================================
      // Slider Settings - Commit (on release)
      // ========================================
      setNoiseAmount: (amount) => {
        get().updateSettings({ noiseAmount: amount });
      },

      setBorderRadius: (radius) => {
        get().updateSettings({ borderRadius: radius });
      },

      setPadding: (padding) => {
        get().updateSettings({ padding });
      },

      setShadowBlur: (blur) => {
        get().pushHistory();
        set((s) => {
          s.settings.shadow.blur = blur;
          s.future = [];
        });
        persistIfReady();
      },

      setShadowOffsetX: (offsetX) => {
        get().pushHistory();
        set((state) => {
          state.settings.shadow.offsetX = offsetX;
          state.future = [];
        });
        persistIfReady();
      },

      setShadowOffsetY: (offsetY) => {
        get().pushHistory();
        set((state) => {
          state.settings.shadow.offsetY = offsetY;
          state.future = [];
        });
        persistIfReady();
      },

      setShadowOpacity: (opacity) => {
        get().pushHistory();
        set((state) => {
          state.settings.shadow.opacity = opacity;
          state.future = [];
        });
        persistIfReady();
      },

      setCanvasWidth: (width) => {
        const currentDims = get().settings.canvasDimensions;
        const newDims = { ...currentDims, width };
        if (currentDims.aspectRatioLocked && width > 0 && currentDims.width > 0) {
          const ratio = currentDims.height / currentDims.width;
          newDims.height = Math.round(width * ratio);
        }
        get().updateSettings({ canvasDimensions: newDims });
      },

      setCanvasHeight: (height) => {
        const currentDims = get().settings.canvasDimensions;
        const newDims = { ...currentDims, height };
        if (currentDims.aspectRatioLocked && height > 0 && currentDims.height > 0) {
          const ratio = currentDims.width / currentDims.height;
          newDims.width = Math.round(height * ratio);
        }
        get().updateSettings({ canvasDimensions: newDims });
      },

      setAspectRatioLocked: (locked) => {
        get().updateSettings({
          canvasDimensions: {
            ...get().settings.canvasDimensions,
            aspectRatioLocked: locked,
          },
        });
      },

      setCanvasDimensions: (dimensions) => {
        get().updateSettings({
          canvasDimensions: {
            ...get().settings.canvasDimensions,
            ...dimensions,
          },
        });
      },

      setImageOffsetX: (offsetX) => {
        get().updateSettings({
          imageOffset: {
            ...get().settings.imageOffset,
            x: offsetX,
          },
        });
      },

      setImageOffsetY: (offsetY) => {
        get().updateSettings({
          imageOffset: {
            ...get().settings.imageOffset,
            y: offsetY,
          },
        });
      },

      setImageOffset: (offset) => {
        get().updateSettings({ imageOffset: offset });
      },

      setImageScalingMode: (mode) => {
        get().updateSettings({ imageScalingMode: mode });
      },

      setImageBorderSize: (size) => {
        get().updateSettings({ imageBorderSize: size });
      },

      setFrameType: (frameType) => {
        get().updateSettings({ frameType });
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
          state._isInitialized = false;
        });
      },
    };
  })
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
export const useCanvasDimensions = () => useEditorStore((state) => state.settings.canvasDimensions);
export const useImageOffset = () => useEditorStore((state) => state.settings.imageOffset);

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
  get setMacbookUseOuterBackground() { return useEditorStore.getState().setMacbookUseOuterBackground; },
  get setMacbookBackgroundType() { return useEditorStore.getState().setMacbookBackgroundType; },
  get setMacbookCustomColor() { return useEditorStore.getState().setMacbookCustomColor; },
  get setMacbookSelectedImage() { return useEditorStore.getState().setMacbookSelectedImage; },
  get setMacbookGradient() { return useEditorStore.getState().setMacbookGradient; },
  get handleMacbookImageSelect() { return useEditorStore.getState().handleMacbookImageSelect; },
  get setMacbookScreenshotPadding() { return useEditorStore.getState().setMacbookScreenshotPadding; },
  get setMacbookScreenshotPaddingTransient() { return useEditorStore.getState().setMacbookScreenshotPaddingTransient; },
  get setNoiseAmount() { return useEditorStore.getState().setNoiseAmount; },
  get setNoiseAmountTransient() { return useEditorStore.getState().setNoiseAmountTransient; },
  get setBorderRadius() { return useEditorStore.getState().setBorderRadius; },
  get setBorderRadiusTransient() { return useEditorStore.getState().setBorderRadiusTransient; },
  get setPadding() { return useEditorStore.getState().setPadding; },
  get setPaddingTransient() { return useEditorStore.getState().setPaddingTransient; },
  get setShadowBlur() { return useEditorStore.getState().setShadowBlur; },
  get setShadowBlurTransient() { return useEditorStore.getState().setShadowBlurTransient; },
  get setShadowOffsetX() { return useEditorStore.getState().setShadowOffsetX; },
  get setShadowOffsetXTransient() { return useEditorStore.getState().setShadowOffsetXTransient; },
  get setShadowOffsetY() { return useEditorStore.getState().setShadowOffsetY; },
  get setShadowOffsetYTransient() { return useEditorStore.getState().setShadowOffsetYTransient; },
  get setShadowOpacity() { return useEditorStore.getState().setShadowOpacity; },
  get setShadowOpacityTransient() { return useEditorStore.getState().setShadowOpacityTransient; },
  get setCanvasWidth() { return useEditorStore.getState().setCanvasWidth; },
  get setCanvasWidthTransient() { return useEditorStore.getState().setCanvasWidthTransient; },
  get setCanvasHeight() { return useEditorStore.getState().setCanvasHeight; },
  get setCanvasHeightTransient() { return useEditorStore.getState().setCanvasHeightTransient; },
  get setAspectRatioLocked() { return useEditorStore.getState().setAspectRatioLocked; },
  get setAspectRatioLockedTransient() { return useEditorStore.getState().setAspectRatioLockedTransient; },
  get setCanvasDimensions() { return useEditorStore.getState().setCanvasDimensions; },
  get setImageOffsetX() { return useEditorStore.getState().setImageOffsetX; },
  get setImageOffsetXTransient() { return useEditorStore.getState().setImageOffsetXTransient; },
  get setImageOffsetY() { return useEditorStore.getState().setImageOffsetY; },
  get setImageOffsetYTransient() { return useEditorStore.getState().setImageOffsetYTransient; },
  get setImageOffset() { return useEditorStore.getState().setImageOffset; },
  get setImageScalingMode() { return useEditorStore.getState().setImageScalingMode; },
  get setImageBorderSize() { return useEditorStore.getState().setImageBorderSize; },
  get setFrameType() { return useEditorStore.getState().setFrameType; },
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
