import { convertFileSrc } from "@tauri-apps/api/core";
import { Store } from "@tauri-apps/plugin-store";
import { createHighQualityCanvas } from "./canvas-utils";
import { resolveBackgroundPath, getDefaultBackgroundPath } from "./asset-registry";

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`Failed to load image: ${src}`));
    img.src = src;
  });
}

function canvasToDataUrl(canvas: HTMLCanvasElement): Promise<string> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) {
          reject(new Error("Failed to create blob from canvas"));
          return;
        }
        const reader = new FileReader();
        reader.onloadend = () => resolve(reader.result as string);
        reader.onerror = () => reject(new Error("Failed to read processed image"));
        reader.readAsDataURL(blob);
      },
      "image/png",
      1.0
    );
  });
}

export async function processScreenshotWithDefaultBackground(
  imagePath: string
): Promise<string> {
  // Get the default background path, resolving from store if available
  let defaultBgImage: string = getDefaultBackgroundPath();

  try {
    const store = await Store.load("settings.json");
    const storedDefaultBg = await store.get<string>("defaultBackgroundImage");
    if (storedDefaultBg) {
      defaultBgImage = resolveBackgroundPath(storedDefaultBg);
    }
  } catch (err) {
    console.error("Failed to load default background from settings:", err);
  }

  const assetUrl = convertFileSrc(imagePath);
  const img = await loadImage(assetUrl);
  const bgImg = await loadImage(defaultBgImage);

  const canvas = createHighQualityCanvas({
    image: img,
    backgroundType: "image",
    customColor: "#667eea",
    selectedImage: defaultBgImage,
    bgImage: bgImg,
    blurAmount: 0,
    noiseAmount: 0,
    borderRadius: 18,
    padding: 100,
    shadow: {
      blur: 20,
      offsetX: 0,
      offsetY: 10,
      opacity: 30,
    },
  });

  return canvasToDataUrl(canvas);
}
