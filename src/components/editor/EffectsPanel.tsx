import { memo } from "react";
import { Slider } from "@/components/ui/slider";
import type { ShadowSettings } from "@/stores/editorStore";

interface EffectsPanelProps {
  blurAmount: number;
  noiseAmount: number;
  shadow: ShadowSettings;
  // Transient handlers (during drag) - for visual feedback
  onBlurChangeTransient?: (value: number) => void;
  onNoiseChangeTransient?: (value: number) => void;
  onShadowBlurChangeTransient?: (value: number) => void;
  onShadowOffsetXChangeTransient?: (value: number) => void;
  onShadowOffsetYChangeTransient?: (value: number) => void;
  onShadowOpacityChangeTransient?: (value: number) => void;
  // Commit handlers (on release) - for state/history
  onBlurChange: (value: number) => void;
  onNoiseChange: (value: number) => void;
  onShadowBlurChange: (value: number) => void;
  onShadowOffsetXChange: (value: number) => void;
  onShadowOffsetYChange: (value: number) => void;
  onShadowOpacityChange: (value: number) => void;
}

export const EffectsPanel = memo(function EffectsPanel({
  blurAmount,
  noiseAmount,
  shadow,
  onBlurChangeTransient,
  onNoiseChangeTransient,
  onShadowBlurChangeTransient,
  onShadowOffsetXChangeTransient,
  onShadowOffsetYChangeTransient,
  onShadowOpacityChangeTransient,
  onBlurChange,
  onNoiseChange,
  onShadowBlurChange,
  onShadowOffsetXChange,
  onShadowOffsetYChange,
  onShadowOpacityChange,
}: EffectsPanelProps) {
  return (
    <div className="space-y-6">
      {/* Background Effects */}
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
              onValueChange={(value) => onBlurChangeTransient?.(value[0])}
              onValueCommit={(value) => onBlurChange(value[0])}
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
              onValueChange={(value) => onNoiseChangeTransient?.(value[0])}
              onValueCommit={(value) => onNoiseChange(value[0])}
              min={0}
              max={100}
              step={1}
              className="w-full"
            />
          </div>
        </div>
      </div>

      {/* Shadow Effects */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-medium text-zinc-200 font-mono text-balance">Shadow</h3>
        </div>
        
        <div className="space-y-6">
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-zinc-400 font-medium">Blur</label>
              <span className="text-xs text-zinc-400 font-mono tabular-nums">{shadow.blur}px</span>
            </div>
            <Slider
              value={[shadow.blur]}
              onValueChange={(value) => onShadowBlurChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowBlurChange(value[0])}
              min={0}
              max={100}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-zinc-400 font-medium">Offset X</label>
              <span className="text-xs text-zinc-400 font-mono tabular-nums">{shadow.offsetX}px</span>
            </div>
            <Slider
              value={[shadow.offsetX]}
              onValueChange={(value) => onShadowOffsetXChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowOffsetXChange(value[0])}
              min={-50}
              max={50}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-zinc-400 font-medium">Offset Y</label>
              <span className="text-xs text-zinc-400 font-mono tabular-nums">{shadow.offsetY}px</span>
            </div>
            <Slider
              value={[shadow.offsetY]}
              onValueChange={(value) => onShadowOffsetYChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowOffsetYChange(value[0])}
              min={-50}
              max={50}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-zinc-400 font-medium">Opacity</label>
              <span className="text-xs text-zinc-400 font-mono tabular-nums">{shadow.opacity}%</span>
            </div>
            <Slider
              value={[shadow.opacity]}
              onValueChange={(value) => onShadowOpacityChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowOpacityChange(value[0])}
              min={0}
              max={100}
              step={1}
              className="w-full"
            />
          </div>
        </div>
      </div>
    </div>
  );
});
