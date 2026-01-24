import { useState, useCallback, useMemo, useEffect, useRef } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { gradientOptions, type GradientOption } from "@/components/editor/BackgroundSelector";
import { resolveBackgroundPath, getDefaultBackgroundPath } from "@/lib/asset-registry";
import { Annotation } from "@/types/annotations";

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

// Combined state for undo/redo
export interface EditorState {
  settings: EditorSettings;
  annotations: Annotation[];
}

export interface EditorStateResult {
  // Current state
  settings: EditorSettings;
  annotations: Annotation[];
  
  // History state
  canUndo: boolean;
  canRedo: boolean;
  
  // History actions
  undo: () => void;
  redo: () => void;
  
  // Settings actions
  setBackgroundType: (type: BackgroundType) => void;
  setCustomColor: (color: string) => void;
  setSelectedImage: (src: string) => void;
  setGradient: (gradient: GradientOption) => void;
  setBlurAmount: (amount: number) => void;
  setNoiseAmount: (amount: number) => void;
  setBorderRadius: (radius: number) => void;
  handleImageSelect: (imageSrc: string) => void;
  setShadowBlur: (blur: number) => void;
  setShadowOffsetX: (offsetX: number) => void;
  setShadowOffsetY: (offsetY: number) => void;
  setShadowOpacity: (opacity: number) => void;
  
  // Annotation actions
  addAnnotation: (annotation: Annotation) => void;
  updateAnnotation: (annotation: Annotation) => void;
  deleteAnnotation: (id: string) => void;
  setAnnotations: (annotations: Annotation[]) => void;
}

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
  noiseAmount: 0,
  borderRadius: 12,
  shadow: {
    blur: 33,
    offsetX: 18,
    offsetY: 23,
    opacity: 39,
  },
};

const DEFAULT_STATE: EditorState = {
  settings: DEFAULT_SETTINGS,
  annotations: [],
};

export function useEditorState(): EditorStateResult {
  const [state, setState] = useState<EditorState>(DEFAULT_STATE);
  const pastRef = useRef<EditorState[]>([]);
  const futureRef = useRef<EditorState[]>([]);
  const [, forceUpdate] = useState(0);
  
  // Load default background from store on mount
  useEffect(() => {
    const loadDefaultBackground = async () => {
      try {
        const store = await Store.load("settings.json");
        const storedBg = await store.get<string>("defaultBackgroundImage");
        if (storedBg) {
          const resolvedPath = resolveBackgroundPath(storedBg);
          setState(prev => ({
            ...prev,
            settings: {
              ...prev.settings,
              selectedImageSrc: resolvedPath,
            },
          }));
        }
      } catch (err) {
        console.error("Failed to load default background from store:", err);
      }
    };
    loadDefaultBackground();
  }, []);

  // Push current state to history and set new state
  const pushState = useCallback((newState: EditorState) => {
    setState(prev => {
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  // Update state with a partial settings update
  const updateSettings = useCallback((updates: Partial<EditorSettings>) => {
    setState(prev => {
      const newState = {
        ...prev,
        settings: { ...prev.settings, ...updates },
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  // Undo
  const undo = useCallback(() => {
    if (pastRef.current.length === 0) return;
    
    setState(prev => {
      const previous = pastRef.current[pastRef.current.length - 1];
      pastRef.current = pastRef.current.slice(0, -1);
      futureRef.current = [prev, ...futureRef.current].slice(0, MAX_HISTORY_SIZE);
      forceUpdate(n => n + 1);
      return previous;
    });
  }, []);

  // Redo
  const redo = useCallback(() => {
    if (futureRef.current.length === 0) return;
    
    setState(prev => {
      const next = futureRef.current[0];
      futureRef.current = futureRef.current.slice(1);
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      forceUpdate(n => n + 1);
      return next;
    });
  }, []);

  // Settings actions
  const setBackgroundType = useCallback((type: BackgroundType) => {
    updateSettings({ backgroundType: type });
  }, [updateSettings]);

  const setCustomColor = useCallback((color: string) => {
    updateSettings({ customColor: color });
  }, [updateSettings]);

  const setSelectedImage = useCallback((src: string) => {
    updateSettings({ selectedImageSrc: src });
  }, [updateSettings]);

  const setGradient = useCallback((gradient: GradientOption) => {
    updateSettings({
      gradientId: gradient.id,
      gradientSrc: gradient.src,
      gradientColors: gradient.colors,
    });
  }, [updateSettings]);

  const setBlurAmount = useCallback((amount: number) => {
    updateSettings({ blurAmount: amount });
  }, [updateSettings]);

  const setNoiseAmount = useCallback((amount: number) => {
    updateSettings({ noiseAmount: amount });
  }, [updateSettings]);

  const setBorderRadius = useCallback((radius: number) => {
    updateSettings({ borderRadius: radius });
  }, [updateSettings]);

  const handleImageSelect = useCallback((imageSrc: string) => {
    updateSettings({ selectedImageSrc: imageSrc, backgroundType: "image" });
  }, [updateSettings]);

  const setShadowBlur = useCallback((blur: number) => {
    setState(prev => {
      const newState = {
        ...prev,
        settings: {
          ...prev.settings,
          shadow: { ...prev.settings.shadow, blur },
        },
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  const setShadowOffsetX = useCallback((offsetX: number) => {
    setState(prev => {
      const newState = {
        ...prev,
        settings: {
          ...prev.settings,
          shadow: { ...prev.settings.shadow, offsetX },
        },
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  const setShadowOffsetY = useCallback((offsetY: number) => {
    setState(prev => {
      const newState = {
        ...prev,
        settings: {
          ...prev.settings,
          shadow: { ...prev.settings.shadow, offsetY },
        },
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  const setShadowOpacity = useCallback((opacity: number) => {
    setState(prev => {
      const newState = {
        ...prev,
        settings: {
          ...prev.settings,
          shadow: { ...prev.settings.shadow, opacity },
        },
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  // Annotation actions
  const addAnnotation = useCallback((annotation: Annotation) => {
    setState(prev => {
      const newState = {
        ...prev,
        annotations: [...prev.annotations, annotation],
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  const updateAnnotation = useCallback((annotation: Annotation) => {
    setState(prev => {
      const newState = {
        ...prev,
        annotations: prev.annotations.map(ann => 
          ann.id === annotation.id ? annotation : ann
        ),
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  const deleteAnnotation = useCallback((id: string) => {
    setState(prev => {
      const newState = {
        ...prev,
        annotations: prev.annotations.filter(ann => ann.id !== id),
      };
      pastRef.current = [...pastRef.current, prev].slice(-MAX_HISTORY_SIZE);
      futureRef.current = [];
      forceUpdate(n => n + 1);
      return newState;
    });
  }, []);

  const setAnnotations = useCallback((annotations: Annotation[]) => {
    pushState({ ...state, annotations });
  }, [pushState, state]);

  return useMemo(() => ({
    settings: state.settings,
    annotations: state.annotations,
    canUndo: pastRef.current.length > 0,
    canRedo: futureRef.current.length > 0,
    undo,
    redo,
    setBackgroundType,
    setCustomColor,
    setSelectedImage,
    setGradient,
    setBlurAmount,
    setNoiseAmount,
    setBorderRadius,
    handleImageSelect,
    setShadowBlur,
    setShadowOffsetX,
    setShadowOffsetY,
    setShadowOpacity,
    addAnnotation,
    updateAnnotation,
    deleteAnnotation,
    setAnnotations,
  }), [
    state.settings,
    state.annotations,
    undo,
    redo,
    setBackgroundType,
    setCustomColor,
    setSelectedImage,
    setGradient,
    setBlurAmount,
    setNoiseAmount,
    setBorderRadius,
    handleImageSelect,
    setShadowBlur,
    setShadowOffsetX,
    setShadowOffsetY,
    setShadowOpacity,
    addAnnotation,
    updateAnnotation,
    deleteAnnotation,
    setAnnotations,
  ]);
}
