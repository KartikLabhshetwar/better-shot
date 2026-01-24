import { convertFileSrc} from "@tauri-apps/api/core";
import { Store } from "@tauri-apps/plugin-store";
import { createHighQualityCanvas } from "./canvas-utils";
import { resolveBackgroundPath, getDefaultBackgroundPath } from "./asset-registry";

type BackgroundType = "transparent" | "white" | "black" | "gray" | "custom" | "image" | "gradient";

export async function processScreenshotWithDefaultBackground(
  imagePath: string
): Promise<string> {
  return new Promise(async (resolve, reject) => {
    let backgroundType: BackgroundType = "image";
    let customColor = "#667eea";
    let defaultBgImage: string = getDefaultBackgroundPath();
    let bgImage: HTMLImageElement | null = null;
    
    try {
      const store = await Store.load("settings.json");
      const storedBgType = await store.get<BackgroundType>("defaultBackgroundType");
      const storedCustomColor = await store.get<string>("defaultCustomColor");
      const storedDefaultBg = await store.get<string>("defaultBackgroundImage");
      
      if (storedBgType) {
        backgroundType = storedBgType;
      }
      if (storedCustomColor) {
        customColor = storedCustomColor;
      }
      if (storedDefaultBg && (backgroundType === "image" || backgroundType === "gradient")) {
        defaultBgImage = resolveBackgroundPath(storedDefaultBg);
      }
    } catch (err) {
      console.error("Failed to load default background from settings:", err);
    }

    const img = new Image();
    img.crossOrigin = "anonymous";
    
    img.onload = async () => {
      try {
        const avgDimension = (img.width + img.height) / 2;
        const padding = Math.min(Math.round(avgDimension * 0.1), 400);
        const paddingTop = padding;
        const paddingBottom = padding;
        const paddingLeft = padding;
        const paddingRight = padding;

        if (backgroundType === "image" || backgroundType === "gradient") {
          bgImage = new Image();
          bgImage.crossOrigin = "anonymous";
          
          bgImage.onload = () => {
            try {
              const isGradient = backgroundType === "gradient";
              const canvas = createHighQualityCanvas({
                image: img,
                backgroundType,
                customColor,
                selectedImage: isGradient ? null : defaultBgImage,
                bgImage: isGradient ? null : bgImage,
                blurAmount: 0,
                noiseAmount: 20,
                borderRadius: 12,
                paddingTop,
                paddingBottom,
                paddingLeft,
                paddingRight,
                gradientImage: isGradient ? bgImage : null,
                shadow: {
                  blur: 33,
                  offsetX: 18,
                  offsetY: 23,
                  opacity: 39,
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
          
          bgImage.onerror = () => {
            reject(new Error("Failed to load background image"));
          };
          
          bgImage.src = defaultBgImage;
        } else {
          try {
            const isTransparent = backgroundType === "transparent";
            const blurAmount = 0;
            const finalPadding = isTransparent ? 0 : padding;
            const paddingTop = finalPadding;
            const paddingBottom = finalPadding;
            const paddingLeft = finalPadding;
            const paddingRight = finalPadding;

            const canvas = createHighQualityCanvas({
              image: img,
              backgroundType,
              customColor,
              selectedImage: null,
              bgImage: null,
              gradientImage: null,
              blurAmount,
              noiseAmount: 20,
              borderRadius: 12,
              paddingTop,
              paddingBottom,
              paddingLeft,
              paddingRight,
              shadow: isTransparent ? {
                blur: 0,
                offsetX: 0,
                offsetY: 0,
                opacity: 0,
              } : {
                blur: 33,
                offsetX: 18,
                offsetY: 23,
                opacity: 39,
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
        }
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
