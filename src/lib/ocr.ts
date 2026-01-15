import { createWorker, Worker, PSM } from "tesseract.js";

let workerInstance: Worker | null = null;
let workerInitializing = false;
let workerInitPromise: Promise<Worker> | null = null;

async function getWorker(): Promise<Worker> {
  if (workerInstance) {
    return workerInstance;
  }

  if (workerInitializing && workerInitPromise) {
    return workerInitPromise;
  }

  workerInitializing = true;
  workerInitPromise = createWorker("eng", 1, {
    logger: (m: { status?: string; progress?: number }) => {
      if (m.status === "recognizing text" && m.progress !== undefined) {
        console.log(`OCR progress: ${Math.round(m.progress * 100)}%`);
      }
    },
  }).then(async (worker: Worker) => {
    await worker.setParameters({
      tessedit_pageseg_mode: PSM.AUTO,
      tessedit_char_whitelist: "",
      preserve_interword_spaces: "1",
    });
    workerInstance = worker;
    workerInitializing = false;
    return worker;
  });

  return workerInitPromise;
}

function preprocessImageForOCR(canvas: HTMLCanvasElement): HTMLCanvasElement {
  const processedCanvas = document.createElement("canvas");
  const targetDPI = 300;
  const baseDPI = 72;
  
  const scale = Math.max(1, targetDPI / baseDPI);
  processedCanvas.width = Math.round(canvas.width * scale);
  processedCanvas.height = Math.round(canvas.height * scale);
  
  const ctx = processedCanvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) {
    throw new Error("Failed to get canvas context for preprocessing");
  }
  
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(canvas, 0, 0, processedCanvas.width, processedCanvas.height);
  
  const imageData = ctx.getImageData(0, 0, processedCanvas.width, processedCanvas.height);
  const data = imageData.data;
  const width = processedCanvas.width;
  const height = processedCanvas.height;
  
  const grayscale = new Uint8Array(width * height);
  
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i];
    const g = data[i + 1];
    const b = data[i + 2];
    const gray = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
    grayscale[i / 4] = gray;
  }
  
  const contrastFactor = 1.8;
  const brightnessAdjust = 10;
  
  for (let i = 0; i < data.length; i += 4) {
    const pixelIndex = i / 4;
    let gray = grayscale[pixelIndex];
    
    gray = (gray - 128) * contrastFactor + 128 + brightnessAdjust;
    gray = Math.max(0, Math.min(255, gray));
    
    const threshold = 140;
    const binary = gray > threshold ? 255 : 0;
    
    data[i] = binary;
    data[i + 1] = binary;
    data[i + 2] = binary;
  }
  
  ctx.putImageData(imageData, 0, 0);
  
  return processedCanvas;
}

export async function recognizeTextFromCanvas(
  canvas: HTMLCanvasElement,
  region?: { x: number; y: number; width: number; height: number }
): Promise<string> {
  const worker = await getWorker();

  let sourceCanvas: HTMLCanvasElement = canvas;

  if (region) {
    const tempCanvas = document.createElement("canvas");
    tempCanvas.width = region.width;
    tempCanvas.height = region.height;
    const ctx = tempCanvas.getContext("2d");
    if (!ctx) {
      throw new Error("Failed to create temporary canvas context");
    }
    ctx.drawImage(
      canvas,
      region.x,
      region.y,
      region.width,
      region.height,
      0,
      0,
      region.width,
      region.height
    );
    sourceCanvas = tempCanvas;
  }

  const processedCanvas = preprocessImageForOCR(sourceCanvas);

  const { data } = await worker.recognize(processedCanvas, {
    rotateAuto: true,
  });
  
  return data.text.trim();
}

export async function recognizeTextFromImageData(
  imageData: ImageData
): Promise<string> {
  const worker = await getWorker();
  
  const tempCanvas = document.createElement("canvas");
  tempCanvas.width = imageData.width;
  tempCanvas.height = imageData.height;
  const ctx = tempCanvas.getContext("2d");
  if (!ctx) {
    throw new Error("Failed to create canvas context");
  }
  ctx.putImageData(imageData, 0, 0);
  
  const processedCanvas = preprocessImageForOCR(tempCanvas);
  
  const { data } = await worker.recognize(processedCanvas, {
    rotateAuto: true,
  });
  
  return data.text.trim();
}

export async function terminateWorker(): Promise<void> {
  if (workerInstance) {
    await workerInstance.terminate();
    workerInstance = null;
    workerInitPromise = null;
    workerInitializing = false;
  }
}
