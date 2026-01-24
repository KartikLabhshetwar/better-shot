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
 * Fast box blur approximation for preview (much faster than Gaussian)
 * Uses multiple passes of box blur to approximate Gaussian blur
 * Optimized with sliding window algorithm for O(n) performance
 */
function applyFastBoxBlur(canvas: HTMLCanvasElement, radius: number) {
  if (radius <= 0) return;
  
  const passes = Math.min(Math.ceil(radius / 15) + 1, 3);
  const boxRadius = Math.floor(radius / passes);
  
  if (boxRadius <= 0) return;
  
  const ctx = canvas.getContext("2d")!;
  const width = canvas.width;
  const height = canvas.height;
  const kernelSize = boxRadius * 2 + 1;
  
  for (let pass = 0; pass < passes; pass++) {
    const imageData = ctx.getImageData(0, 0, width, height);
    const data = imageData.data;
    const tempData = new Uint8ClampedArray(data);
    
    for (let y = 0; y < height; y++) {
      let rSum = 0, gSum = 0, bSum = 0, aSum = 0;
      
      for (let x = 0; x < width; x++) {
        if (x === 0) {
          for (let kx = -boxRadius; kx <= boxRadius; kx++) {
            const px = Math.max(0, Math.min(width - 1, kx));
            const idx = (y * width + px) * 4;
            rSum += data[idx];
            gSum += data[idx + 1];
            bSum += data[idx + 2];
            aSum += data[idx + 3];
          }
        } else {
          const removeX = Math.max(0, Math.min(width - 1, x - boxRadius - 1));
          const addX = Math.max(0, Math.min(width - 1, x + boxRadius));
          const removeIdx = (y * width + removeX) * 4;
          const addIdx = (y * width + addX) * 4;
          
          rSum = rSum - data[removeIdx] + data[addIdx];
          gSum = gSum - data[removeIdx + 1] + data[addIdx + 1];
          bSum = bSum - data[removeIdx + 2] + data[addIdx + 2];
          aSum = aSum - data[removeIdx + 3] + data[addIdx + 3];
        }
        
        const idx = (y * width + x) * 4;
        tempData[idx] = Math.round(rSum / kernelSize);
        tempData[idx + 1] = Math.round(gSum / kernelSize);
        tempData[idx + 2] = Math.round(bSum / kernelSize);
        tempData[idx + 3] = Math.round(aSum / kernelSize);
      }
    }
    
    const finalData = new Uint8ClampedArray(tempData);
    
    for (let x = 0; x < width; x++) {
      let rSum = 0, gSum = 0, bSum = 0, aSum = 0;
      
      for (let y = 0; y < height; y++) {
        if (y === 0) {
          for (let ky = -boxRadius; ky <= boxRadius; ky++) {
            const py = Math.max(0, Math.min(height - 1, ky));
            const idx = (py * width + x) * 4;
            rSum += tempData[idx];
            gSum += tempData[idx + 1];
            bSum += tempData[idx + 2];
            aSum += tempData[idx + 3];
          }
        } else {
          const removeY = Math.max(0, Math.min(height - 1, y - boxRadius - 1));
          const addY = Math.max(0, Math.min(height - 1, y + boxRadius));
          const removeIdx = (removeY * width + x) * 4;
          const addIdx = (addY * width + x) * 4;
          
          rSum = rSum - tempData[removeIdx] + tempData[addIdx];
          gSum = gSum - tempData[removeIdx + 1] + tempData[addIdx + 1];
          bSum = bSum - tempData[removeIdx + 2] + tempData[addIdx + 2];
          aSum = aSum - tempData[removeIdx + 3] + tempData[addIdx + 3];
        }
        
        const idx = (y * width + x) * 4;
        finalData[idx] = Math.round(rSum / kernelSize);
        finalData[idx + 1] = Math.round(gSum / kernelSize);
        finalData[idx + 2] = Math.round(bSum / kernelSize);
        finalData[idx + 3] = Math.round(aSum / kernelSize);
      }
    }
    
    ctx.putImageData(new ImageData(finalData, width, height), 0, 0);
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
  paddingTop?: number;
  paddingBottom?: number;
  paddingLeft?: number;
  paddingRight?: number;
  imagePath?: string;
}

export interface PreviewGeneratorResult {
  previewUrl: string | null;
  isGenerating: boolean;
  error: string | null;
  renderHighQualityCanvas: (annotations: Annotation[], imagePath?: string) => Promise<HTMLCanvasElement | null>;
}

const PREVIEW_DEBOUNCE_MS = 16;
const BLUR_DEBOUNCE_MS = 100;

/**
 * Hook for generating preview images based on editor settings
 * Optimized with debouncing to prevent lag during slider interaction
 */
export function usePreviewGenerator({
  screenshotImage,
  settings,
  canvasRef,
  paddingTop = 100,
  paddingBottom = 100,
  paddingLeft = 100,
  paddingRight = 100,
  imagePath,
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

    const bgWidth = screenshotImage.width + paddingLeft + paddingRight;
    const bgHeight = screenshotImage.height + paddingTop + paddingBottom;

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

      // When all padding is 0, skip background and shadow - just draw the image directly
      const totalPadding = paddingTop + paddingBottom + paddingLeft + paddingRight;
      if (totalPadding === 0) {
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
        
        if (settingsToRender.blurAmount > 0) {
          applyFastBoxBlur(tempCanvas, settingsToRender.blurAmount);
        }

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

        ctx.drawImage(imageCanvas, paddingLeft, paddingTop);

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
  }, [screenshotImage, canvasRef, paddingTop, paddingBottom, paddingLeft, paddingRight]);

  // Debounced preview generation
  useEffect(() => {
    if (!screenshotImage || !canvasRef.current) return;

    // Cancel any pending debounce
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
    }

    // Store pending settings
    pendingSettingsRef.current = settings;

    // Use longer debounce for blur to improve performance
    const debounceDelay = settings.blurAmount > 0 ? BLUR_DEBOUNCE_MS : PREVIEW_DEBOUNCE_MS;

    // Debounce the actual render
    debounceTimerRef.current = setTimeout(() => {
      if (pendingSettingsRef.current) {
        generatePreview(pendingSettingsRef.current);
      }
    }, debounceDelay);

    return () => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
    };
  }, [
    screenshotImage,
    bgSettingsKey,
    settings.blurAmount,
    settings.noiseAmount,
    settings.borderRadius,
    settings.shadow.blur,
    settings.shadow.offsetX,
    settings.shadow.offsetY,
    settings.shadow.opacity,
    paddingTop,
    paddingBottom,
    paddingLeft,
    paddingRight,
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
    async (annotations: Annotation[], imagePath?: string): Promise<HTMLCanvasElement | null> => {
      if (!screenshotImage) return null;

      try {
        if (settings.blurAmount > 0 && imagePath && (settings.backgroundType === "transparent" || settings.backgroundType === "white" || settings.backgroundType === "black" || settings.backgroundType === "gray" || settings.backgroundType === "custom")) {
          try {
            const { invoke } = await import("@tauri-apps/api/core");
            const rustRendered = await invoke<string>("render_image_with_effects_rust", {
              imagePath,
              settings: {
                background_type: settings.backgroundType,
                custom_color: settings.customColor,
                blur_amount: settings.blurAmount,
                noise_amount: settings.noiseAmount,
                border_radius: settings.borderRadius,
                padding_top: paddingTop,
                padding_bottom: paddingBottom,
                padding_left: paddingLeft,
                padding_right: paddingRight,
                shadow_blur: settings.shadow.blur,
                shadow_offset_x: settings.shadow.offsetX,
                shadow_offset_y: settings.shadow.offsetY,
                shadow_opacity: settings.shadow.opacity,
              },
            });

            const img = new Image();
            await new Promise<void>((resolve, reject) => {
              img.onload = () => resolve();
              img.onerror = () => reject(new Error("Failed to load Rust-rendered image"));
              img.src = rustRendered;
            });

            const canvas = document.createElement("canvas");
            canvas.width = img.width;
            canvas.height = img.height;
            const ctx = canvas.getContext("2d");
            if (!ctx) throw new Error("Failed to get canvas context");

            ctx.drawImage(img, 0, 0);

            if (annotations.length > 0) {
              annotations.forEach((annotation) => {
                drawAnnotationOnCanvas(ctx, annotation);
              });
            }

            return canvas;
          } catch (rustErr) {
            console.warn("Rust rendering failed, falling back to JS:", rustErr);
          }
        }

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
          blurAmount: settings.blurAmount,
          noiseAmount: settings.noiseAmount,
          borderRadius: settings.borderRadius,
          paddingTop,
          paddingBottom,
          paddingLeft,
          paddingRight,
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
    [screenshotImage, settings, paddingTop, paddingBottom, paddingLeft, paddingRight, imagePath]
  );

  return {
    previewUrl,
    isGenerating,
    error,
    renderHighQualityCanvas,
  };
}
