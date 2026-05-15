import { memo } from "react";
import { Slider } from "@/components/ui/slider";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { ExportFormat } from "@/lib/export-image";

interface ExportPanelProps {
  format: ExportFormat;
  quality: number;
  scalePercent: number;
  outputWidth: number;
  outputHeight: number;
  onFormatChange: (format: ExportFormat) => void;
  onQualityChange: (quality: number) => void;
  onScalePercentChange: (scalePercent: number) => void;
}

function clampExportScale(value: number) {
  return Math.min(Math.max(Math.round(value), 10), 300);
}

function clampQuality(value: number) {
  return Math.min(Math.max(Math.round(value), 1), 100);
}

export const ExportPanel = memo(function ExportPanel({
  format,
  quality,
  scalePercent,
  outputWidth,
  outputHeight,
  onFormatChange,
  onQualityChange,
  onScalePercentChange,
}: ExportPanelProps) {
  const handleScaleInputChange = (value: string) => {
    const numericValue = Number(value);
    if (Number.isFinite(numericValue)) {
      onScalePercentChange(clampExportScale(numericValue));
    }
  };

  const handleQualityInputChange = (value: string) => {
    const numericValue = Number(value);
    if (Number.isFinite(numericValue)) {
      onQualityChange(clampQuality(numericValue));
    }
  };

  return (
    <div className="space-y-4 border-t border-border pt-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-foreground font-mono text-balance">Export</h3>
        <span className="text-xs text-muted-foreground font-mono tabular-nums">
          {outputWidth} x {outputHeight}
        </span>
      </div>

      <div className="space-y-3">
        <label className="text-xs text-muted-foreground font-medium">Format</label>
        <div className="grid grid-cols-2 gap-2" role="group" aria-label="Export format">
          {(["png", "jpeg"] as const).map((option) => (
            <Button
              key={option}
              type="button"
              variant={format === option ? "secondary" : "ghost"}
              size="sm"
              aria-pressed={format === option}
              className={cn(
                "h-8 rounded-md text-xs font-medium",
                format === option && "border border-border",
              )}
              onClick={() => onFormatChange(option)}
            >
              {option === "png" ? "PNG" : "JPEG"}
            </Button>
          ))}
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between gap-3">
          <label htmlFor="export-scale" className="text-xs text-muted-foreground font-medium">
            Scale
          </label>
          <div className="flex items-center gap-1">
            <input
              id="export-scale"
              type="number"
              min={10}
              max={300}
              step={1}
              value={scalePercent}
              onChange={(event) => handleScaleInputChange(event.target.value)}
              className="h-7 w-16 rounded-md border border-border bg-background px-2 text-right text-xs text-foreground tabular-nums outline-none focus:border-ring focus:ring-2 focus:ring-ring/50"
              aria-label="Export scale percent"
            />
            <span className="text-xs text-muted-foreground">%</span>
          </div>
        </div>
        <Slider
          value={[scalePercent]}
          onValueChange={(value) => onScalePercentChange(value[0])}
          min={10}
          max={300}
          step={1}
          className="w-full"
          aria-label="Export scale"
        />
      </div>

      <div className={cn("space-y-3", format === "png" && "opacity-50")}>
        <div className="flex items-center justify-between gap-3">
          <label htmlFor="export-quality" className="text-xs text-muted-foreground font-medium">
            Quality
          </label>
          <div className="flex items-center gap-1">
            <input
              id="export-quality"
              type="number"
              min={1}
              max={100}
              step={1}
              value={quality}
              disabled={format === "png"}
              onChange={(event) => handleQualityInputChange(event.target.value)}
              className="h-7 w-16 rounded-md border border-border bg-background px-2 text-right text-xs text-foreground tabular-nums outline-none focus:border-ring focus:ring-2 focus:ring-ring/50 disabled:cursor-not-allowed"
              aria-label="JPEG export quality"
            />
            <span className="text-xs text-muted-foreground">%</span>
          </div>
        </div>
        <Slider
          value={[quality]}
          onValueChange={(value) => onQualityChange(value[0])}
          min={1}
          max={100}
          step={1}
          disabled={format === "png"}
          className="w-full disabled:cursor-not-allowed"
          aria-label="JPEG export quality"
        />
        {format === "png" && (
          <p className="text-xs text-muted-foreground text-pretty">
            PNG exports are lossless, so quality is only used for JPEG.
          </p>
        )}
      </div>
    </div>
  );
});
