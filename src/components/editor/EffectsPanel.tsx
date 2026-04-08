import { memo } from "react";
import { Slider } from "@/components/ui/slider";
import type { ShadowSettings } from "@/stores/editorStore";

interface EffectsPanelProps {
  noiseAmount: number;
  padding: number;
  shadow: ShadowSettings;
  noiseExpanded?: boolean;
  shadowExpanded?: boolean;
  onNoiseChangeTransient?: (value: number) => void;
  onPaddingChangeTransient?: (value: number) => void;
  onShadowBlurChangeTransient?: (value: number) => void;
  onShadowOffsetXChangeTransient?: (value: number) => void;
  onShadowOffsetYChangeTransient?: (value: number) => void;
  onShadowOpacityChangeTransient?: (value: number) => void;
  onNoiseChange: (value: number) => void;
  onPaddingChange: (value: number) => void;
  onShadowBlurChange: (value: number) => void;
  onShadowOffsetXChange: (value: number) => void;
  onShadowOffsetYChange: (value: number) => void;
  onShadowOpacityChange: (value: number) => void;
  onNoiseToggle?: () => void;
  onShadowToggle?: () => void;
}

function SliderRow({
  label,
  value,
  unit = "px",
  min,
  max,
  step = 1,
  onChangeTransient,
  onChange,
}: {
  label: string;
  value: number;
  unit?: string;
  min: number;
  max: number;
  step?: number;
  onChangeTransient?: (v: number) => void;
  onChange: (v: number) => void;
}) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div className="toggle-row" style={{ marginBottom: 6 }}>
        <span className="toggle-label">{label}</span>
        <span className="toggle-value">{value}{unit}</span>
      </div>
      <Slider
        value={[value]}
        onValueChange={(v) => onChangeTransient?.(v[0])}
        onValueCommit={(v) => onChange(v[0])}
        min={min}
        max={max}
        step={step}
        className="studio-slider w-full"
      />
    </div>
  );
}

export const EffectsPanel = memo(function EffectsPanel({
  noiseAmount,
  padding,
  shadow,
  onNoiseChangeTransient,
  onPaddingChangeTransient,
  onShadowBlurChangeTransient,
  onShadowOffsetXChangeTransient,
  onShadowOffsetYChangeTransient,
  onShadowOpacityChangeTransient,
  onNoiseChange,
  onPaddingChange,
  onShadowBlurChange,
  onShadowOffsetXChange,
  onShadowOffsetYChange,
  onShadowOpacityChange,
}: EffectsPanelProps) {
  return (
    <div>
      {/* Padding */}
      <div className="section-header">
        <span className="section-title">Border</span>
      </div>
      <SliderRow
        label="Padding"
        value={padding}
        min={0}
        max={200}
        onChangeTransient={onPaddingChangeTransient}
        onChange={onPaddingChange}
      />

      <hr className="panel-divider" />

      {/* Noise */}
      <div className="section-header">
        <span className="section-title">Noise</span>
      </div>
      <SliderRow
        label="Amount"
        value={noiseAmount}
        unit="%"
        min={0}
        max={100}
        onChangeTransient={onNoiseChangeTransient}
        onChange={onNoiseChange}
      />

      <hr className="panel-divider" />

      {/* Shadow */}
      <div className="section-header">
        <span className="section-title">Shadow</span>
      </div>
      <SliderRow
        label="Blur"
        value={shadow.blur}
        min={0}
        max={100}
        onChangeTransient={onShadowBlurChangeTransient}
        onChange={onShadowBlurChange}
      />
      <SliderRow
        label="Offset X"
        value={shadow.offsetX}
        min={-50}
        max={50}
        onChangeTransient={onShadowOffsetXChangeTransient}
        onChange={onShadowOffsetXChange}
      />
      <SliderRow
        label="Offset Y"
        value={shadow.offsetY}
        min={-50}
        max={50}
        onChangeTransient={onShadowOffsetYChangeTransient}
        onChange={onShadowOffsetYChange}
      />
      <SliderRow
        label="Opacity"
        value={shadow.opacity}
        unit="%"
        min={0}
        max={100}
        onChangeTransient={onShadowOpacityChangeTransient}
        onChange={onShadowOpacityChange}
      />
    </div>
  );
});
