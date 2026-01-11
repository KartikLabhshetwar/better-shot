import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom";

interface BackgroundSelectorProps {
  backgroundType: BackgroundType;
  customColor: string;
  onBackgroundTypeChange: (type: BackgroundType) => void;
  onCustomColorChange: (color: string) => void;
}

export function BackgroundSelector({
  backgroundType,
  customColor,
  onBackgroundTypeChange,
  onCustomColorChange,
}: BackgroundSelectorProps) {
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-zinc-200 font-mono">Background</h3>
      </div>
      
      <div className="grid grid-cols-3 gap-2">
        {(["gradient", "white", "black", "gray", "transparent", "custom"] as BackgroundType[]).map((type) => (
          <Button
            key={type}
            variant="outline"
            size="sm"
            onClick={() => onBackgroundTypeChange(type)}
            className={cn(
              "capitalize text-xs h-8",
              backgroundType === type
                ? "bg-zinc-700 text-white border-zinc-600 hover:bg-zinc-600 hover:text-white"
                : "bg-transparent border-zinc-800 text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200 hover:border-zinc-700"
            )}
          >
            {type}
          </Button>
        ))}
      </div>

      {backgroundType === "custom" && (
        <div className="flex items-center gap-3 pt-2 bg-zinc-800/30 p-3 rounded-lg border border-zinc-800">
          <label className="text-xs text-zinc-400 font-medium">Custom Color</label>
          <div className="flex-1 flex justify-end">
            <input
              type="color"
              value={customColor}
              onChange={(e) => onCustomColorChange(e.target.value)}
              className="w-8 h-8 rounded cursor-pointer bg-transparent border-0 p-0"
            />
          </div>
        </div>
      )}
    </div>
  );
}
