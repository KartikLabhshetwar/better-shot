import type { ShadowSettings } from "@/hooks/useEditorSettings";

export interface RenderOptions {
  image: HTMLImageElement;
  backgroundType: "transparent" | "white" | "black" | "gray" | "gradient" | "custom" | "image";
  customColor: string;
  selectedImage: string | null;
  bgImage: HTMLImageElement | null;
  blurAmount: number;
  noiseAmount: number;
  borderRadius: number;
  padding: number;
  scale?: number;
  gradientImage?: HTMLImageElement | null;
  shadow?: ShadowSettings;
}

export function createHighQualityCanvas(options: RenderOptions): HTMLCanvasElement {
  const {
    image,
    backgroundType,
    customColor,
    selectedImage,
    bgImage,
    blurAmount,
    noiseAmount,
    borderRadius,
    padding,
    // Use scale = 1 to match preview exactly - the image is already at full resolution
    scale = 1,
    gradientImage = null,
    shadow = { blur: 20, offsetX: 0, offsetY: 10, opacity: 30 },
  } = options;

  const bgWidth = image.width + padding * 2;
  const bgHeight = image.height + padding * 2;

  const canvas = document.createElement("canvas");
  canvas.width = bgWidth * scale;
  canvas.height = bgHeight * scale;

  const ctx = canvas.getContext("2d", { alpha: true, desynchronized: true });
  if (!ctx) throw new Error("Failed to get canvas context");

  if (scale !== 1) {
    ctx.scale(scale, scale);
  }
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";

  // When padding is 0, skip background and shadow - just draw the image directly
  if (padding === 0) {
    ctx.beginPath();
    ctx.roundRect(0, 0, image.width, image.height, borderRadius);
    ctx.closePath();
    ctx.clip();
    ctx.drawImage(image, 0, 0, image.width, image.height);
  } else {
    const tempBgCanvas = document.createElement("canvas");
    tempBgCanvas.width = bgWidth;
    tempBgCanvas.height = bgHeight;
    const tempBgCtx = tempBgCanvas.getContext("2d");
    if (!tempBgCtx) throw new Error("Failed to get temp canvas context");

    drawBackground(tempBgCtx, bgWidth, bgHeight, backgroundType, customColor, selectedImage, bgImage, gradientImage);

    const bgCanvas = document.createElement("canvas");
    bgCanvas.width = bgWidth;
    bgCanvas.height = bgHeight;
    const bgCtx = bgCanvas.getContext("2d");
    if (!bgCtx) throw new Error("Failed to get bg canvas context");

    if (blurAmount > 0) {
      // Extend canvas size to prevent edge clipping during blur
      const blurPadding = blurAmount * 3;
      const extendedWidth = bgWidth + blurPadding * 2;
      const extendedHeight = bgHeight + blurPadding * 2;

      const extendedCanvas = document.createElement("canvas");
      extendedCanvas.width = extendedWidth;
      extendedCanvas.height = extendedHeight;
      const extendedCtx = extendedCanvas.getContext("2d");

      if (extendedCtx) {
        // Draw background at offset position
        extendedCtx.drawImage(tempBgCanvas, blurPadding, blurPadding);

        // Fill edges by extending the background
        // Top edge
        extendedCtx.drawImage(tempBgCanvas, 0, 0, bgWidth, 1, blurPadding, 0, bgWidth, blurPadding);
        // Bottom edge
        extendedCtx.drawImage(tempBgCanvas, 0, bgHeight - 1, bgWidth, 1, blurPadding, blurPadding + bgHeight, bgWidth, blurPadding);
        // Left edge
        extendedCtx.drawImage(tempBgCanvas, 0, 0, 1, bgHeight, 0, blurPadding, blurPadding, bgHeight);
        // Right edge
        extendedCtx.drawImage(tempBgCanvas, bgWidth - 1, 0, 1, bgHeight, blurPadding + bgWidth, blurPadding, blurPadding, bgHeight);

        // Apply blur to extended canvas
        const blurredExtCanvas = document.createElement("canvas");
        blurredExtCanvas.width = extendedWidth;
        blurredExtCanvas.height = extendedHeight;
        const blurredExtCtx = blurredExtCanvas.getContext("2d");

        if (blurredExtCtx) {
          blurredExtCtx.filter = `blur(${blurAmount}px)`;
          blurredExtCtx.drawImage(extendedCanvas, 0, 0);
          blurredExtCtx.filter = "none";

          // Crop back to original size
          bgCtx.drawImage(blurredExtCanvas, blurPadding, blurPadding, bgWidth, bgHeight, 0, 0, bgWidth, bgHeight);
        } else {
          bgCtx.drawImage(tempBgCanvas, 0, 0);
        }
      } else {
        bgCtx.drawImage(tempBgCanvas, 0, 0);
      }
    } else {
      bgCtx.drawImage(tempBgCanvas, 0, 0);
    }

    if (noiseAmount > 0) {
      applyNoiseToBackground(bgCtx, bgWidth, bgHeight, noiseAmount);
    }

    ctx.drawImage(bgCanvas, 0, 0);

    const imageCanvas = document.createElement("canvas");
    imageCanvas.width = image.width;
    imageCanvas.height = image.height;
    const imageCtx = imageCanvas.getContext("2d");
    if (!imageCtx) throw new Error("Failed to get image canvas context");

    imageCtx.imageSmoothingEnabled = true;
    imageCtx.imageSmoothingQuality = "high";

    imageCtx.beginPath();
    imageCtx.roundRect(0, 0, image.width, image.height, borderRadius);
    imageCtx.closePath();
    imageCtx.clip();

    imageCtx.drawImage(image, 0, 0, image.width, image.height);

    ctx.save();
    ctx.shadowColor = `rgba(0, 0, 0, ${shadow.opacity / 100})`;
    ctx.shadowBlur = shadow.blur;
    ctx.shadowOffsetX = shadow.offsetX;
    ctx.shadowOffsetY = shadow.offsetY;

    ctx.drawImage(imageCanvas, padding, padding);

    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;
    ctx.restore();
  }

  // Re-apply scale for annotations if needed (restore removed the previous scale)
  if (scale !== 1) {
    ctx.save();
    ctx.scale(scale, scale);
  }

  return canvas;
}

function drawBackground(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  backgroundType: string,
  customColor: string,
  selectedImage: string | null,
  bgImage: HTMLImageElement | null,
  gradientImage: HTMLImageElement | null
) {
  switch (backgroundType) {
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
    case "gradient": {
      if (gradientImage) {
        ctx.drawImage(gradientImage, 0, 0, width, height);
      } else {
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(0, 0, width, height);
      }
      break;
    }
    case "custom":
      ctx.fillStyle = customColor;
      ctx.fillRect(0, 0, width, height);
      break;
    case "image":
      if (bgImage && selectedImage) {
        ctx.drawImage(bgImage, 0, 0, width, height);
      } else {
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(0, 0, width, height);
      }
      break;
  }
}

function applyNoiseToBackground(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  amount: number
) {
  if (amount === 0) return;

  const imageData = ctx.getImageData(0, 0, width, height);
  const data = imageData.data;
  const noiseIntensity = amount * 2.55;

  for (let i = 0; i < data.length; i += 4) {
    const noise = (Math.random() - 0.5) * noiseIntensity;
    data[i] = Math.max(0, Math.min(255, data[i] + noise));
    data[i + 1] = Math.max(0, Math.min(255, data[i + 1] + noise));
    data[i + 2] = Math.max(0, Math.min(255, data[i + 2] + noise));
  }

  ctx.putImageData(imageData, 0, 0);
}
