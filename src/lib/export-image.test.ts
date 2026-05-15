import { afterEach, describe, expect, it, vi } from "vitest";
import { createExportDataUrl, getExportDimensions } from "./export-image";

function createMockCanvas(width: number, height: number) {
  const sourceCanvas = document.createElement("canvas");
  sourceCanvas.width = width;
  sourceCanvas.height = height;
  return sourceCanvas;
}

describe("export image helpers", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("calculates proportional export dimensions from scale percent", () => {
    expect(getExportDimensions(1200, 800, 50)).toEqual({ width: 600, height: 400 });
    expect(getExportDimensions(1200, 800, 125)).toEqual({ width: 1500, height: 1000 });
  });

  it("encodes JPEG with scaled dimensions and quality", async () => {
    const sourceCanvas = createMockCanvas(1200, 800);
    const drawImage = vi.fn();
    const toBlob = vi.fn((callback: BlobCallback, type?: string, quality?: number) => {
      callback(new Blob(["jpeg"], { type: type ?? "image/png" }));
      return undefined;
    });

    vi.spyOn(document, "createElement").mockImplementation((tagName) => {
      const canvas = document.createElementNS("http://www.w3.org/1999/xhtml", tagName) as HTMLCanvasElement;
      if (tagName === "canvas") {
        vi.spyOn(canvas, "getContext").mockReturnValue({
          drawImage,
          imageSmoothingEnabled: false,
          imageSmoothingQuality: "low",
        } as unknown as CanvasRenderingContext2D);
        vi.spyOn(canvas, "toBlob").mockImplementation(toBlob);
      }
      return canvas;
    });

    const dataUrl = await createExportDataUrl(sourceCanvas, {
      format: "jpeg",
      quality: 72,
      scalePercent: 50,
    });

    expect(dataUrl).toBe("data:image/jpeg;base64,anBlZw==");
    expect(drawImage).toHaveBeenCalledWith(sourceCanvas, 0, 0, 600, 400);
    expect(toBlob).toHaveBeenCalledWith(expect.any(Function), "image/jpeg", 0.72);
  });

  it("encodes PNG without lossy quality", async () => {
    const sourceCanvas = createMockCanvas(100, 50);
    const toBlob = vi.fn((callback: BlobCallback, type?: string, quality?: number) => {
      callback(new Blob(["png"], { type: type ?? "image/png" }));
      return undefined;
    });

    vi.spyOn(document, "createElement").mockImplementation((tagName) => {
      const canvas = document.createElementNS("http://www.w3.org/1999/xhtml", tagName) as HTMLCanvasElement;
      if (tagName === "canvas") {
        vi.spyOn(canvas, "getContext").mockReturnValue({
          drawImage: vi.fn(),
          imageSmoothingEnabled: false,
          imageSmoothingQuality: "low",
        } as unknown as CanvasRenderingContext2D);
        vi.spyOn(canvas, "toBlob").mockImplementation(toBlob);
      }
      return canvas;
    });

    await createExportDataUrl(sourceCanvas, {
      format: "png",
      quality: 40,
      scalePercent: 100,
    });

    expect(toBlob).toHaveBeenCalledWith(expect.any(Function), "image/png", undefined);
  });
});
