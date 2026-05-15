export type ExportFormat = "png" | "jpeg";

export interface ExportOptions {
  format: ExportFormat;
  quality: number;
  scalePercent: number;
}

export function getExportDimensions(
  width: number,
  height: number,
  scalePercent: number,
) {
  const scale = Math.max(scalePercent, 1) / 100;
  return {
    width: Math.max(Math.round(width * scale), 1),
    height: Math.max(Math.round(height * scale), 1),
  };
}

export async function createExportDataUrl(
  sourceCanvas: HTMLCanvasElement,
  options: ExportOptions,
): Promise<string> {
  const { width, height } = getExportDimensions(
    sourceCanvas.width,
    sourceCanvas.height,
    options.scalePercent,
  );

  const exportCanvas = document.createElement("canvas");
  exportCanvas.width = width;
  exportCanvas.height = height;

  const ctx = exportCanvas.getContext("2d");
  if (!ctx) {
    throw new Error("Failed to get export canvas context");
  }

  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(sourceCanvas, 0, 0, width, height);

  const mimeType = options.format === "jpeg" ? "image/jpeg" : "image/png";
  const quality = options.format === "jpeg" ? options.quality / 100 : undefined;

  const blob = await new Promise<Blob>((resolve, reject) => {
    exportCanvas.toBlob(
      (value) => {
        if (value) {
          resolve(value);
        } else {
          reject(new Error("Failed to encode export image"));
        }
      },
      mimeType,
      quality,
    );
  });

  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error("Failed to read export image data"));
    reader.readAsDataURL(blob);
  });
}
