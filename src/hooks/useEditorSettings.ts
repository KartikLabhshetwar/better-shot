import { useState, useCallback, useMemo } from "react";
import { gradientOptions, type GradientOption } from "@/components/editor/BackgroundSelector";

// Import all background images
import bgImage13 from "@/assets/bg-images/asset-13.jpg";
import bgImage18 from "@/assets/bg-images/asset-18.jpg";
import bgImage19 from "@/assets/bg-images/asset-19.jpg";
import bgImage24 from "@/assets/bg-images/asset-24.avif";
import bgImage25 from "@/assets/bg-images/asset-25.jpg";
import bgImage26 from "@/assets/bg-images/asset-26.jpeg";
import bgImage27 from "@/assets/bg-images/asset-27.jpeg";
import bgImage28 from "@/assets/bg-images/asset-28.jpeg";
import bgImage29 from "@/assets/bg-images/asset-29.jpeg";
import bgImage30 from "@/assets/bg-images/asset-30.jpeg";

import macImage3 from "@/assets/mac/mac-asset-3.jpg";
import macImage5 from "@/assets/mac/mac-asset-5.jpg";
import macImage6 from "@/assets/mac/mac-asset-6.jpeg";
import macImage7 from "@/assets/mac/mac-asset-7.png";
import macImage8 from "@/assets/mac/mac-asset-8.jpg";
import macImage9 from "@/assets/mac/mac-asset-9.jpg";
import macImage10 from "@/assets/mac/mac-asset-10.jpg";

import type { AssetCategory } from "@/components/editor/AssetGrid";

export type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom" | "image";

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
}

export interface EditorSettingsActions {
  setBackgroundType: (type: BackgroundType) => void;
  setCustomColor: (color: string) => void;
  setSelectedImage: (src: string) => void;
  setGradient: (gradient: GradientOption) => void;
  setBlurAmount: (amount: number) => void;
  setNoiseAmount: (amount: number) => void;
  setBorderRadius: (radius: number) => void;
  handleImageSelect: (imageSrc: string) => void;
}

export const assetCategories: AssetCategory[] = [
  {
    name: "Wallpapers",
    assets: [
      { id: "bg-13", src: bgImage13, name: "Background 13" },
      { id: "bg-18", src: bgImage18, name: "Background 18" },
      { id: "bg-19", src: bgImage19, name: "Background 19" },
      { id: "bg-24", src: bgImage24, name: "Background 24" },
      { id: "bg-25", src: bgImage25, name: "Background 25" },
      { id: "bg-26", src: bgImage26, name: "Background 26" },
      { id: "bg-27", src: bgImage27, name: "Background 27" },
      { id: "bg-28", src: bgImage28, name: "Background 28" },
      { id: "bg-29", src: bgImage29, name: "Background 29" },
      { id: "bg-30", src: bgImage30, name: "Background 30" },
    ],
  },
  {
    name: "Mac Assets",
    assets: [
      { id: "mac-3", src: macImage3, name: "Mac 3" },
      { id: "mac-5", src: macImage5, name: "Mac 5" },
      { id: "mac-6", src: macImage6, name: "Mac 6" },
      { id: "mac-7", src: macImage7, name: "Mac 7" },
      { id: "mac-8", src: macImage8, name: "Mac 8" },
      { id: "mac-9", src: macImage9, name: "Mac 9" },
      { id: "mac-10", src: macImage10, name: "Mac 10" },
    ],
  },
];

const DEFAULT_GRADIENT = gradientOptions[0];
const DEFAULT_IMAGE = bgImage18;

export function useEditorSettings(): [EditorSettings, EditorSettingsActions] {
  // Background state
  const [backgroundType, setBackgroundType] = useState<BackgroundType>("image");
  const [customColor, setCustomColor] = useState("#667eea");
  const [selectedImageSrc, setSelectedImageSrc] = useState<string | null>(DEFAULT_IMAGE);
  
  // Store gradient as primitive values to avoid reference issues
  const [gradientId, setGradientId] = useState(DEFAULT_GRADIENT.id);
  const [gradientSrc, setGradientSrc] = useState(DEFAULT_GRADIENT.src);
  const [gradientColors, setGradientColors] = useState<[string, string]>(DEFAULT_GRADIENT.colors);
  
  // Effects state
  const [blurAmount, setBlurAmount] = useState(0);
  const [noiseAmount, setNoiseAmount] = useState(0);
  const [borderRadius, setBorderRadius] = useState(18);

  // Memoized settings object - only changes when actual values change
  const settings = useMemo<EditorSettings>(() => ({
    backgroundType,
    customColor,
    selectedImageSrc,
    gradientId,
    gradientSrc,
    gradientColors,
    blurAmount,
    noiseAmount,
    borderRadius,
  }), [
    backgroundType,
    customColor,
    selectedImageSrc,
    gradientId,
    gradientSrc,
    gradientColors,
    blurAmount,
    noiseAmount,
    borderRadius,
  ]);

  // Actions
  const setGradient = useCallback((gradient: GradientOption) => {
    setGradientId(gradient.id);
    setGradientSrc(gradient.src);
    setGradientColors(gradient.colors);
  }, []);

  const handleImageSelect = useCallback((imageSrc: string) => {
    setSelectedImageSrc(imageSrc);
    setBackgroundType("image");
  }, []);

  const setSelectedImage = useCallback((src: string) => {
    setSelectedImageSrc(src);
  }, []);

  const actions = useMemo<EditorSettingsActions>(() => ({
    setBackgroundType,
    setCustomColor,
    setSelectedImage,
    setGradient,
    setBlurAmount,
    setNoiseAmount,
    setBorderRadius,
    handleImageSelect,
  }), [setGradient, handleImageSelect, setSelectedImage]);

  return [settings, actions];
}
