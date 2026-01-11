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
  { id: "mesh-1", name: "Mesh 1", src: mesh1, colors: ["#667eea", "#764ba2"] },
  { id: "mesh-2", name: "Mesh 2", src: mesh2, colors: ["#0093E9", "#80D0C7"] },
  { id: "mesh-3", name: "Mesh 3", src: mesh3, colors: ["#f093fb", "#f5576c"] },
  { id: "mesh-4", name: "Mesh 4", src: mesh4, colors: ["#11998e", "#38ef7d"] },
  { id: "mesh-5", name: "Mesh 5", src: mesh5, colors: ["#fa709a", "#fee140"] },
  { id: "mesh-6", name: "Mesh 6", src: mesh6, colors: ["#2E3192", "#1BFFFF"] },
  { id: "mesh-7", name: "Mesh 7", src: mesh7, colors: ["#ffecd2", "#fcb69f"] },
  { id: "mesh-8", name: "Mesh 8", src: mesh8, colors: ["#0f0c29", "#24243e"] },
];

interface BackgroundSelectorProps {
  backgroundType: BackgroundType;
  customColor: string;
  selectedGradient?: string;
  onBackgroundTypeChange: (type: BackgroundType) => void;
  onCustomColorChange: (color: string) => void;
  onGradientSelect?: (gradient: GradientOption) => void;
}

export function BackgroundSelector({
  backgroundType,
  customColor,
  selectedGradient,
  onBackgroundTypeChange,
  onCustomColorChange,
  onGradientSelect,
}: BackgroundSelectorProps) {
  const solidColors: { type: BackgroundType; color: string }[] = [
    { type: "white", color: "#ffffff" },
    { type: "black", color: "#000000" },
    { type: "gray", color: "#f5f5f5" },
    { type: "transparent", color: "transparent" },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-zinc-200 font-mono text-balance">Background</h3>
      </div>
      
      {/* Solid Colors */}
      <div className="space-y-2">
        <span className="text-xs text-zinc-500">Solid</span>
        <div className="flex gap-2">
          {solidColors.map(({ type, color }) => (
            <button
              key={type}
              onClick={() => onBackgroundTypeChange(type)}
              aria-label={`Select ${type} background`}
              className={cn(
                "size-10 rounded-lg transition-all",
                type === "transparent" && "bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGRlZnM+PHBhdHRlcm4gaWQ9ImNoZWNrZXJib2FyZCIgd2lkdGg9IjEwIiBoZWlnaHQ9IjEwIiBwYXR0ZXJuVW5pdHM9InVzZXJTcGFjZU9uVXNlIj48cmVjdCB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjZmZmIi8+PHJlY3QgeD0iNSIgd2lkdGg9IjUiIGhlaWdodD0iNSIgZmlsbD0iI2UwZTBlMCIvPjxyZWN0IHk9IjUiIHdpZHRoPSI1IiBoZWlnaHQ9IjUiIGZpbGw9IiNlMGUwZTAiLz48cmVjdCB4PSI1IiB5PSI1IiB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjZmZmIi8+PC9wYXR0ZXJuPjwvZGVmcz48cmVjdCB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIGZpbGw9InVybCgjY2hlY2tlcmJvYXJkKSIvPjwvc3ZnPg==')]",
                backgroundType === type
                  ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-zinc-900"
                  : "ring-1 ring-zinc-700 hover:ring-zinc-500"
              )}
              style={type !== "transparent" ? { backgroundColor: color } : undefined}
              title={type.charAt(0).toUpperCase() + type.slice(1)}
            />
          ))}
          {/* Custom color picker */}
          <div className="relative">
            <button
              onClick={() => onBackgroundTypeChange("custom")}
              aria-label="Select custom color background"
              className={cn(
                "size-10 rounded-lg transition-all",
                backgroundType === "custom"
                  ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-zinc-900"
                  : "ring-1 ring-zinc-700 hover:ring-zinc-500"
              )}
              style={{ backgroundColor: customColor }}
              title="Custom color"
            />
            <input
              type="color"
              value={customColor}
              onChange={(e) => {
                onCustomColorChange(e.target.value);
                onBackgroundTypeChange("custom");
              }}
              className="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
            />
          </div>
        </div>
      </div>

      {/* Gradients */}
      <div className="space-y-2">
        <span className="text-xs text-zinc-500">Gradients</span>
        <div className="grid grid-cols-4 gap-2">
          {gradientOptions.map((gradient) => {
            const isSelected = backgroundType === "gradient" && selectedGradient === gradient.id;
            return (
              <button
                key={gradient.id}
                onClick={() => {
                  onBackgroundTypeChange("gradient");
                  onGradientSelect?.(gradient);
                }}
                aria-label={`Select ${gradient.name} gradient`}
                className={cn(
                  "relative w-full aspect-square rounded-lg transition-all overflow-hidden",
                  isSelected
                    ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-zinc-900"
                    : "ring-1 ring-zinc-700 hover:ring-zinc-500"
                )}
                title={gradient.name}
              >
                <img
                  src={gradient.src}
                  alt={gradient.name}
                  className="w-full h-full object-cover"
                />
                {isSelected && (
                  <div className="absolute inset-0 bg-blue-500/20 flex items-center justify-center">
                    <div className="size-6 rounded-full bg-blue-500 flex items-center justify-center shadow-lg">
                      <svg className="size-3.5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" />
                      </svg>
                    </div>
                  </div>
                )}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export { gradientOptions };
export type { GradientOption };
