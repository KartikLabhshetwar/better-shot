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
  paddingTop: number;
  paddingBottom: number;
  paddingLeft: number;
  paddingRight: number;
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
    paddingTop,
    paddingBottom,
    paddingLeft,
    paddingRight,
    // Use scale = 1 to match preview exactly - the image is already at full resolution
    scale = 1,
    gradientImage = null,
    shadow = { blur: 33, offsetX: 18, offsetY: 23, opacity: 39 },
  } = options;

  const bgWidth = image.width + paddingLeft + paddingRight;
  const bgHeight = image.height + paddingTop + paddingBottom;

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

  // When all padding is 0, skip background and shadow - just draw the image directly
  const totalPadding = paddingTop + paddingBottom + paddingLeft + paddingRight;
  if (totalPadding === 0) {
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

    if (blurAmount > 0) {
      applyGaussianBlurToCanvas(tempBgCanvas, blurAmount);
    }

    if (noiseAmount > 0) {
      applyNoiseToBackground(tempBgCtx, bgWidth, bgHeight, noiseAmount);
    }

    ctx.drawImage(tempBgCanvas, 0, 0);

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

    ctx.drawImage(imageCanvas, paddingLeft, paddingTop);

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

/**
 * Fast box blur for high-quality render (faster than Gaussian, good quality)
 * Uses multiple passes of box blur to approximate Gaussian blur
 */
function applyGaussianBlurToCanvas(canvas: HTMLCanvasElement, radius: number) {
  if (radius <= 0) return;
  
  const passes = Math.min(Math.ceil(radius / 12) + 1, 4);
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
