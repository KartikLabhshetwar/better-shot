import { memo } from "react";
import { Circle, Square, Minus, ArrowUpRight, Type, Hash, MousePointer2, Trash2, Scan } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { ToolType } from "@/types/annotations";
import { cn } from "@/lib/utils";

interface AnnotationToolbarProps {
  selectedTool: ToolType;
  onToolSelect: (tool: ToolType) => void;
  onDelete?: () => void;
}

const tools: Array<{ type: ToolType; icon: React.ReactNode; label: string }> = [
  { type: "select", icon: <MousePointer2 className="size-4" />, label: "Select" },
  { type: "circle", icon: <Circle className="size-4" />, label: "Circle" },
  { type: "rectangle", icon: <Square className="size-4" />, label: "Rectangle" },
  { type: "line", icon: <Minus className="size-4" />, label: "Line" },
  { type: "arrow", icon: <ArrowUpRight className="size-4" />, label: "Arrow" },
  { type: "number", icon: <Hash className="size-4" />, label: "Number" },
  { type: "text", icon: <Type className="size-4" />, label: "Text" },
  { type: "blur", icon: <Scan className="size-4" />, label: "Blur an area" },
];

export const AnnotationToolbar = memo(function AnnotationToolbar({ selectedTool, onToolSelect, onDelete }: AnnotationToolbarProps) {
  return (
    <TooltipProvider delayDuration={200}>
      <div className="flex items-center gap-1 px-4 py-2 border-b border-border bg-card">
        {tools.map((tool) => (
          <Tooltip key={tool.type}>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => onToolSelect(tool.type)}
                className={cn(
                  "size-8 rounded-md",
                  selectedTool === tool.type
                    ? "bg-muted text-foreground"
                    : "text-muted-foreground hover:text-foreground hover:bg-secondary"
                )}
                aria-label={tool.label}
              >
                {tool.icon}
              </Button>
            </TooltipTrigger>
            <TooltipContent side="bottom" className="text-xs">
              {tool.label}
            </TooltipContent>
          </Tooltip>
        ))}
        {onDelete && (
          <div className="ml-auto">
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={onDelete}
                  className="size-8 rounded-md text-red-400 hover:text-red-300 hover:bg-red-950/30"
                  aria-label="Delete"
                >
                  <Trash2 className="size-4" />
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom" className="text-xs">
                Delete
              </TooltipContent>
            </Tooltip>
          </div>
        )}
      </div>
    </TooltipProvider>
  );
});
