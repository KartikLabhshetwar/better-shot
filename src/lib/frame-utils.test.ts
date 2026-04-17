import { describe, expect, it } from "vitest";

import { getContainFitRect, getMacbookFrameDimensions } from "./frame-utils";

describe("frame-utils macbook sizing", () => {
  it("keeps the MacBook frame height stable for the same screenshot width", () => {
    const wideCapture = getMacbookFrameDimensions(1440, 810);
    const tallCapture = getMacbookFrameDimensions(1440, 1200);

    expect(wideCapture.totalWidth).toBe(tallCapture.totalWidth);
    expect(wideCapture.totalHeight).toBe(tallCapture.totalHeight);
    expect(wideCapture.screenWidth).toBe(tallCapture.screenWidth);
    expect(wideCapture.screenHeight).toBe(tallCapture.screenHeight);
    expect(wideCapture.screenHeight).toBe(900);
    expect(wideCapture.totalHeight).toBe(1026);
  });

  it("uses a fixed 16:10 laptop display area", () => {
    const dims = getMacbookFrameDimensions(1280, 720);

    expect(dims.screenWidth).toBe(1280);
    expect(dims.screenHeight).toBe(800);
  });
});

describe("getContainFitRect", () => {
  it("letterboxes wider content inside the MacBook display", () => {
    const fitted = getContainFitRect(1600, 900, 0, 0, 1440, 900);

    expect(fitted.x).toBe(0);
    expect(fitted.y).toBeCloseTo(45);
    expect(fitted.width).toBe(1440);
    expect(fitted.height).toBeCloseTo(810);
  });

  it("pillarboxes taller content inside the MacBook display", () => {
    const fitted = getContainFitRect(900, 1600, 0, 0, 1440, 900);

    expect(fitted.x).toBeCloseTo(466.875);
    expect(fitted.y).toBe(0);
    expect(fitted.width).toBeCloseTo(506.25);
    expect(fitted.height).toBe(900);
  });
});
