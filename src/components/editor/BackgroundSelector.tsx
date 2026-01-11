import { cn } from "@/lib/utils";

type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom";

interface GradientOption {
  id: string;
  name: string;
  gradient: string;
  colors: [string, string];
}

const gradientOptions: GradientOption[] = [
  { id: "purple-pink", name: "Purple Pink", gradient: "linear-gradient(135deg, #667eea 0%, #764ba2 100%)", colors: ["#667eea", "#764ba2"] },
  { id: "blue-cyan", name: "Blue Cyan", gradient: "linear-gradient(135deg, #0093E9 0%, #80D0C7 100%)", colors: ["#0093E9", "#80D0C7"] },
  { id: "orange-red", name: "Orange Red", gradient: "linear-gradient(135deg, #f093fb 0%, #f5576c 100%)", colors: ["#f093fb", "#f5576c"] },
  { id: "green-teal", name: "Green Teal", gradient: "linear-gradient(135deg, #11998e 0%, #38ef7d 100%)", colors: ["#11998e", "#38ef7d"] },
  { id: "sunset", name: "Sunset", gradient: "linear-gradient(135deg, #fa709a 0%, #fee140 100%)", colors: ["#fa709a", "#fee140"] },
  { id: "ocean", name: "Ocean", gradient: "linear-gradient(135deg, #2E3192 0%, #1BFFFF 100%)", colors: ["#2E3192", "#1BFFFF"] },
  { id: "peach", name: "Peach", gradient: "linear-gradient(135deg, #ffecd2 0%, #fcb69f 100%)", colors: ["#ffecd2", "#fcb69f"] },
  { id: "night", name: "Night", gradient: "linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%)", colors: ["#0f0c29", "#24243e"] },
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
          {gradientOptions.map((gradient) => (
            <button
              key={gradient.id}
              onClick={() => {
                onBackgroundTypeChange("gradient");
                onGradientSelect?.(gradient);
              }}
              aria-label={`Select ${gradient.name} gradient`}
              className={cn(
                "w-full aspect-square rounded-lg transition-all",
                backgroundType === "gradient" && selectedGradient === gradient.id
                  ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-zinc-900"
                  : "ring-1 ring-zinc-700 hover:ring-zinc-500"
              )}
              style={{ background: gradient.gradient }}
              title={gradient.name}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

export { gradientOptions };
export type { GradientOption };
