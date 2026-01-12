import { useState, useEffect } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";
import { Slider } from "@/components/ui/slider";
import { Annotation, LineType, ArrowType } from "@/types/annotations";

interface PropertiesPanelProps {
  annotation: Annotation | null;
  onUpdate: (annotation: Annotation) => void;
}

export function PropertiesPanel({ annotation, onUpdate }: PropertiesPanelProps) {
  const [expandedSections, setExpandedSections] = useState<Set<string>>(new Set(["fill", "border"]));

  // Auto-expand relevant sections based on annotation type
  useEffect(() => {
    if (!annotation) return;
    
    const newExpanded = new Set(["fill", "border"]);
    
    if (annotation.type === "text") {
      newExpanded.add("text");
    }
    if (annotation.type === "line" || annotation.type === "arrow") {
      newExpanded.add("line");
    }
    if (annotation.type === "number") {
      newExpanded.add("number");
    }
    
    setExpandedSections(newExpanded);
  }, [annotation?.type, annotation?.id]);

  if (!annotation) {
    return (
      <div className="px-4 py-3 text-sm text-zinc-500 text-pretty">
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

  return (
    <div className="px-4 py-3 space-y-2">
      {/* Text Section - Only for text annotations */}
      {annotation.type === "text" && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("text")}
            className="w-full flex items-center justify-between text-xs font-medium text-zinc-300 hover:text-zinc-50"
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
                <div className="text-xs text-zinc-500 mb-1.5">Content</div>
                <textarea
                  value={annotation.text}
                  onChange={(e) => updateAnnotation({ text: e.target.value })}
                  onFocus={(e) => e.target.select()}
                  className="w-full px-2 py-1.5 bg-zinc-800 border border-zinc-700 rounded text-sm text-zinc-100 resize-none focus:outline-none focus:ring-1 focus:ring-zinc-600"
                  rows={2}
                  placeholder="Enter text..."
                  autoFocus
                />
              </div>
              <div>
                <div className="text-xs text-zinc-500 mb-1.5">Font Size</div>
                <div className="flex items-center gap-2">
                  <Slider
                    value={[annotation.fontSize]}
                    onValueChange={([value]) => updateAnnotation({ fontSize: value })}
                    min={12}
                    max={72}
                    step={1}
                  />
                  <input
                    type="text"
                    value={annotation.fontSize}
                    onChange={(e) => updateAnnotation({ fontSize: Number(e.target.value) || 24 })}
                    className="w-14 px-1.5 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Line/Arrow Section */}
      {(annotation.type === "line" || annotation.type === "arrow") && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("line")}
            className="w-full flex items-center justify-between text-xs font-medium text-zinc-300 hover:text-zinc-50"
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
                <div className="text-xs text-zinc-500 mb-1.5">Style</div>
                <select
                  value={annotation.lineType}
                  onChange={(e) => updateAnnotation({ lineType: e.target.value as LineType })}
                  className="w-full px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                >
                  <option value="straight">Straight</option>
                  <option value="curved">Curved</option>
                </select>
              </div>
              {annotation.type === "arrow" && (
                <div>
                  <div className="text-xs text-zinc-500 mb-1.5">Arrow Head</div>
                  <select
                    value={annotation.arrowType}
                    onChange={(e) => updateAnnotation({ arrowType: e.target.value as ArrowType })}
                    className="w-full px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
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

      {/* Number Section */}
      {annotation.type === "number" && (
        <div className="space-y-1.5">
          <button
            onClick={() => toggleSection("number")}
            className="w-full flex items-center justify-between text-xs font-medium text-zinc-300 hover:text-zinc-50"
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
                <div className="text-xs text-zinc-500 mb-1.5">Value</div>
                <input
                  type="number"
                  value={annotation.number}
                  onChange={(e) => updateAnnotation({ number: Number(e.target.value) || 1 })}
                  className="w-full px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                  min={1}
                />
              </div>
              <div>
                <div className="text-xs text-zinc-500 mb-1.5">Size</div>
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
                    onChange={(e) => updateAnnotation({ radius: Number(e.target.value) || 20 })}
                    className="w-14 px-1.5 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Fill Section */}
      <div className="space-y-1.5">
        <button
          onClick={() => toggleSection("fill")}
          className="w-full flex items-center justify-between text-xs font-medium text-zinc-300 hover:text-zinc-50"
        >
          <span>Fill</span>
          {expandedSections.has("fill") ? (
            <ChevronUp className="size-3" />
          ) : (
            <ChevronDown className="size-3" />
          )}
        </button>
        {expandedSections.has("fill") && (
          <div className="space-y-2 pl-2">
            <div>
              <div className="text-xs text-zinc-500 mb-1.5">Color</div>
              <div className="flex items-center gap-2">
                <input
                  type="color"
                  value={annotation.fill.hex}
                  onChange={(e) => handleColorChange("fill", e.target.value)}
                  className="size-7 rounded border border-zinc-700 cursor-pointer"
                />
                <input
                  type="text"
                  value={annotation.fill.hex.toUpperCase()}
                  onChange={(e) => handleColorChange("fill", e.target.value)}
                  className="flex-1 px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                />
                <input
                  type="text"
                  value={`${Math.round(annotation.fill.opacity)}%`}
                  readOnly
                  className="w-12 px-1.5 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                />
              </div>
              <div className="mt-2">
                <Slider
                  value={[annotation.fill.opacity]}
                  onValueChange={([value]) => handleOpacityChange("fill", value)}
                  min={0}
                  max={100}
                  step={1}
                />
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Border Section */}
      <div className="space-y-1.5">
        <button
          onClick={() => toggleSection("border")}
          className="w-full flex items-center justify-between text-xs font-medium text-zinc-300 hover:text-zinc-50"
        >
          <span>Border</span>
          {expandedSections.has("border") ? (
            <ChevronUp className="size-3" />
          ) : (
            <ChevronDown className="size-3" />
          )}
        </button>
        {expandedSections.has("border") && (
          <div className="space-y-2 pl-2">
            <div>
              <div className="text-xs text-zinc-500 mb-1.5">Width</div>
              <div className="flex items-center gap-2">
                <Slider
                  value={[annotation.border.width]}
                  onValueChange={([value]) => updateAnnotation({ border: { ...annotation.border, width: value } })}
                  min={0}
                  max={20}
                  step={1}
                />
                <input
                  type="text"
                  value={annotation.border.width}
                  onChange={(e) =>
                    updateAnnotation({ border: { ...annotation.border, width: Number(e.target.value) || 0 } })
                  }
                  className="w-14 px-1.5 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                />
              </div>
            </div>
            <div>
              <div className="text-xs text-zinc-500 mb-1.5">Color</div>
              <div className="flex items-center gap-2">
                <input
                  type="color"
                  value={annotation.border.color.hex}
                  onChange={(e) => handleColorChange("border", e.target.value)}
                  className="size-7 rounded border border-zinc-700 cursor-pointer"
                />
                <input
                  type="text"
                  value={annotation.border.color.hex.toUpperCase()}
                  onChange={(e) => handleColorChange("border", e.target.value)}
                  className="flex-1 px-2 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                />
                <input
                  type="text"
                  value={`${Math.round(annotation.border.color.opacity)}%`}
                  readOnly
                  className="w-12 px-1.5 py-1 bg-zinc-800 border border-zinc-700 rounded text-xs text-zinc-100"
                />
              </div>
              <div className="mt-2">
                <Slider
                  value={[annotation.border.color.opacity]}
                  onValueChange={([value]) => handleOpacityChange("border", value)}
                  min={0}
                  max={100}
                  step={1}
                />
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
