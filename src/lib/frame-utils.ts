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
// Structure:
//   Lid (top part):
//     Outer shell — dark (#1e1e1e), small rounded corners
//     Thin bezel around screen: ~12px sides/bottom, ~24px top for camera
//     Screen — screenshot fills it, sharp corners
//     Camera dot — centered in top bezel
//     Bottom chin of lid — thin flat bar below screen
//   Base (keyboard body):
//     Wider than lid — extends ~30px beyond lid on each side
//     Flat rectangle, same dark color, slightly rounded bottom corners
//     Thin inner platform inside base (keyboard deck, slightly inset)
//     Small rubber feet at bottom corners
//
// All values scale proportionally from a 1280px reference screen width.
// ---------------------------------------------------------------------------

// Reference at 1280px screen width
const MB_REF_W        = 1280;
const MB_REF_BEZEL_S  = 20;    // side bezel
const MB_REF_BEZEL_T  = 36;    // top bezel (camera area)
const MB_REF_BEZEL_B  = 20;    // bottom bezel (chin below screen)
const MB_REF_LID_R    = 40;    // lid outer corner radius — large, prominent
const MB_REF_SCREEN_R = 6;     // screen inner corner radius (subtle)
const MB_REF_CAM_R    = 4;     // camera dot radius
const MB_REF_BASE_OVERHANG = 60; // base wider than lid on each side
const MB_REF_BASE_H   = 70;    // base height (keyboard body)
const MB_REF_BASE_R   = 8;     // base bottom corner radius
const MB_REF_FOOT_W   = 28;    // rubber foot width
const MB_REF_FOOT_H   = 5;     // rubber foot height

const MB_LID_COLOR    = "#2a2a2a";
const MB_SCREEN_COLOR = "#000000";
const MB_BASE_COLOR   = "#1e1e1e";
const MB_FOOT_COLOR   = "#141414";

export function getMacbookFrameDimensions(screenshotWidth: number, screenshotHeight: number): FrameDimensions {
  const s        = screenshotWidth / MB_REF_W;
  const bezelS   = Math.round(MB_REF_BEZEL_S * s);
  const bezelT   = Math.round(MB_REF_BEZEL_T * s);
  const bezelB   = Math.round(MB_REF_BEZEL_B * s);
  const overhang = Math.round(MB_REF_BASE_OVERHANG * s);
  const baseH    = Math.round(MB_REF_BASE_H * s);

  const lidWidth    = screenshotWidth + bezelS * 2;
  const lidHeight   = screenshotHeight + bezelT + bezelB;
  const totalWidth  = lidWidth + overhang * 2;
  const totalHeight = lidHeight + baseH;

  return {
    totalWidth,
    totalHeight,
    screenX: overhang + bezelS,
    screenY: bezelT,
    screenWidth:  screenshotWidth,
    screenHeight: screenshotHeight,
  };
}

export function drawMacbookFrame(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  dims: FrameDimensions,
  screenshot: HTMLImageElement
) {
  const { totalWidth, screenX, screenY, screenWidth, screenHeight } = dims;

  const s        = screenWidth / MB_REF_W;
  const bezelS   = Math.round(MB_REF_BEZEL_S  * s);
  const bezelT   = Math.round(MB_REF_BEZEL_T  * s);
  const bezelB   = Math.round(MB_REF_BEZEL_B  * s);
  const lidR     = Math.max(4, Math.round(MB_REF_LID_R    * s));
  const screenR  = Math.max(2, Math.round(MB_REF_SCREEN_R * s));
  const camR     = Math.max(2, Math.round(MB_REF_CAM_R    * s));
  const overhang = Math.round(MB_REF_BASE_OVERHANG * s);
  const baseH    = Math.round(MB_REF_BASE_H    * s);
  const baseR    = Math.max(2, Math.round(MB_REF_BASE_R   * s));
  const footW    = Math.round(MB_REF_FOOT_W    * s);
  const footH    = Math.max(2, Math.round(MB_REF_FOOT_H   * s));

  const lidWidth  = screenWidth + bezelS * 2;
  const lidHeight = screenHeight + bezelT + bezelB;
  const lidX      = x + overhang;

  ctx.save();

  // ── Base (keyboard body) — drawn first, lid sits on top ──
  const baseY = y + lidHeight;
  ctx.beginPath();
  ctx.roundRect(x, baseY, totalWidth, baseH, [0, 0, baseR, baseR]);
  ctx.fillStyle = MB_BASE_COLOR;
  ctx.fill();

  // Rubber feet
  const footY      = baseY + baseH - footH;
  const footInset  = Math.round(footW * 0.6);
  [x + footInset, x + totalWidth - footInset - footW].forEach((fx) => {
    ctx.beginPath();
    ctx.roundRect(fx, footY, footW, footH, footH / 2);
    ctx.fillStyle = MB_FOOT_COLOR;
    ctx.fill();
  });

  // ── Lid shell — large rounded corners ──
  ctx.beginPath();
  ctx.roundRect(lidX, y, lidWidth, lidHeight, lidR);
  ctx.fillStyle = MB_LID_COLOR;
  ctx.fill();

  // ── Screen: black fill + screenshot, clipped with subtle rounded corners ──
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(x + screenX, y + screenY, screenWidth, screenHeight, screenR);
  ctx.fillStyle = MB_SCREEN_COLOR;
  ctx.fill();
  ctx.clip();
  ctx.drawImage(screenshot, x + screenX, y + screenY, screenWidth, screenHeight);
  ctx.restore();

  // ── Camera dot — centred in top bezel ──
  const camX = lidX + lidWidth / 2;
  const camY = y + bezelT / 2;
  ctx.beginPath();
  ctx.arc(camX, camY, camR, 0, Math.PI * 2);
  ctx.fillStyle = "#3a3a3a";
  ctx.fill();
  ctx.beginPath();
  ctx.arc(camX, camY, Math.max(1, camR - 1), 0, Math.PI * 2);
  ctx.fillStyle = "#111111";
  ctx.fill();

  // ── Hinge shadow line ──
  ctx.beginPath();
  ctx.moveTo(x, y + lidHeight);
  ctx.lineTo(x + totalWidth, y + lidHeight);
  ctx.strokeStyle = "rgba(0,0,0,0.6)";
  ctx.lineWidth = 2;
  ctx.stroke();

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
  screenshot: HTMLImageElement
) {
  switch (frameType) {
    case "terminal": drawTerminalFrame(ctx, x, y, dims, screenshot); break;
    case "iphone":   drawIphoneFrame(ctx, x, y, dims, screenshot);   break;
    case "macbook":  drawMacbookFrame(ctx, x, y, dims, screenshot);  break;
  }
}
