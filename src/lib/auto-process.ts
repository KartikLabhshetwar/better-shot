import { convertFileSrc } from "@tauri-apps/api/core";
import { createHighQualityCanvas } from "./canvas-utils";
import bgImage18 from "@/assets/bg-images/asset-18.jpg";

export async function processScreenshotWithDefaultBackground(
  imagePath: string
): Promise<string> {
  return new Promise((resolve, reject) => {
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
              selectedImage: bgImage18,
              bgImage: bgImg,
              blurAmount: 0,
              noiseAmount: 0,
              borderRadius: 18,
              padding: 100,
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
        
        bgImg.src = bgImage18;
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
