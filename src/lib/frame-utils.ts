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
// Reference: custats-info/src/components/MobileApp.jsx
//
// Structure (inside-out):
//   outer bezel  rounded-[2.5rem]=40px,  bg-foreground/90 (~#1a1a1a)
//     p-[6px] → inner screen container  rounded-[2.2rem]=35.2px, bg-black
//       content fills screen (object-cover object-top)
//       Dynamic Island: 90×28px pill, top-3 (12px from top), centered
//       Home indicator: 30% width pill at bottom
//   Side buttons drawn outside the bezel
// ---------------------------------------------------------------------------

// Bezel thickness and radii mirror the reference CSS exactly
const IPHONE_BEZEL = 6;            // p-[6px]
const IPHONE_OUTER_RADIUS = 40;    // rounded-[2.5rem]
const IPHONE_SCREEN_RADIUS = 35;   // rounded-[2.2rem] ≈ 35.2px

// Dynamic Island: 90px wide × 28px tall, 12px from top (top-3)
const IPHONE_DI_WIDTH = 90;
const IPHONE_DI_HEIGHT = 28;
const IPHONE_DI_TOP = 12;

// Side hardware buttons (drawn outside the bezel, same dark color)
const IPHONE_BTN_W = 4;
const IPHONE_BTN_RADIUS = 2;
const IPHONE_FRAME_COLOR = "#1a1a1a"; // bg-foreground/90

// Home indicator bar
const IPHONE_INDICATOR_HEIGHT = 5;
const IPHONE_INDICATOR_BOTTOM = 14;
const IPHONE_INDICATOR_COLOR = "rgba(255,255,255,0.35)";

export function getIphoneFrameDimensions(screenshotWidth: number, screenshotHeight: number): FrameDimensions {
  // The outer body is: bezel + screen + bezel on each axis
  const totalWidth  = screenshotWidth  + IPHONE_BEZEL * 2;
  const totalHeight = screenshotHeight + IPHONE_BEZEL * 2;

  return {
    totalWidth,
    totalHeight,
    // Screen starts at top-left corner of the inner screen container
    screenX: IPHONE_BEZEL,
    screenY: IPHONE_BEZEL,
    screenWidth:  screenshotWidth,
    screenHeight: screenshotHeight,
  };
}

export function drawIphoneFrame(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  dims: FrameDimensions,
  screenshot: HTMLImageElement
) {
  const { totalWidth, totalHeight, screenX, screenY, screenWidth, screenHeight } = dims;

  ctx.save();

  // ── Side hardware buttons (drawn outside frame, same color, behind frame visually) ──

  // Volume up + volume down (left side)
  const volBtnX    = x - IPHONE_BTN_W + 1;
  const volBtn1Y   = y + totalHeight * 0.22;
  const volBtn2Y   = y + totalHeight * 0.31;
  const volBtnH    = totalHeight * 0.07;

  ctx.fillStyle = IPHONE_FRAME_COLOR;
  [volBtn1Y, volBtn2Y].forEach((by) => {
    ctx.beginPath();
    ctx.roundRect(volBtnX, by, IPHONE_BTN_W, volBtnH, IPHONE_BTN_RADIUS);
    ctx.fill();
  });

  // Power button (right side)
  const pwrBtnX = x + totalWidth - 1;
  const pwrBtnY = y + totalHeight * 0.26;
  const pwrBtnH = totalHeight * 0.10;
  ctx.beginPath();
  ctx.roundRect(pwrBtnX, pwrBtnY, IPHONE_BTN_W, pwrBtnH, IPHONE_BTN_RADIUS);
  ctx.fill();

  // ── Outer bezel: dark rounded rect ──
  ctx.beginPath();
  ctx.roundRect(x, y, totalWidth, totalHeight, IPHONE_OUTER_RADIUS);
  ctx.fillStyle = IPHONE_FRAME_COLOR;
  ctx.fill();

  // ── Screen container: black, slightly smaller radius ──
  const sx = x + IPHONE_BEZEL;
  const sy = y + IPHONE_BEZEL;

  ctx.beginPath();
  ctx.roundRect(sx, sy, screenWidth, screenHeight, IPHONE_SCREEN_RADIUS);
  ctx.fillStyle = "#000000";
  ctx.fill();

  // ── Screenshot clipped to screen shape ──
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(x + screenX, y + screenY, screenWidth, screenHeight, IPHONE_SCREEN_RADIUS);
  ctx.clip();
  ctx.drawImage(screenshot, x + screenX, y + screenY, screenWidth, screenHeight);
  ctx.restore();

  // ── Dynamic Island: 90×28px pill, 12px from top of screen, centered ──
  const diWidth  = Math.min(IPHONE_DI_WIDTH, screenWidth * 0.35);
  const diX = x + screenX + (screenWidth - diWidth) / 2;
  const diY = y + screenY + IPHONE_DI_TOP;

  ctx.beginPath();
  ctx.roundRect(diX, diY, diWidth, IPHONE_DI_HEIGHT, IPHONE_DI_HEIGHT / 2);
  ctx.fillStyle = "#000000";
  ctx.fill();

  // ── Home indicator bar ──
  const indWidth = totalWidth * 0.3;
  const indX = x + (totalWidth - indWidth) / 2;
  const indY = y + totalHeight - IPHONE_INDICATOR_BOTTOM;

  ctx.beginPath();
  ctx.roundRect(indX, indY, indWidth, IPHONE_INDICATOR_HEIGHT, IPHONE_INDICATOR_HEIGHT / 2);
  ctx.fillStyle = IPHONE_INDICATOR_COLOR;
  ctx.fill();

  ctx.restore();
}

// ---------------------------------------------------------------------------
// MacBook frame
// ---------------------------------------------------------------------------

const MACBOOK_TOP_BEZEL = 28;
const MACBOOK_SIDE_BEZEL = 20;
const MACBOOK_BOTTOM_BEZEL = 24;
const MACBOOK_LID_RADIUS = 10;
const MACBOOK_BASE_HEIGHT_RATIO = 0.065;
const MACBOOK_BASE_CORNER_RADIUS = 3;
const MACBOOK_HINGE_HEIGHT = 6;
const MACBOOK_CAMERA_RADIUS = 4;
const MACBOOK_FRAME_COLOR = "#3d3d3d";
const MACBOOK_INNER_BEZEL_COLOR = "#1a1a1a";
const MACBOOK_BASE_COLOR = "#4a4a4a";
const MACBOOK_BASE_EDGE_COLOR = "#2d2d2d";

export function getMacbookFrameDimensions(screenshotWidth: number, screenshotHeight: number): FrameDimensions {
  const lidWidth = screenshotWidth + MACBOOK_SIDE_BEZEL * 2;
  const lidHeight = screenshotHeight + MACBOOK_TOP_BEZEL + MACBOOK_BOTTOM_BEZEL;
  const baseHeight = Math.round(lidWidth * MACBOOK_BASE_HEIGHT_RATIO);

  return {
    totalWidth: lidWidth,
    totalHeight: lidHeight + MACBOOK_HINGE_HEIGHT + baseHeight,
    screenX: MACBOOK_SIDE_BEZEL,
    screenY: MACBOOK_TOP_BEZEL,
    screenWidth: screenshotWidth,
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
  const lidHeight = screenHeight + MACBOOK_TOP_BEZEL + MACBOOK_BOTTOM_BEZEL;
  const baseHeight = Math.round(totalWidth * MACBOOK_BASE_HEIGHT_RATIO);

  ctx.save();

  // ── Lid ──
  ctx.beginPath();
  ctx.roundRect(x, y, totalWidth, lidHeight, MACBOOK_LID_RADIUS);
  ctx.fillStyle = MACBOOK_FRAME_COLOR;
  ctx.fill();

  // Inner bezel (inset)
  ctx.beginPath();
  ctx.roundRect(x + 4, y + 4, totalWidth - 8, lidHeight - 8, MACBOOK_LID_RADIUS - 2);
  ctx.fillStyle = MACBOOK_INNER_BEZEL_COLOR;
  ctx.fill();

  // Screen area
  ctx.save();
  ctx.beginPath();
  ctx.rect(x + screenX, y + screenY, screenWidth, screenHeight);
  ctx.clip();
  ctx.drawImage(screenshot, x + screenX, y + screenY, screenWidth, screenHeight);
  ctx.restore();

  // Camera dot
  const cameraX = x + totalWidth / 2;
  const cameraY = y + MACBOOK_TOP_BEZEL / 2;
  ctx.beginPath();
  ctx.arc(cameraX, cameraY, MACBOOK_CAMERA_RADIUS, 0, Math.PI * 2);
  ctx.fillStyle = "#2a2a2a";
  ctx.fill();
  ctx.beginPath();
  ctx.arc(cameraX, cameraY, MACBOOK_CAMERA_RADIUS - 1.5, 0, Math.PI * 2);
  ctx.fillStyle = "#3d3d3d";
  ctx.fill();

  // ── Hinge ──
  const hingeY = y + lidHeight;
  ctx.fillStyle = MACBOOK_BASE_EDGE_COLOR;
  ctx.fillRect(x, hingeY, totalWidth, MACBOOK_HINGE_HEIGHT);

  // ── Base ──
  const baseY = hingeY + MACBOOK_HINGE_HEIGHT;
  ctx.beginPath();
  ctx.roundRect(x, baseY, totalWidth, baseHeight, MACBOOK_BASE_CORNER_RADIUS);
  ctx.fillStyle = MACBOOK_BASE_COLOR;
  ctx.fill();

  // Base edge highlight
  ctx.beginPath();
  ctx.moveTo(x, baseY + baseHeight);
  ctx.lineTo(x + totalWidth, baseY + baseHeight);
  ctx.strokeStyle = MACBOOK_BASE_EDGE_COLOR;
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
