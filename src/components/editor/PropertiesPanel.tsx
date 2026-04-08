import { useState, useEffect, memo } from "react";
import { Slider } from "@/components/ui/slider";
import { Annotation, LineType, ArrowType } from "@/types/annotations";

const stopPropagation = (e: React.KeyboardEvent) => e.stopPropagation();

interface PropertiesPanelProps {
  annotation: Annotation | null;
  onUpdate: (annotation: Annotation) => void;
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ fontSize: 10, color: 'oklch(0.42 0.009 250)', marginBottom: 5, fontWeight: 500, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
        {label}
      </div>
      {children}
    </div>
  );
}

function SliderWithValue({
  value,
  min,
  max,
  step = 1,
  onChange,
  unit = "",
}: {
  value: number;
  min: number;
  max: number;
  step?: number;
  onChange: (v: number) => void;
  unit?: string;
}) {
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      <Slider
        value={[value]}
        onValueChange={([v]) => onChange(v)}
        min={min} max={max} step={step}
        className="studio-slider"
        style={{ flex: 1 }}
      />
      <span style={{
        fontSize: 11, fontFamily: 'var(--font-mono)',
        color: 'oklch(0.55 0.01 250)', minWidth: 32, textAlign: 'right',
      }}>
        {value}{unit}
      </span>
    </div>
  );
}

export const PropertiesPanel = memo(function PropertiesPanel({ annotation, onUpdate }: PropertiesPanelProps) {
  const [, setExpandedSections] = useState<Set<string>>(new Set(["fill", "border"]));

  useEffect(() => {
    if (!annotation) return;
    const sections = new Set(["fill", "border"]);
    if (annotation.type === "text") sections.add("text");
    if (annotation.type === "line" || annotation.type === "arrow") sections.add("line");
    if (annotation.type === "number") sections.add("number");
    if (annotation.type === "blur") { sections.add("blur"); sections.delete("fill"); sections.delete("border"); }
    setExpandedSections(sections);
  }, [annotation?.type, annotation?.id]);

  if (!annotation) return null;

  const updateAnnotation = (updates: Partial<Annotation>) => {
    onUpdate({ ...annotation, ...updates } as Annotation);
  };

  const handleColorChange = (type: "fill" | "border", hex: string) => {
    if (type === "fill") {
      updateAnnotation({ fill: { ...annotation.fill, hex } });
    } else {
      updateAnnotation({ border: { ...annotation.border, color: { ...annotation.border.color, hex } } });
    }
  };

  const handleOpacityChange = (type: "fill" | "border", opacity: number) => {
    if (type === "fill") {
      updateAnnotation({ fill: { ...annotation.fill, opacity } });
    } else {
      updateAnnotation({ border: { ...annotation.border, color: { ...annotation.border.color, opacity } } });
    }
  };

  const inputStyle: React.CSSProperties = {
    width: '100%',
    padding: '5px 8px',
    background: 'oklch(0.175 0.008 250)',
    border: '1px solid oklch(0.26 0.009 250)',
    borderRadius: 5,
    fontSize: 12,
    color: 'oklch(0.85 0.008 250)',
    outline: 'none',
    fontFamily: 'var(--font-sans)',
  };

  const selectStyle: React.CSSProperties = {
    ...inputStyle,
    cursor: 'pointer',
    appearance: 'none' as any,
    WebkitAppearance: 'none',
    backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='10' viewBox='0 0 24 24' fill='none' stroke='%23666' stroke-width='2'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E")`,
    backgroundRepeat: 'no-repeat',
    backgroundPosition: 'right 8px center',
    paddingRight: 24,
  };

  return (
    <div>
      {/* Blur */}
      {annotation.type === "blur" && (
        <Row label="Blur Intensity">
          <SliderWithValue
            value={annotation.blurAmount}
            min={1} max={50}
            onChange={(v) => updateAnnotation({ blurAmount: v })}
          />
        </Row>
      )}

      {/* Text */}
      {annotation.type === "text" && (
        <>
          <Row label="Content">
            <textarea
              value={annotation.text}
              onChange={(e) => updateAnnotation({ text: e.target.value })}
              onFocus={(e) => e.target.select()}
              onKeyDown={stopPropagation}
              style={{ ...inputStyle, resize: 'none', lineHeight: 1.4 }}
              rows={2}
              placeholder="Enter text…"
              autoFocus
            />
          </Row>
          <Row label="Font Size">
            <SliderWithValue
              value={annotation.fontSize}
              min={12} max={72}
              onChange={(v) => updateAnnotation({ fontSize: v })}
              unit="px"
            />
          </Row>
        </>
      )}

      {/* Line / Arrow */}
      {(annotation.type === "line" || annotation.type === "arrow") && (
        <>
          <Row label="Style">
            <select
              value={annotation.lineType}
              onChange={(e) => {
                const newType = e.target.value as LineType;
                if (newType === "curved" && (annotation.type === "line" || annotation.type === "arrow")) {
                  const midX = (annotation.x + annotation.endX) / 2;
                  const midY = (annotation.y + annotation.endY) / 2;
                  const dx = annotation.endX - annotation.x;
                  const dy = annotation.endY - annotation.y;
                  const perpX = -dy; const perpY = dx;
                  const len = Math.sqrt(perpX * perpX + perpY * perpY);
                  const offset = len * 0.3;
                  updateAnnotation({
                    lineType: newType,
                    controlPoints: [{ x: midX + (perpX / len) * offset, y: midY + (perpY / len) * offset }]
                  });
                } else {
                  updateAnnotation({ lineType: newType });
                }
              }}
              style={selectStyle}
            >
              <option value="straight">Straight</option>
              <option value="curved">Curved</option>
            </select>
          </Row>
          {annotation.type === "arrow" && (
            <Row label="Arrowhead">
              <select
                value={annotation.arrowType}
                onChange={(e) => updateAnnotation({ arrowType: e.target.value as ArrowType })}
                style={selectStyle}
              >
                <option value="thick">Large</option>
                <option value="thin">Small</option>
                <option value="none">None</option>
              </select>
            </Row>
          )}
        </>
      )}

      {/* Number */}
      {annotation.type === "number" && (
        <>
          <Row label="Value">
            <input
              type="number"
              value={annotation.number}
              onChange={(e) => updateAnnotation({ number: Number(e.target.value) || 1 })}
              onKeyDown={stopPropagation}
              style={inputStyle}
              min={1}
            />
          </Row>
          <Row label="Size">
            <SliderWithValue
              value={annotation.radius}
              min={10} max={50}
              onChange={(v) => updateAnnotation({ radius: v })}
              unit="px"
            />
          </Row>
        </>
      )}

      {/* Fill */}
      {annotation.type !== "blur" && (
        <>
          <hr className="panel-divider" style={{ marginTop: 4 }} />
          <Row label="Fill Color">
            <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 8 }}>
              <div style={{ position: 'relative', flexShrink: 0 }}>
                <div style={{
                  width: 28, height: 28, borderRadius: 5,
                  background: annotation.fill.hex,
                  border: '1px solid oklch(0.32 0.009 250)',
                  cursor: 'pointer',
                }} />
                <input
                  type="color"
                  value={annotation.fill.hex}
                  onChange={(e) => handleColorChange("fill", e.target.value)}
                  style={{ position: 'absolute', inset: 0, opacity: 0, cursor: 'pointer', width: '100%', height: '100%' }}
                />
              </div>
              <input
                type="text"
                value={annotation.fill.hex.toUpperCase()}
                onChange={(e) => handleColorChange("fill", e.target.value)}
                onKeyDown={stopPropagation}
                style={{ ...inputStyle, flex: 1, fontFamily: 'var(--font-mono)', fontSize: 11 }}
              />
              <span style={{ fontSize: 11, fontFamily: 'var(--font-mono)', color: 'oklch(0.48 0.009 250)', flexShrink: 0, width: 32, textAlign: 'right' }}>
                {Math.round(annotation.fill.opacity)}%
              </span>
            </div>
            <SliderWithValue
              value={annotation.fill.opacity}
              min={0} max={100}
              onChange={(v) => handleOpacityChange("fill", v)}
              unit="%"
            />
          </Row>

          {/* Border */}
          <Row label="Border">
            <div style={{ marginBottom: 8 }}>
              <div style={{ fontSize: 10, color: 'oklch(0.38 0.009 250)', marginBottom: 4 }}>Width</div>
              <SliderWithValue
                value={annotation.border.width}
                min={0} max={20}
                onChange={(v) => updateAnnotation({ border: { ...annotation.border, width: v } })}
                unit="px"
              />
            </div>
            <div style={{ marginBottom: 8 }}>
              <div style={{ fontSize: 10, color: 'oklch(0.38 0.009 250)', marginBottom: 4 }}>Color</div>
              <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
                <div style={{ position: 'relative', flexShrink: 0 }}>
                  <div style={{
                    width: 28, height: 28, borderRadius: 5,
                    background: annotation.border.color.hex,
                    border: '1px solid oklch(0.32 0.009 250)',
                    cursor: 'pointer',
                  }} />
                  <input
                    type="color"
                    value={annotation.border.color.hex}
                    onChange={(e) => handleColorChange("border", e.target.value)}
                    style={{ position: 'absolute', inset: 0, opacity: 0, cursor: 'pointer', width: '100%', height: '100%' }}
                  />
                </div>
                <input
                  type="text"
                  value={annotation.border.color.hex.toUpperCase()}
                  onChange={(e) => handleColorChange("border", e.target.value)}
                  onKeyDown={stopPropagation}
                  style={{ ...inputStyle, flex: 1, fontFamily: 'var(--font-mono)', fontSize: 11 }}
                />
                <span style={{ fontSize: 11, fontFamily: 'var(--font-mono)', color: 'oklch(0.48 0.009 250)', flexShrink: 0, width: 32, textAlign: 'right' }}>
                  {Math.round(annotation.border.color.opacity)}%
                </span>
              </div>
              <SliderWithValue
                value={annotation.border.color.opacity}
                min={0} max={100}
                onChange={(v) => handleOpacityChange("border", v)}
                unit="%"
              />
            </div>
          </Row>
        </>
      )}
    </div>
  );
});
