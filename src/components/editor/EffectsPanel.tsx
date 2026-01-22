import { memo, useState } from "react";
import { toast } from "sonner";
import { Check, Bookmark, Link2, Link2Off } from "lucide-react";
import { Slider } from "@/components/ui/slider";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import type { ShadowSettings, PaddingSettings, PaddingMode } from "@/stores/editorStore";

interface EffectsPanelProps {
  blurAmount: number;
  noiseAmount: number;
  padding: PaddingSettings;
  shadow: ShadowSettings;
  // Transient handlers (during drag) - for visual feedback
  onBlurAmountChangeTransient?: (value: number) => void;
  onNoiseChangeTransient?: (value: number) => void;
  onPaddingUniformChangeTransient?: (value: number) => void;
  onPaddingTopChangeTransient?: (value: number) => void;
  onPaddingRightChangeTransient?: (value: number) => void;
  onPaddingBottomChangeTransient?: (value: number) => void;
  onPaddingLeftChangeTransient?: (value: number) => void;
  onPaddingModeChangeTransient?: (mode: PaddingMode) => void;
  onShadowBlurChangeTransient?: (value: number) => void;
  onShadowOffsetXChangeTransient?: (value: number) => void;
  onShadowOffsetYChangeTransient?: (value: number) => void;
  onShadowOpacityChangeTransient?: (value: number) => void;
  // Commit handlers (on release) - for state/history
  onBlurAmountChange: (value: number) => void;
  onNoiseChange: (value: number) => void;
  onPaddingUniformChange: (value: number) => void;
  onPaddingTopChange: (value: number) => void;
  onPaddingRightChange: (value: number) => void;
  onPaddingBottomChange: (value: number) => void;
  onPaddingLeftChange: (value: number) => void;
  onPaddingModeChange: (mode: PaddingMode) => void;
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
  onPaddingUniformChangeTransient,
  onPaddingTopChangeTransient,
  onPaddingRightChangeTransient,
  onPaddingBottomChangeTransient,
  onPaddingLeftChangeTransient,
  onPaddingModeChangeTransient,
  onShadowBlurChangeTransient,
  onShadowOffsetXChangeTransient,
  onShadowOffsetYChangeTransient,
  onShadowOpacityChangeTransient,
  onBlurAmountChange,
  onNoiseChange,
  onPaddingUniformChange,
  onPaddingTopChange,
  onPaddingRightChange,
  onPaddingBottomChange,
  onPaddingLeftChange,
  onPaddingModeChange,
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
              <div className="flex items-center gap-2">
                {padding.mode === "uniform" && (
                  <span className="text-xs text-muted-foreground font-mono tabular-nums">{padding.uniform}px</span>
                )}
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="size-6"
                        onClick={() => {
                          const newMode = padding.mode === "uniform" ? "individual" : "uniform";
                          onPaddingModeChangeTransient?.(newMode);
                          onPaddingModeChange(newMode);
                        }}
                        aria-label={padding.mode === "uniform" ? "Switch to individual padding" : "Switch to uniform padding"}
                      >
                        {padding.mode === "uniform" ? (
                          <Link2 className="size-3.5" aria-hidden="true" />
                        ) : (
                          <Link2Off className="size-3.5" aria-hidden="true" />
                        )}
                      </Button>
                    </TooltipTrigger>
                    <TooltipContent side="left">
                      <p className="text-xs">{padding.mode === "uniform" ? "Individual padding" : "Uniform padding"}</p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              </div>
            </div>

            {padding.mode === "uniform" ? (
              <Slider
                value={[padding.uniform]}
                onValueChange={(value) => onPaddingUniformChangeTransient?.(value[0])}
                onValueCommit={(value) => onPaddingUniformChange(value[0])}
                min={0}
                max={maxPadding}
                step={1}
                className="w-full"
              />
            ) : (
              <div className="space-y-4">
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <label className="text-xs text-muted-foreground">Top</label>
                    <span className="text-xs text-muted-foreground font-mono tabular-nums">{padding.top}px</span>
                  </div>
                  <Slider
                    value={[padding.top]}
                    onValueChange={(value) => onPaddingTopChangeTransient?.(value[0])}
                    onValueCommit={(value) => onPaddingTopChange(value[0])}
                    min={0}
                    max={maxPadding}
                    step={1}
                    className="w-full"
                  />
                </div>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <label className="text-xs text-muted-foreground">Right</label>
                    <span className="text-xs text-muted-foreground font-mono tabular-nums">{padding.right}px</span>
                  </div>
                  <Slider
                    value={[padding.right]}
                    onValueChange={(value) => onPaddingRightChangeTransient?.(value[0])}
                    onValueCommit={(value) => onPaddingRightChange(value[0])}
                    min={0}
                    max={maxPadding}
                    step={1}
                    className="w-full"
                  />
                </div>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <label className="text-xs text-muted-foreground">Bottom</label>
                    <span className="text-xs text-muted-foreground font-mono tabular-nums">{padding.bottom}px</span>
                  </div>
                  <Slider
                    value={[padding.bottom]}
                    onValueChange={(value) => onPaddingBottomChangeTransient?.(value[0])}
                    onValueCommit={(value) => onPaddingBottomChange(value[0])}
                    min={0}
                    max={maxPadding}
                    step={1}
                    className="w-full"
                  />
                </div>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <label className="text-xs text-muted-foreground">Left</label>
                    <span className="text-xs text-muted-foreground font-mono tabular-nums">{padding.left}px</span>
                  </div>
                  <Slider
                    value={[padding.left]}
                    onValueChange={(value) => onPaddingLeftChangeTransient?.(value[0])}
                    onValueCommit={(value) => onPaddingLeftChange(value[0])}
                    min={0}
                    max={maxPadding}
                    step={1}
                    className="w-full"
                  />
                </div>
              </div>
            )}
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
