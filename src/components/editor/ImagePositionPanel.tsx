import { memo, useCallback, useMemo } from "react";
import { RotateCcw } from "lucide-react";
import { calculateOffsetLimits } from "@/lib/canvas-utils";
import type { ImageOffset, ImageScalingMode } from "@/stores/editorStore";

interface ImagePositionPanelProps {
  imageOffset: ImageOffset;
  screenshotWidth: number;
  screenshotHeight: number;
  backgroundWidth: number;
  backgroundHeight: number;
  imageScalingMode?: ImageScalingMode;
  expanded?: boolean;
  onOffsetXChange: (offsetX: number) => void;
  onOffsetYChange: (offsetY: number) => void;
  onReset: () => void;
  onToggle?: () => void;
}

export const ImagePositionPanel = memo(function ImagePositionPanel({
  imageOffset,
  screenshotWidth,
  screenshotHeight,
  backgroundWidth,
  backgroundHeight,
  imageScalingMode = "none",
  onOffsetXChange,
  onOffsetYChange,
  onReset,
}: ImagePositionPanelProps) {
  const offsetLimits = useMemo(
    () => calculateOffsetLimits(screenshotWidth, screenshotHeight, backgroundWidth, backgroundHeight),
    [screenshotWidth, screenshotHeight, backgroundWidth, backgroundHeight]
  );

  const canReposition =
    imageScalingMode === "cover" ||
    (screenshotWidth > backgroundWidth || screenshotHeight > backgroundHeight);

  const handleOffsetXInput = useCallback((value: string) => {
    const num = parseInt(value, 10);
    if (!isNaN(num)) {
      const clamped = Math.max(offsetLimits.minOffsetX, Math.min(offsetLimits.maxOffsetX, num));
      onOffsetXChange(clamped);
    }
  }, [onOffsetXChange, offsetLimits]);

  const handleOffsetYInput = useCallback((value: string) => {
    const num = parseInt(value, 10);
    if (!isNaN(num)) {
      const clamped = Math.max(offsetLimits.minOffsetY, Math.min(offsetLimits.maxOffsetY, num));
      onOffsetYChange(clamped);
    }
  }, [onOffsetYChange, offsetLimits]);

  if (!canReposition) {
    return null;
  }

  return (
    <div>
      {/* Tip */}
      <div style={{
        padding: '8px 10px',
        background: 'oklch(0.19 0.009 250)',
        border: '1px solid oklch(0.26 0.009 250)',
        borderRadius: 6,
        fontSize: 11,
        color: 'oklch(0.55 0.01 250)',
        marginBottom: 16,
        lineHeight: 1.5,
      }}>
        Hold <kbd style={{
          background: 'oklch(0.22 0.009 250)',
          border: '1px solid oklch(0.30 0.009 250)',
          borderRadius: 3, padding: '1px 5px', fontSize: 10,
          fontFamily: 'var(--font-mono)',
        }}>Alt</kbd> and drag on the canvas to reposition
      </div>

      <div className="section-header" style={{ paddingTop: 0 }}>
        <span className="section-title">Offset</span>
        <button
          onClick={onReset}
          style={{
            display: 'flex', alignItems: 'center', gap: 4,
            fontSize: 10, color: 'oklch(0.48 0.012 250)',
            background: 'none', border: 'none', cursor: 'pointer',
          }}
        >
          <RotateCcw className="size-3" />
          Reset
        </button>
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 10, color: 'oklch(0.42 0.009 250)', marginBottom: 4 }}>X</div>
          <input
            type="number"
            value={imageOffset.x}
            onChange={(e) => handleOffsetXInput(e.target.value)}
            min={offsetLimits.minOffsetX}
            max={offsetLimits.maxOffsetX}
            className="studio-input"
          />
          <div style={{ fontSize: 10, color: 'oklch(0.35 0.009 250)', marginTop: 3, fontFamily: 'var(--font-mono)' }}>
            {Math.round(offsetLimits.minOffsetX)} to {Math.round(offsetLimits.maxOffsetX)}
          </div>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 10, color: 'oklch(0.42 0.009 250)', marginBottom: 4 }}>Y</div>
          <input
            type="number"
            value={imageOffset.y}
            onChange={(e) => handleOffsetYInput(e.target.value)}
            min={offsetLimits.minOffsetY}
            max={offsetLimits.maxOffsetY}
            className="studio-input"
          />
          <div style={{ fontSize: 10, color: 'oklch(0.35 0.009 250)', marginTop: 3, fontFamily: 'var(--font-mono)' }}>
            {Math.round(offsetLimits.minOffsetY)} to {Math.round(offsetLimits.maxOffsetY)}
          </div>
        </div>
      </div>
    </div>
  );
});
