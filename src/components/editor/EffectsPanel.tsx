import { Slider } from "@/components/ui/slider";

interface EffectsPanelProps {
  blurAmount: number;
  noiseAmount: number;
  onBlurChange: (value: number) => void;
  onNoiseChange: (value: number) => void;
}

export function EffectsPanel({
  blurAmount,
  noiseAmount,
  onBlurChange,
  onNoiseChange,
}: EffectsPanelProps) {
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-zinc-200 font-mono text-balance">Background Effects</h3>
      </div>
      
      <div className="space-y-6">
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <label className="text-xs text-zinc-400 font-medium">Blur</label>
            <span className="text-xs text-zinc-400 font-mono tabular-nums">{blurAmount}px</span>
          </div>
          <Slider
            value={[blurAmount]}
            onValueChange={(value) => onBlurChange(value[0])}
            min={0}
            max={100}
            step={1}
            className="w-full"
          />
        </div>

        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <label className="text-xs text-zinc-400 font-medium">Noise</label>
            <span className="text-xs text-zinc-400 font-mono tabular-nums">{noiseAmount}%</span>
          </div>
          <Slider
            value={[noiseAmount]}
            onValueChange={(value) => onNoiseChange(value[0])}
            min={0}
            max={100}
            step={1}
            className="w-full"
          />
        </div>
      </div>
    </div>
  );
}
