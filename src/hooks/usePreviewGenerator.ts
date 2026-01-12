import { useRef, useEffect, useCallback, useState } from "react";
import { EditorSettings } from "./useEditorSettings";
import { createHighQualityCanvas } from "@/lib/canvas-utils";
import { drawAnnotationOnCanvas } from "@/lib/annotation-utils";
import { Annotation } from "@/types/annotations";

// Image cache - shared across all hook instances
const imageCache = new Map<string, HTMLImageElement>();

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
      imageCache.set(src, img);
      resolve(img);
    };
    img.onerror = reject;
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
      const squareSize = 10;
      for (let y = 0; y < height; y += squareSize) {
        for (let x = 0; x < width; x += squareSize) {
          const isEven = ((x / squareSize) + (y / squareSize)) % 2 === 0;
          ctx.fillStyle = isEven ? "#ffffff" : "#e0e0e0";
          ctx.fillRect(x, y, squareSize, squareSize);
        }
      }
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
 * Apply blur effect to a canvas with edge extension to prevent edge artifacts
 */
function applyBlur(
  sourceCanvas: HTMLCanvasElement,
  blurAmount: number
): HTMLCanvasElement {
  if (blurAmount <= 0) return sourceCanvas;

  const width = sourceCanvas.width;
  const height = sourceCanvas.height;
  
  // Extend canvas size to prevent edge clipping during blur
  const blurPadding = blurAmount * 3;
  const extendedWidth = width + blurPadding * 2;
  const extendedHeight = height + blurPadding * 2;
  
  const extendedCanvas = document.createElement("canvas");
  extendedCanvas.width = extendedWidth;
  extendedCanvas.height = extendedHeight;
  const extendedCtx = extendedCanvas.getContext("2d");
  
  if (!extendedCtx) {
    // Fallback to simple blur if context fails
    const blurCanvas = document.createElement("canvas");
    blurCanvas.width = width;
    blurCanvas.height = height;
    const blurCtx = blurCanvas.getContext("2d")!;
    blurCtx.filter = `blur(${blurAmount}px)`;
    blurCtx.drawImage(sourceCanvas, 0, 0);
    blurCtx.filter = "none";
    return blurCanvas;
  }
  
  // Draw background at offset position
  extendedCtx.drawImage(sourceCanvas, blurPadding, blurPadding);
  
  // Fill edges by extending the background
  // Top edge
  extendedCtx.drawImage(sourceCanvas, 0, 0, width, 1, blurPadding, 0, width, blurPadding);
  // Bottom edge
  extendedCtx.drawImage(sourceCanvas, 0, height - 1, width, 1, blurPadding, blurPadding + height, width, blurPadding);
  // Left edge
  extendedCtx.drawImage(sourceCanvas, 0, 0, 1, height, 0, blurPadding, blurPadding, height);
  // Right edge
  extendedCtx.drawImage(sourceCanvas, width - 1, 0, 1, height, blurPadding + width, blurPadding, blurPadding, height);
  
  // Apply blur to extended canvas
  const blurredExtCanvas = document.createElement("canvas");
  blurredExtCanvas.width = extendedWidth;
  blurredExtCanvas.height = extendedHeight;
  const blurredExtCtx = blurredExtCanvas.getContext("2d");
  
  if (!blurredExtCtx) {
    // Fallback
    const blurCanvas = document.createElement("canvas");
    blurCanvas.width = width;
    blurCanvas.height = height;
    const blurCtx = blurCanvas.getContext("2d")!;
    blurCtx.filter = `blur(${blurAmount}px)`;
    blurCtx.drawImage(sourceCanvas, 0, 0);
    blurCtx.filter = "none";
    return blurCanvas;
  }
  
  blurredExtCtx.filter = `blur(${blurAmount}px)`;
  blurredExtCtx.drawImage(extendedCanvas, 0, 0);
  blurredExtCtx.filter = "none";
  
  // Crop back to original size
  const resultCanvas = document.createElement("canvas");
  resultCanvas.width = width;
  resultCanvas.height = height;
  const resultCtx = resultCanvas.getContext("2d")!;
  resultCtx.drawImage(blurredExtCanvas, blurPadding, blurPadding, width, height, 0, 0, width, height);
  
  return resultCanvas;
}

/**
 * Apply noise effect to a canvas (modifies in place)
 */
function applyNoise(canvas: HTMLCanvasElement, noiseAmount: number) {
  if (noiseAmount <= 0) return;

  const ctx = canvas.getContext("2d")!;
  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const data = imageData.data;
  const noiseIntensity = noiseAmount * 2.55;

  for (let i = 0; i < data.length; i += 4) {
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

/**
 * Hook for generating preview images based on editor settings
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

  // Generate preview when settings or image changes
  useEffect(() => {
    if (!screenshotImage || !canvasRef.current) return;

    const currentRenderId = ++renderIdRef.current;
    const canvas = canvasRef.current;
    const bgWidth = screenshotImage.width + padding * 2;
    const bgHeight = screenshotImage.height + padding * 2;

    const generatePreview = async () => {
      setIsGenerating(true);
      setError(null);

      try {
        // Load background image if needed
        const bgSrc = getBackgroundImageSrc(settings);
        let bgImage: HTMLImageElement | null = null;
        if (bgSrc) {
          bgImage = await loadImage(bgSrc);
        }

        // Check if this render is still current
        if (currentRenderId !== renderIdRef.current) return;

        // Set canvas size
        canvas.width = bgWidth;
        canvas.height = bgHeight;
        const ctx = canvas.getContext("2d", { alpha: true });
        if (!ctx) {
          setError("Failed to get canvas context");
          return;
        }

        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = "high";

        // Create temp canvas for background
        const tempCanvas = document.createElement("canvas");
        tempCanvas.width = bgWidth;
        tempCanvas.height = bgHeight;
        const tempCtx = tempCanvas.getContext("2d")!;
        drawBackground(tempCtx, bgWidth, bgHeight, settings, bgImage);

        // Apply effects
        let finalBgCanvas = applyBlur(tempCanvas, settings.blurAmount);
        applyNoise(finalBgCanvas, settings.noiseAmount);

        // Draw final background
        ctx.drawImage(finalBgCanvas, 0, 0);

        // Draw screenshot with shadow and rounded corners
        ctx.save();
        ctx.shadowColor = "rgba(0, 0, 0, 0.3)";
        ctx.shadowBlur = 20;
        ctx.shadowOffsetX = 0;
        ctx.shadowOffsetY = 10;

        ctx.beginPath();
        ctx.roundRect(padding, padding, screenshotImage.width, screenshotImage.height, settings.borderRadius);
        ctx.closePath();
        ctx.clip();

        ctx.drawImage(screenshotImage, padding, padding, screenshotImage.width, screenshotImage.height);
        ctx.restore();

        // Check again if this render is still current
        if (currentRenderId !== renderIdRef.current) return;

        // Generate preview URL
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
    };

    generatePreview();
  }, [
    screenshotImage,
    settings.backgroundType,
    settings.selectedImageSrc,
    settings.gradientId,
    settings.gradientSrc,
    settings.customColor,
    settings.blurAmount,
    settings.noiseAmount,
    settings.borderRadius,
    canvasRef,
    padding,
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
        // Load background image if needed
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
          padding,
          gradientImage: settings.backgroundType === "gradient" ? bgImage : null,
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
