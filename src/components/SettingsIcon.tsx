import { Settings } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface SettingsIconProps {
  onClick: () => void;
  className?: string;
  size?: "default" | "sm" | "lg";
}

export function SettingsIcon({ onClick, className, size = "default" }: SettingsIconProps) {
  return (
    <Button
      variant="ghost"
      size="icon"
      onClick={onClick}
      className={cn(
        "text-muted-foreground hover:text-foreground hover:bg-secondary",
        {
          "size-8": size === "sm",
          "size-10": size === "default",
          "size-12": size === "lg",
        },
        className
      )}
      aria-label="Open settings"
    >
      <Settings className="size-4" aria-hidden="true" />
    </Button>
  );
}
