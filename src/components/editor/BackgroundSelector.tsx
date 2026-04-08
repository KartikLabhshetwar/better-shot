import { memo } from "react";
import { cn } from "@/lib/utils";
import mesh1 from "@/assets/mesh/mesh1.webp";
import mesh2 from "@/assets/mesh/mesh2.webp";
import mesh3 from "@/assets/mesh/mesh3.webp";
import mesh4 from "@/assets/mesh/mesh4.webp";
import mesh5 from "@/assets/mesh/mesh5.webp";
import mesh6 from "@/assets/mesh/mesh6.webp";
import mesh7 from "@/assets/mesh/mesh7.webp";
import mesh8 from "@/assets/mesh/mesh8.webp";

type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom";

interface GradientOption {
  id: string;
  name: string;
  src: string;
  colors: [string, string];
}

const gradientOptions: GradientOption[] = [
  { id: "mesh-1", name: "Iris",    src: mesh1, colors: ["#667eea", "#764ba2"] },
  { id: "mesh-2", name: "Ocean",   src: mesh2, colors: ["#0093E9", "#80D0C7"] },
  { id: "mesh-3", name: "Rose",    src: mesh3, colors: ["#f093fb", "#f5576c"] },
  { id: "mesh-4", name: "Mint",    src: mesh4, colors: ["#11998e", "#38ef7d"] },
  { id: "mesh-5", name: "Sunset",  src: mesh5, colors: ["#fa709a", "#fee140"] },
  { id: "mesh-6", name: "Neon",    src: mesh6, colors: ["#2E3192", "#1BFFFF"] },
  { id: "mesh-7", name: "Peach",   src: mesh7, colors: ["#ffecd2", "#fcb69f"] },
  { id: "mesh-8", name: "Void",    src: mesh8, colors: ["#0f0c29", "#24243e"] },
];

interface SolidOption {
  type: BackgroundType;
  label: string;
  bg: string;
  checkerboard?: boolean;
}

const solidOptions: SolidOption[] = [
  { type: "white",       label: "White",       bg: "#ffffff" },
  { type: "black",       label: "Black",       bg: "#000000" },
  { type: "gray",        label: "Silver",      bg: "#f5f5f5" },
  { type: "transparent", label: "Clear",       bg: "transparent", checkerboard: true },
];

interface BackgroundSelectorProps {
  backgroundType: BackgroundType;
  customColor: string;
  selectedGradient?: string;
  expanded?: boolean;
  onBackgroundTypeChange: (type: BackgroundType) => void;
  onCustomColorChange: (color: string) => void;
  onGradientSelect?: (gradient: GradientOption) => void;
  onToggle?: () => void;
}

export const BackgroundSelector = memo(function BackgroundSelector({
  backgroundType,
  customColor,
  selectedGradient,
  onBackgroundTypeChange,
  onCustomColorChange,
  onGradientSelect,
}: BackgroundSelectorProps) {
  return (
    <div>
      {/* ── Solid colors ── */}
      <div className="section-header" style={{ paddingTop: 0 }}>
        <span className="section-title">Solid</span>
      </div>
      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
        {solidOptions.map(({ type, label, bg, checkerboard }) => {
          const isActive = backgroundType === type;
          return (
            <button
              key={type}
              onClick={() => onBackgroundTypeChange(type)}
              aria-label={`${label} background`}
              title={label}
              className={cn("color-swatch", checkerboard && "checkerboard", isActive && "selected")}
              style={!checkerboard ? { background: bg } : undefined}
            />
          );
        })}

        {/* Custom color */}
        <div style={{ position: 'relative' }}>
          <button
            onClick={() => onBackgroundTypeChange("custom")}
            aria-label="Custom color"
            title="Custom"
            className={cn("color-swatch", backgroundType === "custom" && "selected")}
            style={{ background: customColor }}
          />
          <input
            type="color"
            value={customColor}
            onChange={(e) => {
              onCustomColorChange(e.target.value);
              onBackgroundTypeChange("custom");
            }}
            style={{
              position: 'absolute', inset: 0,
              opacity: 0, cursor: 'pointer',
              width: '100%', height: '100%',
            }}
            aria-label="Pick custom color"
          />
        </div>
      </div>

      {/* Custom color hex display */}
      {backgroundType === "custom" && (
        <div style={{ marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: 20, height: 20, borderRadius: 4,
            background: customColor,
            border: '1px solid oklch(0.32 0.009 250)',
            flexShrink: 0,
          }} />
          <span style={{
            fontFamily: 'var(--font-mono)',
            fontSize: 11,
            color: 'oklch(0.60 0.01 250)',
            textTransform: 'uppercase',
          }}>{customColor}</span>
        </div>
      )}

      {/* ── Gradients ── */}
      <div className="section-header">
        <span className="section-title">Gradients</span>
      </div>
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(4, 1fr)',
        gap: 6,
        marginBottom: 8,
      }}>
        {gradientOptions.map((gradient) => {
          const isSelected = backgroundType === "gradient" && selectedGradient === gradient.id;
          return (
            <button
              key={gradient.id}
              onClick={() => {
                onBackgroundTypeChange("gradient");
                onGradientSelect?.(gradient);
              }}
              aria-label={gradient.name}
              title={gradient.name}
              className={cn("gradient-thumb", isSelected && "selected")}
              style={{ position: 'relative' }}
            >
              <img
                src={gradient.src}
                alt={gradient.name}
                style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
              />
              {isSelected && (
                <div style={{
                  position: 'absolute', inset: 0,
                  background: 'oklch(0.65 0.18 255 / 0.25)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
});

export { gradientOptions };
export type { GradientOption };
