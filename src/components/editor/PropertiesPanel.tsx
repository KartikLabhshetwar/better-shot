import { useState, useEffect, memo } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";
import { Slider } from "@/components/ui/slider";
import { Annotation, LineType, ArrowType } from "@/types/annotations";

const stopPropagation = (e: React.KeyboardEvent) => {
  e.stopPropagation();
};

interface PropertiesPanelProps {
  annotation: Annotation | null;
  onUpdate: (annotation: Annotation) => void;
}

export const PropertiesPanel = memo(function PropertiesPanel({ annotation, onUpdate }: PropertiesPanelProps) {
  const [expandedSections, setExpandedSections] = useState<Set<string>>(new Set(["color"]));

  useEffect(() => {
    if (!annotation) return;
    
    const newExpanded = new Set(["color"]);
    
    if (annotation.type === "text") {
      newExpanded.add("text");
    }
    if (annotation.type === "line" || annotation.type === "arrow") {
      newExpanded.add("line");
    }
    if (annotation.type === "number") {
      newExpanded.add("number");
    }
    if (annotation.type === "blur") {
      newExpanded.add("blur");
      newExpanded.delete("color");
    }
    
    setExpandedSections(newExpanded);
  }, [annotation?.type, annotation?.id]);

  if (!annotation) {
    return (
      <div className="px-4 py-3 text-sm text-foreground0 text-pretty">
        Select an annotation to edit
      </div>
    );
  }

  const toggleSection = (section: string) => {
    const newExpanded = new Set(expandedSections);
    if (newExpanded.has(section)) {
      newExpanded.delete(section);
    } else {
      newExpanded.add(section);
    }
    setExpandedSections(newExpanded);
  };

  const updateAnnotation = (updates: Partial<Annotation>) => {
    onUpdate({ ...annotation, ...updates } as Annotation);
  };

  return (
    <div className="px-4 py-3 space-y-2">
      {annotation.type === "blur" && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("blur")}
            className="w-full flex items-center justify-between text-xs font-medium text-foreground hover:text-foreground"
          >
            <span>Blur</span>
            {expandedSections.has("blur") ? (
              <ChevronUp className="size-3" />
            ) : (
              <ChevronDown className="size-3" />
            )}
          </button>
          {expandedSections.has("blur") && (
            <div className="space-y-2 pl-2">
              <div>
                <div className="text-xs text-foreground0 mb-1.5">Intensity</div>
                <div className="flex items-center gap-2">
                  <Slider
                    value={[annotation.blurAmount]}
                    onValueChange={([value]) => updateAnnotation({ blurAmount: value })}
                    min={1}
                    max={50}
                    step={1}
                  />
                  <input
                    type="text"
                    value={annotation.blurAmount}
                    onChange={(e) => updateAnnotation({ blurAmount: Number(e.target.value) || 20 })}
                    onKeyDown={stopPropagation}
                    className="w-14 px-1.5 py-1 bg-secondary border border-border rounded text-xs text-card-foreground"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {annotation.type === "text" && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("text")}
            className="w-full flex items-center justify-between text-xs font-medium text-foreground hover:text-foreground"
          >
            <span>Text</span>
            {expandedSections.has("text") ? (
              <ChevronUp className="size-3" />
            ) : (
              <ChevronDown className="size-3" />
            )}
          </button>
          {expandedSections.has("text") && (
            <div className="space-y-2 pl-2">
              <div>
                <div className="text-xs text-foreground0 mb-1.5">Content</div>
                <textarea
                  value={annotation.text}
                  onChange={(e) => updateAnnotation({ text: e.target.value })}
                  onFocus={(e) => e.target.select()}
                  onKeyDown={stopPropagation}
                  className="w-full px-2 py-1.5 bg-secondary border border-border rounded text-sm text-card-foreground resize-none focus:outline-none focus:ring-1 focus:ring-ring"
                  rows={2}
                  placeholder="Enter text..."
                  autoFocus
                />
              </div>
              <div>
                <div className="text-xs text-foreground0 mb-1.5">Size</div>
                <div className="flex items-center gap-2">
                  <Slider
                    value={[annotation.fontSize]}
                    onValueChange={([value]) => updateAnnotation({ fontSize: value })}
                    min={8}
                    max={200}
                    step={1}
                  />
                  <input
                    type="text"
                    value={annotation.fontSize}
                    onChange={(e) => {
                      const val = e.target.value;
                      if (val === "" || /^\d*$/.test(val)) {
                        updateAnnotation({ fontSize: val as unknown as number });
                      }
                    }}
                    onBlur={(e) => {
                      const val = Number(e.target.value);
                      updateAnnotation({ fontSize: Math.max(8, Math.min(200, isNaN(val) ? 24 : val)) });
                    }}
                    onKeyDown={stopPropagation}
                    className="w-14 px-1.5 py-1 bg-secondary border border-border rounded text-xs text-card-foreground"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {(annotation.type === "line" || annotation.type === "arrow") && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("line")}
            className="w-full flex items-center justify-between text-xs font-medium text-foreground hover:text-foreground"
          >
            <span>{annotation.type === "arrow" ? "Arrow" : "Line"}</span>
            {expandedSections.has("line") ? (
              <ChevronUp className="size-3" />
            ) : (
              <ChevronDown className="size-3" />
            )}
          </button>
          {expandedSections.has("line") && (
            <div className="space-y-2 pl-2">
              <div>
                <div className="text-xs text-foreground0 mb-1.5">Style</div>
                <select
                  value={annotation.lineType}
                  onChange={(e) => {
                    const newLineType = e.target.value as LineType;
                    if (newLineType === "curved" && (annotation.type === "line" || annotation.type === "arrow")) {
                      const midX = (annotation.x + annotation.endX) / 2;
                      const midY = (annotation.y + annotation.endY) / 2;
                      const dx = annotation.endX - annotation.x;
                      const dy = annotation.endY - annotation.y;
                      const perpX = -dy;
                      const perpY = dx;
                      const length = Math.sqrt(perpX * perpX + perpY * perpY);
                      const offset = length * 0.3;
                      const controlPoint = {
                        x: midX + (perpX / length) * offset,
                        y: midY + (perpY / length) * offset,
                      };
                      updateAnnotation({ 
                        lineType: newLineType,
                        controlPoints: [controlPoint]
                      });
                    } else {
                      updateAnnotation({ lineType: newLineType });
                    }
                  }}
                  className="w-full px-2 py-1 bg-secondary border border-border rounded text-xs text-card-foreground"
                >
                  <option value="straight">Straight</option>
                  <option value="curved">Curved</option>
                </select>
              </div>
              {annotation.type === "arrow" && (
                <div>
                  <div className="text-xs text-foreground0 mb-1.5">Arrow Head</div>
                  <select
                    value={annotation.arrowType}
                    onChange={(e) => updateAnnotation({ arrowType: e.target.value as ArrowType })}
                    className="w-full px-2 py-1 bg-secondary border border-border rounded text-xs text-card-foreground"
                  >
                    <option value="thick">Large</option>
                    <option value="thin">Small</option>
                    <option value="none">None</option>
                  </select>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {annotation.type === "number" && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("number")}
            className="w-full flex items-center justify-between text-xs font-medium text-foreground hover:text-foreground"
          >
            <span>Number</span>
            {expandedSections.has("number") ? (
              <ChevronUp className="size-3" />
            ) : (
              <ChevronDown className="size-3" />
            )}
          </button>
          {expandedSections.has("number") && (
            <div className="space-y-2 pl-2">
              <div>
                <div className="text-xs text-foreground0 mb-1.5">Value</div>
                  <input
                    type="number"
                    value={annotation.number}
                    onChange={(e) => {
                      const val = e.target.value;
                      if (val === "" || val === "-") {
                        updateAnnotation({ number: val as unknown as number });
                      } else {
                        updateAnnotation({ number: Number(val) || 1 });
                      }
                    }}
                    onBlur={(e) => {
                      if (e.target.value === "" || e.target.value === "-") {
                        updateAnnotation({ number: 1 });
                      }
                    }}
                    onKeyDown={stopPropagation}
                    className="w-full px-2 py-1 bg-secondary border border-border rounded text-xs text-card-foreground"
                    min={1}
                  />
              </div>
              <div>
                <div className="text-xs text-foreground0 mb-1.5">Size</div>
                <div className="flex items-center gap-2">
                  <Slider
                    value={[annotation.radius]}
                    onValueChange={([value]) => updateAnnotation({ radius: value })}
                    min={10}
                    max={50}
                    step={1}
                  />
                  <input
                    type="text"
                    value={annotation.radius}
                    onChange={(e) => {
                      const val = e.target.value;
                      if (val === "" || val === "-") {
                        updateAnnotation({ radius: val as unknown as number });
                      } else {
                        updateAnnotation({ radius: Number(val) || 20 });
                      }
                    }}
                    onBlur={(e) => {
                      if (e.target.value === "" || e.target.value === "-") {
                        updateAnnotation({ radius: 20 });
                      }
                    }}
                    onKeyDown={stopPropagation}
                    className="w-14 px-1.5 py-1 bg-secondary border border-border rounded text-xs text-card-foreground"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {annotation.type !== "blur" && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("color")}
            className="w-full flex items-center justify-between text-xs font-medium text-foreground hover:text-foreground"
          >
            <span>Color</span>
            {expandedSections.has("color") ? (
              <ChevronUp className="size-3" />
            ) : (
              <ChevronDown className="size-3" />
            )}
          </button>
          {expandedSections.has("color") && (
            <div className="space-y-2 pl-2">
              <div>
                <div className="text-xs text-foreground0 mb-1.5">
                  {annotation.type === "text" ? "Text Color" : "Fill Color"}
                </div>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    value={annotation.fill.hex}
                    onChange={(e) => updateAnnotation({ fill: { ...annotation.fill, hex: e.target.value } })}
                    className="size-7 rounded border border-border cursor-pointer"
                  />
                  <input
                    type="text"
                    value={annotation.fill.hex.toUpperCase()}
                    onChange={(e) => updateAnnotation({ fill: { ...annotation.fill, hex: e.target.value } })}
                    onKeyDown={stopPropagation}
                    className="flex-1 px-2 py-1 bg-secondary border border-border rounded text-xs text-card-foreground"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
});
