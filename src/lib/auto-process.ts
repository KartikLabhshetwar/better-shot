import { convertFileSrc } from "@tauri-apps/api/core";
import { Store } from "@tauri-apps/plugin-store";
import { createHighQualityCanvas } from "./canvas-utils";
import { resolveBackgroundPath, getDefaultBackgroundPath } from "./asset-registry";

export async function processScreenshotWithDefaultBackground(
  imagePath: string
): Promise<string> {
  return new Promise(async (resolve, reject) => {
    // Get the default background path, resolving from store if available
    let defaultBgImage: string = getDefaultBackgroundPath();
    
    try {
      const store = await Store.load("settings.json");
      const storedDefaultBg = await store.get<string>("defaultBackgroundImage");
      if (storedDefaultBg) {
        // Resolve the stored value (asset ID or data URL) to actual path
        defaultBgImage = resolveBackgroundPath(storedDefaultBg);
      }
    } catch (err) {
      console.error("Failed to load default background from settings:", err);
    }

    const img = new Image();
    img.crossOrigin = "anonymous";
    
    img.onload = async () => {
      try {
        const bgImg = new Image();
        bgImg.crossOrigin = "anonymous";
        
        bgImg.onload = () => {
          try {
            const canvas = createHighQualityCanvas({
              image: img,
              backgroundType: "image",
              customColor: "#667eea",
              selectedImage: defaultBgImage,
              bgImage: bgImg,
              blurAmount: 0,
              noiseAmount: 20,
              borderRadius: 18,
              padding: 100,
              shadow: {
                blur: 20,
                offsetX: 0,
                offsetY: 10,
                opacity: 30,
              },
            });

            canvas.toBlob(
              (blob) => {
                if (blob) {
                  const reader = new FileReader();
                  reader.onloadend = () => {
                    resolve(reader.result as string);
                  };
                  reader.onerror = () => {
                    reject(new Error("Failed to read processed image"));
                  };
                  reader.readAsDataURL(blob);
                } else {
                  reject(new Error("Failed to create blob from canvas"));
                }
              },
              "image/png",
              1.0
            );
          } catch (err) {
            reject(err);
          }
        };
        
        bgImg.onerror = () => {
          reject(new Error("Failed to load background image"));
        };
        
        bgImg.src = defaultBgImage;
      } catch (err) {
        reject(err);
      }
    };
    
    img.onerror = () => {
      reject(new Error(`Failed to load image from: ${imagePath}`));
    };

    const assetUrl = convertFileSrc(imagePath);
    img.src = assetUrl;
  });
}
