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
// ---------------------------------------------------------------------------

const IPHONE_HORIZONTAL_BEZEL = 20;
const IPHONE_TOP_BEZEL = 50;
const IPHONE_BOTTOM_BEZEL = 56;
const IPHONE_OUTER_RADIUS = 46;
const IPHONE_INNER_RADIUS = 14;
const IPHONE_NOTCH_WIDTH_RATIO = 0.32;
const IPHONE_NOTCH_HEIGHT = 28;
const IPHONE_BUTTON_WIDTH = 4;
const IPHONE_FRAME_COLOR = "#1a1a1a";
const IPHONE_BEZEL_INNER = "#111111";
const IPHONE_HOME_INDICATOR_COLOR = "rgba(255,255,255,0.35)";

export function getIphoneFrameDimensions(screenshotWidth: number, screenshotHeight: number): FrameDimensions {
  return {
    totalWidth: screenshotWidth + IPHONE_HORIZONTAL_BEZEL * 2,
    totalHeight: screenshotHeight + IPHONE_TOP_BEZEL + IPHONE_BOTTOM_BEZEL,
    screenX: IPHONE_HORIZONTAL_BEZEL,
    screenY: IPHONE_TOP_BEZEL,
    screenWidth: screenshotWidth,
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

  // Outer iPhone body (main frame color)
  ctx.beginPath();
  ctx.roundRect(x, y, totalWidth, totalHeight, IPHONE_OUTER_RADIUS);
  ctx.fillStyle = IPHONE_FRAME_COLOR;
  ctx.fill();

  // Side volume buttons (left side, 2 buttons)
  const volBtnX = x - IPHONE_BUTTON_WIDTH + 1;
  const volBtn1Y = y + totalHeight * 0.22;
  const volBtn2Y = y + totalHeight * 0.31;
  const volBtnH = totalHeight * 0.07;
  const volBtnRadius = IPHONE_BUTTON_WIDTH / 2;

  ctx.fillStyle = IPHONE_FRAME_COLOR;
  ctx.beginPath();
  ctx.roundRect(volBtnX, volBtn1Y, IPHONE_BUTTON_WIDTH, volBtnH, volBtnRadius);
  ctx.fill();
  ctx.beginPath();
  ctx.roundRect(volBtnX, volBtn2Y, IPHONE_BUTTON_WIDTH, volBtnH, volBtnRadius);
  ctx.fill();

  // Power button (right side)
  const powerBtnX = x + totalWidth - 1;
  const powerBtnY = y + totalHeight * 0.26;
  const powerBtnH = totalHeight * 0.10;
  ctx.beginPath();
  ctx.roundRect(powerBtnX, powerBtnY, IPHONE_BUTTON_WIDTH, powerBtnH, volBtnRadius);
  ctx.fill();

  // Inner bezel (the inset black area)
  ctx.beginPath();
  ctx.roundRect(
    x + 3,
    y + 3,
    totalWidth - 6,
    totalHeight - 6,
    IPHONE_OUTER_RADIUS - 3
  );
  ctx.fillStyle = IPHONE_BEZEL_INNER;
  ctx.fill();

  // Clip to inner rounded rect for screen + chrome
  ctx.beginPath();
  ctx.roundRect(
    x + IPHONE_HORIZONTAL_BEZEL - 6,
    y + IPHONE_TOP_BEZEL - 6,
    screenWidth + 12,
    screenHeight + 12,
    IPHONE_INNER_RADIUS
  );
  ctx.fillStyle = "#000";
  ctx.fill();

  // Screenshot
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(x + screenX, y + screenY, screenWidth, screenHeight, IPHONE_INNER_RADIUS);
  ctx.clip();
  ctx.drawImage(screenshot, x + screenX, y + screenY, screenWidth, screenHeight);
  ctx.restore();

  // Dynamic Island / notch (centered at top)
  const notchWidth = totalWidth * IPHONE_NOTCH_WIDTH_RATIO;
  const notchX = x + (totalWidth - notchWidth) / 2;
  const notchY = y + IPHONE_TOP_BEZEL - IPHONE_NOTCH_HEIGHT - 2;
  ctx.beginPath();
  ctx.roundRect(notchX, notchY, notchWidth, IPHONE_NOTCH_HEIGHT, IPHONE_NOTCH_HEIGHT / 2);
  ctx.fillStyle = "#000";
  ctx.fill();

  // Home indicator bar at bottom
  const indicatorWidth = totalWidth * 0.3;
  const indicatorX = x + (totalWidth - indicatorWidth) / 2;
  const indicatorY = y + totalHeight - 18;
  ctx.beginPath();
  ctx.roundRect(indicatorX, indicatorY, indicatorWidth, 5, 2.5);
  ctx.fillStyle = IPHONE_HOME_INDICATOR_COLOR;
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
