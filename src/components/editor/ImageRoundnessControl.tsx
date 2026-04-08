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
    <div>
      <div className="toggle-row">
        <span className="toggle-label">Corner Radius</span>
        <span className="toggle-value">{borderRadius}px</span>
      </div>
      <Slider
        value={[borderRadius]}
        onValueChange={(value) => onBorderRadiusChangeTransient?.(value[0])}
        onValueCommit={(value) => onBorderRadiusChange(value[0])}
        min={0}
        max={50}
        step={1}
        className="studio-slider w-full"
      />
    </div>
  );
});
