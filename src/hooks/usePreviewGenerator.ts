import { useRef, useEffect, useCallback, useState, useMemo } from "react";
import { EditorSettings } from "@/stores/editorStore";
import { createHighQualityCanvas } from "@/lib/canvas-utils";
import { drawAnnotationOnCanvas } from "@/lib/annotation-utils";
import { Annotation } from "@/types/annotations";

// Image cache with LRU-like cleanup (max 20 images)
const MAX_CACHE_SIZE = 20;
const imageCache = new Map<string, HTMLImageElement>();
const cacheOrder: string[] = [];

function addToCache(src: string, img: HTMLImageElement) {
  if (imageCache.size >= MAX_CACHE_SIZE) {
    const oldest = cacheOrder.shift();
    if (oldest) {
      imageCache.delete(oldest);
    }
  }
  imageCache.set(src, img);
  cacheOrder.push(src);
}

/**
 * Load an image from a URL, using cache if available
 */
export async function loadImage(src: string): Promise<HTMLImageElement> {
  if (imageCache.has(src)) {
    return imageCache.get(src)!;
  }

  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      addToCache(src, img);
      resolve(img);
    };
    img.onerror = (event) => {
      const error = new Error(
        `Failed to load image: ${src}. This may be due to CORS restrictions, ` +
        `invalid path, or asset protocol scope issues in production builds.`
      );
      console.error("Image load error:", { src, event });
      reject(error);
    };
    img.src = src;
  });
}

/**
 * Get the background image source based on settings
 */
function getBackgroundImageSrc(settings: EditorSettings): string | null {
  if (settings.backgroundType === "image" && settings.selectedImageSrc) {
    return settings.selectedImageSrc;
  }
  if (settings.backgroundType === "gradient" && settings.gradientSrc) {
    return settings.gradientSrc;
  }
  return null;
}

/**
 * Draw background on a canvas context
 */
function drawBackground(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  settings: EditorSettings,
  bgImage: HTMLImageElement | null
) {
  switch (settings.backgroundType) {
    case "transparent": {
      break;
    }
    case "white":
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, width, height);
      break;
    case "black":
      ctx.fillStyle = "#000000";
      ctx.fillRect(0, 0, width, height);
      break;
    case "gray":
      ctx.fillStyle = "#f5f5f5";
      ctx.fillRect(0, 0, width, height);
      break;
    case "gradient":
      if (bgImage) {
        ctx.drawImage(bgImage, 0, 0, width, height);
      } else {
        const gradient = ctx.createLinearGradient(0, 0, width, height);
        gradient.addColorStop(0, settings.gradientColors[0]);
        gradient.addColorStop(1, settings.gradientColors[1]);
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, width, height);
      }
      break;
    case "custom":
      ctx.fillStyle = settings.customColor;
      ctx.fillRect(0, 0, width, height);
      break;
    case "image":
      if (bgImage) {
        ctx.drawImage(bgImage, 0, 0, width, height);
      } else {
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(0, 0, width, height);
      }
      break;
  }
}


/**
 * Apply noise effect to a canvas (modifies in place)
 * Optimized with typed arrays
 */
function applyNoise(canvas: HTMLCanvasElement, noiseAmount: number) {
  if (noiseAmount <= 0) return;

  const ctx = canvas.getContext("2d")!;
  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const data = imageData.data;
  const noiseIntensity = noiseAmount * 2.55;
  const len = data.length;

  // Optimize loop - process 4 pixels at a time when possible
  for (let i = 0; i < len; i += 4) {
    const noise = (Math.random() - 0.5) * noiseIntensity;
    data[i] = Math.max(0, Math.min(255, data[i] + noise));
    data[i + 1] = Math.max(0, Math.min(255, data[i + 1] + noise));
    data[i + 2] = Math.max(0, Math.min(255, data[i + 2] + noise));
  }

  ctx.putImageData(imageData, 0, 0);
}

export interface PreviewGeneratorOptions {
  screenshotImage: HTMLImageElement | null;
  settings: EditorSettings;
  canvasRef: React.RefObject<HTMLCanvasElement | null>;
  padding?: number;
}

export interface PreviewGeneratorResult {
  previewUrl: string | null;
  isGenerating: boolean;
  error: string | null;
  renderHighQualityCanvas: (annotations: Annotation[]) => Promise<HTMLCanvasElement | null>;
}

// Debounce delay for preview generation
const PREVIEW_DEBOUNCE_MS = 50;

/**
 * Hook for generating preview images based on editor settings
 * Optimized with debouncing to prevent lag during slider interaction
 */
export function usePreviewGenerator({
  screenshotImage,
  settings,
  canvasRef,
  padding = 100,
}: PreviewGeneratorOptions): PreviewGeneratorResult {
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const previewUrlRef = useRef<string | null>(null);
  const renderIdRef = useRef(0);
  const debounceTimerRef = useRef<NodeJS.Timeout | null>(null);
  const pendingSettingsRef = useRef<EditorSettings | null>(null);

  // Memoize background-related settings for comparison
  const bgSettingsKey = useMemo(() => {
    return JSON.stringify({
      backgroundType: settings.backgroundType,
      selectedImageSrc: settings.selectedImageSrc,
      gradientId: settings.gradientId,
      gradientSrc: settings.gradientSrc,
      customColor: settings.customColor,
    });
  }, [
    settings.backgroundType,
    settings.selectedImageSrc,
    settings.gradientId,
    settings.gradientSrc,
    settings.customColor,
  ]);

  // Core render function
  const generatePreview = useCallback(async (settingsToRender: EditorSettings) => {
    if (!screenshotImage || !canvasRef.current) return;

    const currentRenderId = ++renderIdRef.current;
    const canvas = canvasRef.current;

    const bgWidth = screenshotImage.width + padding * 2;
    const bgHeight = screenshotImage.height + padding * 2;

    setIsGenerating(true);
    setError(null);

    try {
      const bgSrc = getBackgroundImageSrc(settingsToRender);
      let bgImage: HTMLImageElement | null = null;
      if (bgSrc) {
        bgImage = await loadImage(bgSrc);
      }

      if (currentRenderId !== renderIdRef.current) return;

      canvas.width = bgWidth;
      canvas.height = bgHeight;
      const ctx = canvas.getContext("2d", { alpha: true });
      if (!ctx) {
        setError("Failed to get canvas context");
        return;
      }

      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = "high";

      // When padding is 0, skip background and shadow - just draw the image directly
      if (padding === 0) {
        ctx.beginPath();
        ctx.roundRect(0, 0, screenshotImage.width, screenshotImage.height, settingsToRender.borderRadius);
        ctx.closePath();
        ctx.clip();
        ctx.drawImage(screenshotImage, 0, 0, screenshotImage.width, screenshotImage.height);
      } else {
        const tempCanvas = document.createElement("canvas");
        tempCanvas.width = bgWidth;
        tempCanvas.height = bgHeight;
        const tempCtx = tempCanvas.getContext("2d")!;
        drawBackground(tempCtx, bgWidth, bgHeight, settingsToRender, bgImage);
        applyNoise(tempCanvas, settingsToRender.noiseAmount);

        ctx.drawImage(tempCanvas, 0, 0);

        const imageCanvas = document.createElement("canvas");
        imageCanvas.width = screenshotImage.width;
        imageCanvas.height = screenshotImage.height;
        const imageCtx = imageCanvas.getContext("2d");
        if (!imageCtx) {
          setError("Failed to get image canvas context");
          return;
        }

        imageCtx.imageSmoothingEnabled = true;
        imageCtx.imageSmoothingQuality = "high";

        imageCtx.beginPath();
        imageCtx.roundRect(0, 0, screenshotImage.width, screenshotImage.height, settingsToRender.borderRadius);
        imageCtx.closePath();
        imageCtx.clip();

        imageCtx.drawImage(screenshotImage, 0, 0, screenshotImage.width, screenshotImage.height);

        ctx.save();
        ctx.shadowColor = `rgba(0, 0, 0, ${settingsToRender.shadow.opacity / 100})`;
        ctx.shadowBlur = settingsToRender.shadow.blur;
        ctx.shadowOffsetX = settingsToRender.shadow.offsetX;
        ctx.shadowOffsetY = settingsToRender.shadow.offsetY;

        ctx.drawImage(imageCanvas, padding, padding);

        ctx.shadowColor = "transparent";
        ctx.shadowBlur = 0;
        ctx.shadowOffsetX = 0;
        ctx.shadowOffsetY = 0;
        ctx.restore();
      }

      if (currentRenderId !== renderIdRef.current) return;

      canvas.toBlob((blob) => {
        if (blob && currentRenderId === renderIdRef.current) {
          if (previewUrlRef.current) {
            URL.revokeObjectURL(previewUrlRef.current);
          }
          const url = URL.createObjectURL(blob);
          previewUrlRef.current = url;
          setPreviewUrl(url);
          setIsGenerating(false);
        }
      }, "image/png");
    } catch (err) {
      if (currentRenderId === renderIdRef.current) {
        const message = err instanceof Error ? err.message : String(err);
        setError(`Preview generation failed: ${message}`);
        setIsGenerating(false);
        console.error("Preview generation failed:", err);
      }
    }
  }, [screenshotImage, canvasRef, padding]);

  // Debounced preview generation
  useEffect(() => {
    if (!screenshotImage || !canvasRef.current) return;

    // Cancel any pending debounce
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
    }

    // Store pending settings
    pendingSettingsRef.current = settings;

    // Debounce the actual render
    debounceTimerRef.current = setTimeout(() => {
      if (pendingSettingsRef.current) {
        generatePreview(pendingSettingsRef.current);
      }
    }, PREVIEW_DEBOUNCE_MS);

    return () => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
    };
  }, [
    screenshotImage,
    bgSettingsKey,
    settings.noiseAmount,
    settings.borderRadius,
    settings.shadow.blur,
    settings.shadow.offsetX,
    settings.shadow.offsetY,
    settings.shadow.opacity,
    padding,
    canvasRef,
    generatePreview,
  ]);

  // Cleanup preview URL on unmount
  useEffect(() => {
    return () => {
      if (previewUrlRef.current) {
        URL.revokeObjectURL(previewUrlRef.current);
      }
    };
  }, []);

  // High quality canvas render for save/copy
  const renderHighQualityCanvas = useCallback(
    async (annotations: Annotation[]): Promise<HTMLCanvasElement | null> => {
      if (!screenshotImage) return null;

      try {
        const bgSrc = getBackgroundImageSrc(settings);
        let bgImage: HTMLImageElement | null = null;
        if (bgSrc) {
          bgImage = await loadImage(bgSrc);
        }

        const canvas = createHighQualityCanvas({
          image: screenshotImage,
          backgroundType: settings.backgroundType,
          customColor: settings.customColor,
          selectedImage: settings.selectedImageSrc,
          bgImage,
          blurAmount: 0,
          noiseAmount: settings.noiseAmount,
          borderRadius: settings.borderRadius,
          padding,
          gradientImage: settings.backgroundType === "gradient" ? bgImage : null,
          shadow: settings.shadow,
        });

        if (annotations.length > 0) {
          const ctx = canvas.getContext("2d");
          if (ctx) {
            annotations.forEach((annotation) => {
              drawAnnotationOnCanvas(ctx, annotation);
            });
          }
        }

        return canvas;
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        setError(`Failed to render high-quality image: ${message}`);
        return null;
      }
    },
    [screenshotImage, settings, padding]
  );

  return {
    previewUrl,
    isGenerating,
    error,
    renderHighQualityCanvas,
  };
}
