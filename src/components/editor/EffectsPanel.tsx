import { memo, useState } from "react";
import { toast } from "sonner";
import { Check, Bookmark } from "lucide-react";
import { Slider } from "@/components/ui/slider";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import type { ShadowSettings } from "@/stores/editorStore";

interface EffectsPanelProps {
  blurAmount: number;
  noiseAmount: number;
  padding: number;
  shadow: ShadowSettings;
  // Transient handlers (during drag) - for visual feedback
  onBlurAmountChangeTransient?: (value: number) => void;
  onNoiseChangeTransient?: (value: number) => void;
  onPaddingChangeTransient?: (value: number) => void;
  onShadowBlurChangeTransient?: (value: number) => void;
  onShadowOffsetXChangeTransient?: (value: number) => void;
  onShadowOffsetYChangeTransient?: (value: number) => void;
  onShadowOpacityChangeTransient?: (value: number) => void;
  // Commit handlers (on release) - for state/history
  onBlurAmountChange: (value: number) => void;
  onNoiseChange: (value: number) => void;
  onPaddingChange: (value: number) => void;
  onShadowBlurChange: (value: number) => void;
  onShadowOffsetXChange: (value: number) => void;
  onShadowOffsetYChange: (value: number) => void;
  onShadowOpacityChange: (value: number) => void;
  // Persist settings as defaults
  onSaveAsDefaults?: () => Promise<void>;
}

export const EffectsPanel = memo(function EffectsPanel({
  blurAmount,
  noiseAmount,
  padding,
  shadow,
  onBlurAmountChangeTransient,
  onNoiseChangeTransient,
  onPaddingChangeTransient,
  onShadowBlurChangeTransient,
  onShadowOffsetXChangeTransient,
  onShadowOffsetYChangeTransient,
  onShadowOpacityChangeTransient,
  onBlurAmountChange,
  onNoiseChange,
  onPaddingChange,
  onShadowBlurChange,
  onShadowOffsetXChange,
  onShadowOffsetYChange,
  onShadowOpacityChange,
  onSaveAsDefaults,
}: EffectsPanelProps) {
  const maxPadding = 400;
  const [isSaving, setIsSaving] = useState(false);
  const [justSaved, setJustSaved] = useState(false);

  const handleSaveAsDefaults = async () => {
    if (!onSaveAsDefaults || isSaving) return;

    setIsSaving(true);
    try {
      await onSaveAsDefaults();
      setJustSaved(true);
      toast.success("Effect settings saved as defaults");
      setTimeout(() => setJustSaved(false), 2000);
    } catch {
      toast.error("Failed to save defaults");
    } finally {
      setIsSaving(false);
    }
  };
  return (
    <div className="space-y-6">
      {/* Background Effects */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-medium text-foreground font-mono text-balance">Background Effects</h3>
        </div>

        <div className="space-y-6">
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <label className="text-xs text-muted-foreground font-medium cursor-help">Gaussian Blur</label>
                  </TooltipTrigger>
                  <TooltipContent side="right" className="max-w-48">
                    <p className="text-xs text-pretty">Apply Gaussian blur to the background behind the captured image.</p>
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
              <span className="text-xs text-muted-foreground font-mono tabular-nums">{blurAmount}px</span>
            </div>
            <Slider
              value={[blurAmount]}
              onValueChange={(value) => onBlurAmountChangeTransient?.(value[0])}
              onValueCommit={(value) => onBlurAmountChange(value[0])}
              min={0}
              max={100}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-muted-foreground font-medium">Noise</label>
              <span className="text-xs text-muted-foreground font-mono tabular-nums">{noiseAmount}%</span>
            </div>
            <Slider
              value={[noiseAmount]}
              onValueChange={(value) => onNoiseChangeTransient?.(value[0])}
              onValueCommit={(value) => onNoiseChange(value[0])}
              min={0}
              max={100}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <label className="text-xs text-muted-foreground font-medium cursor-help">Background Border</label>
                  </TooltipTrigger>
                  <TooltipContent side="right" className="max-w-48">
                    <p className="text-xs text-pretty">Adjust the width of the background border around the captured object.</p>
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
              <span className="text-xs text-muted-foreground font-mono tabular-nums">{padding}px</span>
            </div>
            <Slider
              value={[padding]}
              onValueChange={(value) => onPaddingChangeTransient?.(value[0])}
              onValueCommit={(value) => onPaddingChange(value[0])}
              min={0}
              max={maxPadding}
              step={1}
              className="w-full"
            />
          </div>
        </div>
      </div>

      {/* Shadow Effects */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-medium text-foreground font-mono text-balance">Shadow</h3>
        </div>
        
        <div className="space-y-6">
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-muted-foreground font-medium">Blur</label>
              <span className="text-xs text-muted-foreground font-mono tabular-nums">{shadow.blur}px</span>
            </div>
            <Slider
              value={[shadow.blur]}
              onValueChange={(value) => onShadowBlurChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowBlurChange(value[0])}
              min={0}
              max={100}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-muted-foreground font-medium">Offset X</label>
              <span className="text-xs text-muted-foreground font-mono tabular-nums">{shadow.offsetX}px</span>
            </div>
            <Slider
              value={[shadow.offsetX]}
              onValueChange={(value) => onShadowOffsetXChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowOffsetXChange(value[0])}
              min={-50}
              max={50}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-muted-foreground font-medium">Offset Y</label>
              <span className="text-xs text-muted-foreground font-mono tabular-nums">{shadow.offsetY}px</span>
            </div>
            <Slider
              value={[shadow.offsetY]}
              onValueChange={(value) => onShadowOffsetYChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowOffsetYChange(value[0])}
              min={-50}
              max={50}
              step={1}
              className="w-full"
            />
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-xs text-muted-foreground font-medium">Opacity</label>
              <span className="text-xs text-muted-foreground font-mono tabular-nums">{shadow.opacity}%</span>
            </div>
            <Slider
              value={[shadow.opacity]}
              onValueChange={(value) => onShadowOpacityChangeTransient?.(value[0])}
              onValueCommit={(value) => onShadowOpacityChange(value[0])}
              min={0}
              max={100}
              step={1}
              className="w-full"
            />
          </div>
        </div>
      </div>

      {/* Save as Defaults */}
      {onSaveAsDefaults && (
        <div className="pt-2 border-t border-border">
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleSaveAsDefaults}
                  disabled={isSaving}
                  className="w-full text-muted-foreground hover:text-foreground"
                >
                  {justSaved ? (
                    <Check className="size-3.5 mr-1.5 text-green-500" aria-hidden="true" />
                  ) : (
                    <Bookmark className="size-3.5 mr-1.5" aria-hidden="true" />
                  )}
                  {justSaved ? "Saved" : "Set as Default"}
                </Button>
              </TooltipTrigger>
              <TooltipContent side="top">
                <p className="text-xs text-pretty">Save current effect settings as defaults for new screenshots</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
      )}
    </div>
  );
});
