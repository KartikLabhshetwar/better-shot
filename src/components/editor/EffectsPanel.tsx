import { memo, useState } from "react";
import { toast } from "sonner";
import { Check, Bookmark, Link2, Unlink2, RotateCcw } from "lucide-react";
import { Slider } from "@/components/ui/slider";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import type { ShadowSettings } from "@/stores/editorStore";

interface EffectsPanelProps {
  blurAmount: number;
  noiseAmount: number;
  paddingTop: number;
  paddingBottom: number;
  paddingLeft: number;
  paddingRight: number;
  shadow: ShadowSettings;
  // Transient handlers (during drag) - for visual feedback
  onBlurAmountChangeTransient?: (value: number) => void;
  onNoiseChangeTransient?: (value: number) => void;
  onPaddingTopChangeTransient?: (value: number) => void;
  onPaddingBottomChangeTransient?: (value: number) => void;
  onPaddingLeftChangeTransient?: (value: number) => void;
  onPaddingRightChangeTransient?: (value: number) => void;
  onAllPaddingChangeTransient?: (value: number) => void;
  onShadowBlurChangeTransient?: (value: number) => void;
  onShadowOffsetXChangeTransient?: (value: number) => void;
  onShadowOffsetYChangeTransient?: (value: number) => void;
  onShadowOpacityChangeTransient?: (value: number) => void;
  // Commit handlers (on release) - for state/history
  onBlurAmountChange: (value: number) => void;
  onNoiseChange: (value: number) => void;
  onPaddingTopChange: (value: number) => void;
  onPaddingBottomChange: (value: number) => void;
  onPaddingLeftChange: (value: number) => void;
  onPaddingRightChange: (value: number) => void;
  onAllPaddingChange: (value: number) => void;
  onShadowBlurChange: (value: number) => void;
  onShadowOffsetXChange: (value: number) => void;
  onShadowOffsetYChange: (value: number) => void;
  onShadowOpacityChange: (value: number) => void;
  // Persist settings as defaults
  onSaveAsDefaults?: () => Promise<void>;
  // Reset to default padding
  onResetPadding?: () => void;
}

export const EffectsPanel = memo(function EffectsPanel({
  blurAmount,
  noiseAmount,
  paddingTop,
  paddingBottom,
  paddingLeft,
  paddingRight,
  shadow,
  onBlurAmountChangeTransient,
  onNoiseChangeTransient,
  onPaddingTopChangeTransient,
  onPaddingBottomChangeTransient,
  onPaddingLeftChangeTransient,
  onPaddingRightChangeTransient,
  onAllPaddingChangeTransient,
  onShadowBlurChangeTransient,
  onShadowOffsetXChangeTransient,
  onShadowOffsetYChangeTransient,
  onShadowOpacityChangeTransient,
  onBlurAmountChange,
  onNoiseChange,
  onPaddingTopChange,
  onPaddingBottomChange,
  onPaddingLeftChange,
  onPaddingRightChange,
  onAllPaddingChange,
  onShadowBlurChange,
  onShadowOffsetXChange,
  onShadowOffsetYChange,
  onShadowOpacityChange,
  onSaveAsDefaults,
  onResetPadding,
}: EffectsPanelProps) {
  const maxPadding = 400;
  const [isSaving, setIsSaving] = useState(false);
  const [justSaved, setJustSaved] = useState(false);
  const [isLinked, setIsLinked] = useState(false);

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

  const handleLinkToggle = () => {
    setIsLinked(!isLinked);
  };

  const handleResetPadding = () => {
    onResetPadding?.();
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
                    <label className="text-xs text-muted-foreground font-medium cursor-help">Padding</label>
                  </TooltipTrigger>
                  <TooltipContent side="right" className="max-w-48">
                    <p className="text-xs text-pretty">Adjust the padding around the captured image. Use the link button to sync all sides.</p>
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
              <div className="flex items-center gap-1">
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        onClick={handleResetPadding}
                        className="p-1 rounded hover:bg-secondary transition-colors"
                        aria-label="Reset padding to default"
                      >
                        <RotateCcw className="size-3.5 text-muted-foreground hover:text-foreground transition-colors" />
                      </button>
                    </TooltipTrigger>
                    <TooltipContent>
                      <p>Reset padding to default (10% of image size)</p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
                <div className="w-px h-4 bg-border mx-1" />
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        onClick={handleLinkToggle}
                        className={`p-1 rounded transition-colors ${isLinked ? 'bg-secondary text-foreground' : 'hover:bg-secondary text-muted-foreground'}`}
                        aria-label={isLinked ? "Unlink padding values" : "Link all padding values"}
                      >
                        {isLinked ? (
                          <Link2 className="size-3.5" />
                        ) : (
                          <Unlink2 className="size-3.5" />
                        )}
                      </button>
                    </TooltipTrigger>
                    <TooltipContent>
                      <p>{isLinked ? "Unlink padding values (change independently)" : "Link all padding values (change together)"}</p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              </div>
            </div>

            {isLinked && (
              <div className="text-xs text-muted-foreground bg-secondary/50 rounded px-2 py-1.5">
                All padding sides are synced - change one, all update
              </div>
            )}

              <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <label className="text-xs text-muted-foreground font-medium">Top</label>
                  <span className="text-xs text-muted-foreground font-mono tabular-nums">{paddingTop}px</span>
                </div>
                <Slider
                  value={[paddingTop]}
                  onValueChange={(value) => {
                    if (isLinked) {
                      onAllPaddingChangeTransient?.(value[0]);
                    } else {
                      onPaddingTopChangeTransient?.(value[0]);
                    }
                  }}
                  onValueCommit={(value) => {
                    if (isLinked) {
                      onAllPaddingChange(value[0]);
                    } else {
                      onPaddingTopChange(value[0]);
                    }
                  }}
                  min={0}
                  max={maxPadding}
                  step={1}
                  className="w-full"
                />
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <label className="text-xs text-muted-foreground font-medium">Bottom</label>
                  <span className="text-xs text-muted-foreground font-mono tabular-nums">{paddingBottom}px</span>
                </div>
                <Slider
                  value={[paddingBottom]}
                  onValueChange={(value) => {
                    if (isLinked) {
                      onAllPaddingChangeTransient?.(value[0]);
                    } else {
                      onPaddingBottomChangeTransient?.(value[0]);
                    }
                  }}
                  onValueCommit={(value) => {
                    if (isLinked) {
                      onAllPaddingChange(value[0]);
                    } else {
                      onPaddingBottomChange(value[0]);
                    }
                  }}
                  min={0}
                  max={maxPadding}
                  step={1}
                  className="w-full"
                />
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <label className="text-xs text-muted-foreground font-medium">Left</label>
                  <span className="text-xs text-muted-foreground font-mono tabular-nums">{paddingLeft}px</span>
                </div>
                <Slider
                  value={[paddingLeft]}
                  onValueChange={(value) => {
                    if (isLinked) {
                      onAllPaddingChangeTransient?.(value[0]);
                    } else {
                      onPaddingLeftChangeTransient?.(value[0]);
                    }
                  }}
                  onValueCommit={(value) => {
                    if (isLinked) {
                      onAllPaddingChange(value[0]);
                    } else {
                      onPaddingLeftChange(value[0]);
                    }
                  }}
                  min={0}
                  max={maxPadding}
                  step={1}
                  className="w-full"
                />
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <label className="text-xs text-muted-foreground font-medium">Right</label>
                  <span className="text-xs text-muted-foreground font-mono tabular-nums">{paddingRight}px</span>
                </div>
                <Slider
                  value={[paddingRight]}
                  onValueChange={(value) => {
                    if (isLinked) {
                      onAllPaddingChangeTransient?.(value[0]);
                    } else {
                      onPaddingRightChangeTransient?.(value[0]);
                    }
                  }}
                  onValueCommit={(value) => {
                    if (isLinked) {
                      onAllPaddingChange(value[0]);
                    } else {
                      onPaddingRightChange(value[0]);
                    }
                  }}
                  min={0}
                  max={maxPadding}
                  step={1}
                  className="w-full"
                />
              </div>
            </div>
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
