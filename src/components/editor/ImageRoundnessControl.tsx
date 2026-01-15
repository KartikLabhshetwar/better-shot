import { memo } from "react";
import { Slider } from "@/components/ui/slider";

interface ImageRoundnessControlProps {
  borderRadius: number;
  onBorderRadiusChangeTransient?: (value: number) => void;
  onBorderRadiusChange: (value: number) => void;
}

export const ImageRoundnessControl = memo(function ImageRoundnessControl({
  borderRadius,
  onBorderRadiusChangeTransient,
  onBorderRadiusChange,
}: ImageRoundnessControlProps) {
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-foreground font-mono text-balance">Image Roundness</h3>
      </div>
      
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <label className="text-xs text-muted-foreground font-medium">Corner Radius</label>
          <span className="text-xs text-muted-foreground font-mono tabular-nums">{borderRadius}px</span>
        </div>
        <Slider
          value={[borderRadius]}
          onValueChange={(value) => onBorderRadiusChangeTransient?.(value[0])}
          onValueCommit={(value) => onBorderRadiusChange(value[0])}
          min={0}
          max={50}
          step={1}
          className="w-full"
        />
        <p className="text-xs text-foreground0 text-pretty">Adjust corner roundness of the image</p>
      </div>
    </div>
  );
});
