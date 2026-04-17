/**
 * Device frame rendering utilities.
 *
 * Each drawXxxFrame function composites a device mockup around a screenshot:
 *   1. Draws the frame chrome (bezel, title bar, etc.) on the provided ctx
 *   2. Clips and draws the screenshot image into the frame's screen area
 *
 * Callers are responsible for applying shadow BEFORE calling these functions
 * (set ctx.shadow* before calling, restore after).
 *
 * All frames are drawn programmatically so they scale perfectly to any
 * screenshot size without raster artifacts.
 */

export type FrameType = "none" | "terminal" | "iphone" | "macbook";

export interface FrameDimensions {
  /** Total width of the framed composition */
  totalWidth: number;
  /** Total height of the framed composition */
  totalHeight: number;
  /** X position of the screen/content area within the frame */
  screenX: number;
  /** Y position of the screen/content area within the frame */
  screenY: number;
  /** Width of the screen/content area */
  screenWidth: number;
  /** Height of the screen/content area */
  screenHeight: number;
}

export interface FittedRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export function getContainFitRect(
  contentWidth: number,
  contentHeight: number,
  containerX: number,
  containerY: number,
  containerWidth: number,
  containerHeight: number
): FittedRect {
  const scale = Math.min(containerWidth / contentWidth, containerHeight / contentHeight);
  const width = contentWidth * scale;
  const height = contentHeight * scale;

  return {
    x: containerX + (containerWidth - width) / 2,
    y: containerY + (containerHeight - height) / 2,
    width,
    height,
  };
}

// ---------------------------------------------------------------------------
// Terminal frame
// ---------------------------------------------------------------------------

const TERMINAL_TITLE_BAR_HEIGHT = 38;
const TERMINAL_CORNER_RADIUS = 10;
const TERMINAL_BUTTON_RADIUS = 6;
const TERMINAL_BUTTON_Y_OFFSET = 13;
const TERMINAL_BUTTON_SPACING = 20;
const TERMINAL_BUTTON_START_X = 16;
const TERMINAL_BG = "#1e1e1e";
const TERMINAL_TITLE_BAR_BG = "#2d2d2d";

export function getTerminalFrameDimensions(screenshotWidth: number, screenshotHeight: number): FrameDimensions {
  return {
    totalWidth: screenshotWidth,
    totalHeight: screenshotHeight + TERMINAL_TITLE_BAR_HEIGHT,
    screenX: 0,
    screenY: TERMINAL_TITLE_BAR_HEIGHT,
    screenWidth: screenshotWidth,
    screenHeight: screenshotHeight,
  };
}

export function drawTerminalFrame(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  dims: FrameDimensions,
  screenshot: HTMLImageElement
) {
  const { totalWidth, totalHeight, screenX, screenY, screenWidth, screenHeight } = dims;

  ctx.save();

  // Outer rounded rect (full frame)
  ctx.beginPath();
  ctx.roundRect(x, y, totalWidth, totalHeight, TERMINAL_CORNER_RADIUS);
  ctx.closePath();

  // Fill entire frame with terminal body color
  ctx.fillStyle = TERMINAL_BG;
  ctx.fill();

  // Clip to rounded rect so title bar + screenshot stay inside frame bounds
  ctx.clip();

  // Title bar background
  ctx.fillStyle = TERMINAL_TITLE_BAR_BG;
  ctx.fillRect(x, y, totalWidth, TERMINAL_TITLE_BAR_HEIGHT);

  // Separator line between title bar and content
  ctx.strokeStyle = "rgba(0,0,0,0.4)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(x, y + TERMINAL_TITLE_BAR_HEIGHT);
  ctx.lineTo(x + totalWidth, y + TERMINAL_TITLE_BAR_HEIGHT);
  ctx.stroke();

  // Traffic light buttons
  const buttons = [
    { color: "#ff5f57", border: "#e0443e" }, // close
    { color: "#febc2e", border: "#d4a017" }, // minimize
    { color: "#28c840", border: "#14a630" }, // maximize
  ];

  buttons.forEach((btn, i) => {
    const bx = x + TERMINAL_BUTTON_START_X + i * TERMINAL_BUTTON_SPACING;
    const by = y + TERMINAL_BUTTON_Y_OFFSET;

    ctx.beginPath();
    ctx.arc(bx, by, TERMINAL_BUTTON_RADIUS, 0, Math.PI * 2);
    ctx.fillStyle = btn.color;
    ctx.fill();
    ctx.strokeStyle = btn.border;
    ctx.lineWidth = 0.5;
    ctx.stroke();
  });

  // Draw screenshot into the body area
  ctx.drawImage(screenshot, x + screenX, y + screenY, screenWidth, screenHeight);

  ctx.restore();
}

// ---------------------------------------------------------------------------
// iPhone frame
// Reference: custats-info/src/components/MobileApp.jsx + screenshot
//
// The frame has a FIXED portrait shape. The screenshot is drawn into it
// using object-cover / object-top semantics (fill screen, align top).
//
// Frame width = screenshot width + 2 * bezel.
// Screen area = 9:19.5 aspect ratio, same width as screenshot.
// Frame height = screen height + 2 * bezel.
//
// Radii are proportional to frame width (like CSS rem units scale with font).
// At 390px screen width (reference): outer=40px, inner=35px, bezel=6px.
// We scale these proportionally so they look right at any screenshot width.
//
// Layer order:
//   1. Outer bezel (dark rounded rect)
//   2. Screen container (black, slightly smaller radius), clips content
//   3. Screenshot drawn with cover+top semantics
//   4. Dynamic Island pill on top (overlays screenshot)
//   5. Home indicator bar
// ---------------------------------------------------------------------------

const IPHONE_FRAME_COLOR = "#1a1a1a";  // bg-foreground/90
const IPHONE_SCREEN_COLOR = "#000000";
const IPHONE_INDICATOR_COLOR = "rgba(255,255,255,0.35)";

// Reference dimensions at 390px screen width
const REF_SCREEN_W = 390;
const REF_BEZEL = 6;         // p-[6px]
const REF_OUTER_R = 40;      // rounded-[2.5rem]
const REF_INNER_R = 35;      // rounded-[2.2rem]
const REF_DI_W = 90;         // Dynamic Island width
const REF_DI_H = 28;         // Dynamic Island height
const REF_DI_TOP = 12;       // top-3 = 12px
const REF_IND_H = 5;
const REF_IND_BOTTOM = 14;

// iPhone screen aspect ratio: 9/19.5
const IPHONE_ASPECT = 9 / 19.5;

export function getIphoneFrameDimensions(screenshotWidth: number, _screenshotHeight: number): FrameDimensions {
  // Scale factor relative to reference 390px width
  const scale = screenshotWidth / REF_SCREEN_W;
  const bezel = Math.round(REF_BEZEL * scale);

  // Screen area: same width as screenshot, height from 9:19.5 ratio
  const screenW = screenshotWidth;
  const screenH = Math.round(screenW / IPHONE_ASPECT);

  const totalWidth  = screenW + bezel * 2;
  const totalHeight = screenH + bezel * 2;

  return {
    totalWidth,
    totalHeight,
    screenX: bezel,
    screenY: bezel,
    screenWidth:  screenW,
    screenHeight: screenH,
  };
}

export function drawIphoneFrame(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  dims: FrameDimensions,
  screenshot: HTMLImageElement
) {
  const { totalWidth, totalHeight, screenWidth, screenHeight } = dims;

  // Scale all proportional values from the reference 390px width
  const scale = screenWidth / REF_SCREEN_W;
  const bezel    = Math.round(REF_BEZEL * scale);
  const outerR   = Math.round(REF_OUTER_R * scale);
  const innerR   = Math.round(REF_INNER_R * scale);
  const diW      = Math.round(REF_DI_W * scale);
  const diH      = Math.round(REF_DI_H * scale);
  const diTop    = Math.round(REF_DI_TOP * scale);
  const indH     = Math.max(3, Math.round(REF_IND_H * scale));
  const indBot   = Math.round(REF_IND_BOTTOM * scale);

  ctx.save();

  // ── 1. Outer bezel ──
  ctx.beginPath();
  ctx.roundRect(x, y, totalWidth, totalHeight, outerR);
  ctx.fillStyle = IPHONE_FRAME_COLOR;
  ctx.fill();

  // ── 2. Screen container (black) — clip all content inside ──
  const sx = x + bezel;
  const sy = y + bezel;

  ctx.beginPath();
  ctx.roundRect(sx, sy, screenWidth, screenHeight, innerR);
  ctx.fillStyle = IPHONE_SCREEN_COLOR;
  ctx.fill();

  // ── 3. Screenshot — object-cover object-top into screen area ──
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(sx, sy, screenWidth, screenHeight, innerR);
  ctx.clip();

  // object-cover: scale screenshot to fill screen, maintain aspect ratio
  const imgAspect = screenshot.width / screenshot.height;
  const screenAspect = screenWidth / screenHeight;
  let drawW: number, drawH: number, drawX: number, drawY: number;

  if (imgAspect > screenAspect) {
    // Image is wider — fit height, crop width
    drawH = screenHeight;
    drawW = drawH * imgAspect;
    drawX = sx + (screenWidth - drawW) / 2; // center horizontally
    drawY = sy;                              // align top
  } else {
    // Image is taller — fit width, crop height
    drawW = screenWidth;
    drawH = drawW / imgAspect;
    drawX = sx;
    drawY = sy;                              // object-top: align to top
  }

  ctx.drawImage(screenshot, drawX, drawY, drawW, drawH);
  ctx.restore();

  // ── 4. Dynamic Island pill — overlaid on screenshot ──
  const diX = x + (totalWidth - diW) / 2;
  const diY = sy + diTop;

  ctx.beginPath();
  ctx.roundRect(diX, diY, diW, diH, diH / 2);
  ctx.fillStyle = IPHONE_SCREEN_COLOR;
  ctx.fill();

  // ── 5. Home indicator ──
  const indWidth = totalWidth * 0.3;
  const indX = x + (totalWidth - indWidth) / 2;
  const indY = y + totalHeight - indBot;

  ctx.beginPath();
  ctx.roundRect(indX, indY, indWidth, indH, indH / 2);
  ctx.fillStyle = IPHONE_INDICATOR_COLOR;
  ctx.fill();

  ctx.restore();
}

// ---------------------------------------------------------------------------
// MacBook frame
// Reference: classic MacBook silhouette — lid + keyboard base.
//
// The laptop proportions stay fixed to a 16:10 MacBook display.
// The incoming screenshot is scaled with object-contain semantics so the
// laptop silhouette remains stable regardless of capture aspect ratio.
//
// All values scale proportionally from a 1440px reference screen width.
// ---------------------------------------------------------------------------

const MB_SCREEN_ASPECT = 16 / 10;

// Reference at 1440px screen width
const MB_REF_W = 1440;
const MB_REF_BEZEL_S = 26;
const MB_REF_BEZEL_T = 38;
const MB_REF_BEZEL_B = 30;
const MB_REF_LID_R = 30;
const MB_REF_SCREEN_R = 12;
const MB_REF_CAM_R = 4;
const MB_REF_CAM_HOUSING_W = 44;
const MB_REF_CAM_HOUSING_H = 12;
const MB_REF_PANEL_INSET = 10;
const MB_REF_BASE_OVERHANG = 92;
const MB_REF_BASE_H = 64;
const MB_REF_BASE_R = 18;
const MB_REF_BASE_OVERLAP = 6;
const MB_REF_BASE_TOP_INSET = 18;
const MB_REF_TRACKPAD_W = 280;
const MB_REF_TRACKPAD_H = 18;
const MB_REF_TRACKPAD_Y = 18;
const MB_REF_NOTCH_W = 88;
const MB_REF_NOTCH_H = 6;
const MB_REF_FOOT_W = 40;
const MB_REF_FOOT_H = 6;

const MB_SCREEN_COLOR = "#050506";
const MB_FOOT_COLOR = "rgba(24, 24, 26, 0.85)";

export function getMacbookFrameDimensions(screenshotWidth: number, _screenshotHeight: number): FrameDimensions {
  const scale = screenshotWidth / MB_REF_W;
  const bezelS = Math.round(MB_REF_BEZEL_S * scale);
  const bezelT = Math.round(MB_REF_BEZEL_T * scale);
  const bezelB = Math.round(MB_REF_BEZEL_B * scale);
  const overhang = Math.round(MB_REF_BASE_OVERHANG * scale);
  const baseH = Math.round(MB_REF_BASE_H * scale);
  const baseOverlap = Math.round(MB_REF_BASE_OVERLAP * scale);
  const screenHeight = Math.max(1, Math.round(screenshotWidth / MB_SCREEN_ASPECT));

  const lidWidth = screenshotWidth + bezelS * 2;
  const lidHeight = screenHeight + bezelT + bezelB;
  const totalWidth = lidWidth + overhang * 2;
  const totalHeight = lidHeight + baseH - baseOverlap;

  return {
    totalWidth,
    totalHeight,
    screenX: overhang + bezelS,
    screenY: bezelT,
    screenWidth: screenshotWidth,
    screenHeight,
  };
}

export function drawMacbookFrame(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  dims: FrameDimensions,
  screenshot: HTMLImageElement,
  backdrop: CanvasImageSource | null = null,
  screenshotPaddingPercent: number = 0
) {
  const { totalWidth, screenX, screenY, screenWidth, screenHeight } = dims;

  const scale = screenWidth / MB_REF_W;
  const bezelS = Math.round(MB_REF_BEZEL_S * scale);
  const bezelT = Math.round(MB_REF_BEZEL_T * scale);
  const bezelB = Math.round(MB_REF_BEZEL_B * scale);
  const lidR = Math.max(6, Math.round(MB_REF_LID_R * scale));
  const screenR = Math.max(4, Math.round(MB_REF_SCREEN_R * scale));
  const camR = Math.max(2, Math.round(MB_REF_CAM_R * scale));
  const camHousingW = Math.round(MB_REF_CAM_HOUSING_W * scale);
  const camHousingH = Math.max(6, Math.round(MB_REF_CAM_HOUSING_H * scale));
  const panelInset = Math.max(4, Math.round(MB_REF_PANEL_INSET * scale));
  const overhang = Math.round(MB_REF_BASE_OVERHANG * scale);
  const baseH = Math.round(MB_REF_BASE_H * scale);
  const baseR = Math.max(8, Math.round(MB_REF_BASE_R * scale));
  const baseOverlap = Math.round(MB_REF_BASE_OVERLAP * scale);
  const baseTopInset = Math.round(MB_REF_BASE_TOP_INSET * scale);
  const trackpadW = Math.round(MB_REF_TRACKPAD_W * scale);
  const trackpadH = Math.max(8, Math.round(MB_REF_TRACKPAD_H * scale));
  const trackpadY = Math.round(MB_REF_TRACKPAD_Y * scale);
  const notchW = Math.round(MB_REF_NOTCH_W * scale);
  const notchH = Math.max(3, Math.round(MB_REF_NOTCH_H * scale));
  const footW = Math.round(MB_REF_FOOT_W * scale);
  const footH = Math.max(2, Math.round(MB_REF_FOOT_H * scale));

  const lidWidth = screenWidth + bezelS * 2;
  const lidHeight = screenHeight + bezelT + bezelB;
  const lidX = x + overhang;
  const screenAbsX = x + screenX;
  const screenAbsY = y + screenY;
  const panelX = screenAbsX - panelInset;
  const panelY = screenAbsY - panelInset;
  const panelWidth = screenWidth + panelInset * 2;
  const panelHeight = screenHeight + panelInset * 2;
  const screenshotInset = Math.max(
    0,
    Math.round(
      Math.min(screenWidth, screenHeight) * (Math.min(Math.max(screenshotPaddingPercent, 0), 20) / 100)
    )
  );
  const screenshotAreaX = screenAbsX + screenshotInset;
  const screenshotAreaY = screenAbsY + screenshotInset;
  const screenshotAreaWidth = Math.max(1, screenWidth - screenshotInset * 2);
  const screenshotAreaHeight = Math.max(1, screenHeight - screenshotInset * 2);

  ctx.save();

  // ── Lid shell ──
  const lidGradient = ctx.createLinearGradient(lidX, y, lidX, y + lidHeight);
  lidGradient.addColorStop(0, "#373c42");
  lidGradient.addColorStop(0.45, "#262a30");
  lidGradient.addColorStop(1, "#1a1d21");
  ctx.beginPath();
  ctx.roundRect(lidX, y, lidWidth, lidHeight, lidR);
  ctx.fillStyle = lidGradient;
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.12)";
  ctx.lineWidth = Math.max(1, 1.25 * scale);
  ctx.stroke();

  // Inner black glass/bezel panel
  ctx.beginPath();
  ctx.roundRect(panelX, panelY, panelWidth, panelHeight, Math.max(screenR + panelInset * 0.6, screenR));
  ctx.fillStyle = "#121417";
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.05)";
  ctx.lineWidth = Math.max(1, scale);
  ctx.stroke();

  // Screen background
  ctx.beginPath();
  ctx.roundRect(screenAbsX, screenAbsY, screenWidth, screenHeight, screenR);
  ctx.fillStyle = MB_SCREEN_COLOR;
  ctx.fill();

  if (backdrop) {
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(screenAbsX, screenAbsY, screenWidth, screenHeight, screenR);
    ctx.clip();
    ctx.drawImage(
      backdrop,
      0,
      0,
      screenWidth,
      screenHeight,
      screenAbsX,
      screenAbsY,
      screenWidth,
      screenHeight
    );
    ctx.restore();
  }

  // Screenshot fit inside fixed 16:10 display
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(screenAbsX, screenAbsY, screenWidth, screenHeight, screenR);
  ctx.clip();
  const fitted = getContainFitRect(
    screenshot.width,
    screenshot.height,
    screenshotAreaX,
    screenshotAreaY,
    screenshotAreaWidth,
    screenshotAreaHeight
  );
  ctx.drawImage(screenshot, fitted.x, fitted.y, fitted.width, fitted.height);

  if (backdrop) {
    const glare = ctx.createLinearGradient(screenAbsX, screenAbsY, screenAbsX, screenAbsY + screenHeight);
    glare.addColorStop(0, "rgba(255,255,255,0.06)");
    glare.addColorStop(0.35, "rgba(255,255,255,0.015)");
    glare.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = glare;
    ctx.fillRect(screenAbsX, screenAbsY, screenWidth, screenHeight);
  }

  ctx.restore();

  // Camera housing + camera dot
  const camHousingX = lidX + (lidWidth - camHousingW) / 2;
  const camHousingY = y + Math.max(6, bezelT * 0.28);
  ctx.beginPath();
  ctx.roundRect(camHousingX, camHousingY, camHousingW, camHousingH, camHousingH / 2);
  ctx.fillStyle = "rgba(0,0,0,0.22)";
  ctx.fill();
  const camX = lidX + lidWidth / 2;
  const camY = y + bezelT * 0.46;
  ctx.beginPath();
  ctx.arc(camX, camY, camR, 0, Math.PI * 2);
  ctx.fillStyle = "#0c0d10";
  ctx.fill();
  ctx.beginPath();
  ctx.arc(camX, camY, Math.max(1, camR - 1), 0, Math.PI * 2);
  ctx.fillStyle = "rgba(122, 162, 255, 0.3)";
  ctx.fill();

  // Bottom lid highlight
  ctx.beginPath();
  ctx.moveTo(panelX + panelInset, y + lidHeight - Math.max(2, bezelB * 0.5));
  ctx.lineTo(panelX + panelWidth - panelInset, y + lidHeight - Math.max(2, bezelB * 0.5));
  ctx.strokeStyle = "rgba(255,255,255,0.08)";
  ctx.lineWidth = Math.max(1, scale);
  ctx.stroke();

  // ── Base / palm rest ──
  const baseY = y + lidHeight - baseOverlap;
  const baseGradient = ctx.createLinearGradient(x, baseY, x, baseY + baseH);
  baseGradient.addColorStop(0, "#b8c0cb");
  baseGradient.addColorStop(0.35, "#979faa");
  baseGradient.addColorStop(1, "#747d89");

  ctx.beginPath();
  ctx.roundRect(x, baseY, totalWidth, baseH, [12 * scale, 12 * scale, baseR, baseR]);
  ctx.fillStyle = baseGradient;
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.22)";
  ctx.lineWidth = Math.max(1, scale);
  ctx.stroke();

  // Deck shadow to separate lid and base
  ctx.beginPath();
  ctx.roundRect(x + baseTopInset, baseY + Math.max(3, 4 * scale), totalWidth - baseTopInset * 2, Math.max(8, baseH * 0.22), 999);
  ctx.fillStyle = "rgba(28,30,34,0.28)";
  ctx.fill();

  // Trackpad outline
  const trackpadX = x + (totalWidth - trackpadW) / 2;
  ctx.beginPath();
  ctx.roundRect(trackpadX, baseY + trackpadY, trackpadW, trackpadH, trackpadH / 2);
  ctx.strokeStyle = "rgba(70,76,84,0.55)";
  ctx.lineWidth = Math.max(1, scale);
  ctx.stroke();

  // Front opening notch
  const notchX = x + (totalWidth - notchW) / 2;
  const notchY = baseY + baseH - notchH - Math.max(4, 5 * scale);
  ctx.beginPath();
  ctx.roundRect(notchX, notchY, notchW, notchH, notchH / 2);
  ctx.fillStyle = "rgba(58, 64, 72, 0.7)";
  ctx.fill();

  // Rubber feet
  const footY = baseY + baseH - footH;
  const footInset = Math.round(footW * 0.8);
  [x + footInset, x + totalWidth - footInset - footW].forEach((fx) => {
    ctx.beginPath();
    ctx.roundRect(fx, footY, footW, footH, footH / 2);
    ctx.fillStyle = MB_FOOT_COLOR;
    ctx.fill();
  });

  ctx.restore();
}

// ---------------------------------------------------------------------------
// Unified helpers
// ---------------------------------------------------------------------------

export function getFrameDimensions(
  frameType: FrameType,
  screenshotWidth: number,
  screenshotHeight: number
): FrameDimensions | null {
  switch (frameType) {
    case "terminal": return getTerminalFrameDimensions(screenshotWidth, screenshotHeight);
    case "iphone":   return getIphoneFrameDimensions(screenshotWidth, screenshotHeight);
    case "macbook":  return getMacbookFrameDimensions(screenshotWidth, screenshotHeight);
    default:         return null;
  }
}

export function drawFrame(
  ctx: CanvasRenderingContext2D,
  frameType: FrameType,
  x: number,
  y: number,
  dims: FrameDimensions,
  screenshot: HTMLImageElement,
  backdrop: CanvasImageSource | null = null,
  screenshotPaddingPercent: number = 0
) {
  switch (frameType) {
    case "terminal": drawTerminalFrame(ctx, x, y, dims, screenshot); break;
    case "iphone":   drawIphoneFrame(ctx, x, y, dims, screenshot);   break;
    case "macbook":  drawMacbookFrame(ctx, x, y, dims, screenshot, backdrop, screenshotPaddingPercent);  break;
  }
}
