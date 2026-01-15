import { useState, useRef, useEffect, useCallback } from "react";
import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { toast } from "sonner";
import { Copy, Loader2, Undo2, Redo2, ImageDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { BackgroundSelector, gradientOptions } from "./editor/BackgroundSelector";
import { AssetGrid } from "./editor/AssetGrid";
import { EffectsPanel } from "./editor/EffectsPanel";
import { ImageRoundnessControl } from "./editor/ImageRoundnessControl";
import { AnnotationToolbar } from "./editor/AnnotationToolbar";
import { AnnotationCanvas } from "./editor/AnnotationCanvas";
import { PropertiesPanel } from "./editor/PropertiesPanel";
import { Annotation, ToolType } from "@/types/annotations";
import { usePreviewGenerator } from "@/hooks/usePreviewGenerator";
import { assetCategories } from "@/hooks/useEditorSettings";
import {
  useSettings,
  useAnnotations,
  useCanUndo,
  useCanRedo,
  editorActions,
} from "@/stores";

interface ImageEditorProps {
  imagePath: string;
  onSave: (editedImageData: string) => void;
  onCancel: () => void;
}

export function ImageEditor({ imagePath, onSave, onCancel }: ImageEditorProps) {
  // Use Zustand store with selectors for optimized re-renders
  const settings = useSettings();
  const annotations = useAnnotations();
  const canUndo = useCanUndo();
  const canRedo = useCanRedo();
  // Use stable actions object (not a hook, doesn't cause re-renders)
  const actions = editorActions;
  
  // Screenshot image state
  const [screenshotImage, setScreenshotImage] = useState<HTMLImageElement | null>(null);
  const [imageLoaded, setImageLoaded] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  
  // Save/copy state
  const [isSaving, setIsSaving] = useState(false);
  const [isCopying, setIsCopying] = useState(false);
  const [tempDir, setTempDir] = useState<string>("/private/tmp");
  
  // Annotation UI state (not part of undo/redo)
  const [selectedTool, setSelectedTool] = useState<ToolType>("select");
  const [selectedAnnotation, setSelectedAnnotation] = useState<Annotation | null>(null);
  
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // Preview generator hook
  const { previewUrl, error: previewError, renderHighQualityCanvas } = usePreviewGenerator({
    screenshotImage,
    settings,
    canvasRef,
    padding: settings.padding,
  });

  // Combined error
  const error = loadError || previewError;

  // Initialize store on mount
  useEffect(() => {
    editorActions.initialize();
  }, []);

  // Restore window state on mount
  useEffect(() => {
    const restoreWindowState = async () => {
      try {
        const appWindow = getCurrentWindow();
        await Promise.all([
          appWindow.setFullscreen(false),
          appWindow.setAlwaysOnTop(false),
        ]);
        await appWindow.setDecorations(true);
      } catch (err) {
        console.error("Failed to restore window decorations:", err);
      }
    };
    restoreWindowState();

    // Get the system temp directory
    invoke<string>("get_temp_directory")
      .then((dir) => setTempDir(dir))
      .catch((err) => console.error("Failed to get temp directory:", err));
  }, []);

  // Load main screenshot image
  useEffect(() => {
    setLoadError(null);
    setImageLoaded(false);
    setScreenshotImage(null);

    if (!imagePath) {
      setLoadError("No image path provided");
      return;
    }

    const img = new Image();
    img.onload = () => {
      setScreenshotImage(img);
      setImageLoaded(true);

      // Calculate smart default padding: 5% of average dimension, capped at 200px
      const avgDimension = (img.width + img.height) / 2;
      const defaultPadding = Math.min(Math.round(avgDimension * 0.05), 200);
      actions.setPaddingTransient(defaultPadding);
    };
    img.onerror = () => {
      setLoadError(`Failed to load image from: ${imagePath}`);
    };

    const assetUrl = convertFileSrc(imagePath);
    img.crossOrigin = "anonymous";
    img.src = assetUrl;

    return () => {
      img.onload = null;
      img.onerror = null;
    };
  }, [imagePath, actions]);

  // Save handler
  const handleSave = useCallback(async () => {
    if (!screenshotImage || isSaving || isCopying) return;
    
    setIsSaving(true);
    try {
      const highQualityCanvas = await renderHighQualityCanvas(annotations);
      
      if (!highQualityCanvas) {
        setIsSaving(false);
        return;
      }

      highQualityCanvas.toBlob(
        (blob) => {
          if (blob) {
            const reader = new FileReader();
            reader.onloadend = () => {
              onSave(reader.result as string);
              setIsSaving(false);
            };
            reader.onerror = () => {
              setLoadError("Failed to read image data");
              setIsSaving(false);
            };
            reader.readAsDataURL(blob);
          } else {
            setIsSaving(false);
          }
        },
        "image/png",
        1.0
      );
    } catch (err) {
      setLoadError(`Failed to save: ${err instanceof Error ? err.message : String(err)}`);
      setIsSaving(false);
    }
  }, [screenshotImage, annotations, renderHighQualityCanvas, onSave, isSaving, isCopying]);

  // Copy handler
  const handleCopy = useCallback(async () => {
    if (!screenshotImage || isSaving || isCopying) return;
    
    setIsCopying(true);
    try {
      const highQualityCanvas = await renderHighQualityCanvas(annotations);
      
      if (!highQualityCanvas) {
        setIsCopying(false);
        return;
      }

      const dataUrl = highQualityCanvas.toDataURL("image/png");
      
      await invoke<string>("save_edited_image", {
        imageData: dataUrl,
        saveDir: tempDir,
        copyToClip: true,
      });
      
      toast.success("Screenshot copied to clipboard!", {
        duration: 2000,
      });
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setLoadError(`Failed to copy: ${errorMessage}`);
      toast.error("Failed to copy", {
        description: errorMessage,
        duration: 3000,
      });
    } finally {
      setIsCopying(false);
    }
  }, [screenshotImage, annotations, renderHighQualityCanvas, isSaving, isCopying, tempDir]);

  // Annotation handlers
  const handleAnnotationAdd = useCallback((annotation: Annotation) => {
    actions.addAnnotation(annotation);
    setSelectedAnnotation(annotation);
    setSelectedTool("select");
  }, [actions]);

  const handleAnnotationUpdateTransient = useCallback((annotation: Annotation) => {
    actions.updateAnnotationTransient(annotation);
    setSelectedAnnotation(annotation);
  }, [actions]);

  const handleAnnotationUpdate = useCallback((annotation: Annotation) => {
    actions.updateAnnotation(annotation);
    setSelectedAnnotation(annotation);
  }, [actions]);

  const handleAnnotationDelete = useCallback((id: string) => {
    actions.deleteAnnotation(id);
    setSelectedAnnotation((prev) => prev?.id === id ? null : prev);
  }, [actions]);

  const handleDeleteSelected = useCallback(() => {
    if (selectedAnnotation) {
      handleAnnotationDelete(selectedAnnotation.id);
    }
  }, [selectedAnnotation, handleAnnotationDelete]);

  // Undo/Redo handlers
  const handleUndo = useCallback(() => {
    actions.undo();
    setSelectedAnnotation(null);
  }, [actions]);

  const handleRedo = useCallback(() => {
    actions.redo();
    setSelectedAnnotation(null);
  }, [actions]);

  // Delete annotation with keyboard
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }
      
      if (e.key === "Delete" || e.key === "Backspace") {
        if (selectedAnnotation) {
          e.preventDefault();
          handleAnnotationDelete(selectedAnnotation.id);
        }
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectedAnnotation, handleAnnotationDelete]);

  // Keyboard shortcuts for save/copy/undo/redo
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Skip if typing in input fields
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }

      // Save: Cmd+S
      if ((e.metaKey || e.ctrlKey) && e.key === "s") {
        e.preventDefault();
        if (imageLoaded && !isSaving && !isCopying) {
          handleSave();
        }
      }
      // Copy: Cmd+Shift+C
      if ((e.metaKey || e.ctrlKey) && e.key === "c" && e.shiftKey) {
        e.preventDefault();
        if (imageLoaded && !isSaving && !isCopying) {
          handleCopy();
        }
      }
      // Undo: Cmd+Z
      if ((e.metaKey || e.ctrlKey) && e.key === "z" && !e.shiftKey) {
        e.preventDefault();
        handleUndo();
      }
      // Redo: Cmd+Shift+Z or Cmd+Y
      if ((e.metaKey || e.ctrlKey) && ((e.key === "z" && e.shiftKey) || e.key === "y")) {
        e.preventDefault();
        handleRedo();
      }
      // Cancel: Escape
      if (e.key === "Escape") {
        onCancel();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [imageLoaded, isSaving, isCopying, handleSave, handleCopy, handleUndo, handleRedo, onCancel]);

  // Find selected gradient for BackgroundSelector
  const selectedGradientOption = gradientOptions.find(g => g.id === settings.gradientId) || gradientOptions[0];

  return (
    <div className="flex flex-col h-dvh bg-background text-foreground">
      <div className="flex items-center justify-between px-6 py-4 border-b border-border bg-card">
        <div className="flex items-center gap-4">
          <h2 className="text-xl font-semibold text-foreground text-balance">Edit Screenshot</h2>
          <TooltipProvider>
            <div className="flex gap-1">
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={handleUndo}
                    disabled={!canUndo}
                    className="text-muted-foreground hover:text-foreground hover:bg-secondary disabled:opacity-30 disabled:cursor-not-allowed"
                    aria-label="Undo"
                  >
                    <Undo2 className="size-4" aria-hidden="true" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  <p>Undo <kbd className="ml-1 text-xs opacity-70">⌘Z</kbd></p>
                </TooltipContent>
              </Tooltip>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={handleRedo}
                    disabled={!canRedo}
                    className="text-muted-foreground hover:text-foreground hover:bg-secondary disabled:opacity-30 disabled:cursor-not-allowed"
                    aria-label="Redo"
                  >
                    <Redo2 className="size-4" aria-hidden="true" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  <p>Redo <kbd className="ml-1 text-xs opacity-70">⌘⇧Z</kbd></p>
                </TooltipContent>
              </Tooltip>
            </div>
          </TooltipProvider>
        </div>
        <div className="flex gap-3">
          <Button 
            variant="cta"
            size="lg"
            onClick={onCancel}
          >
            Cancel
          </Button>
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button 
                  variant="cta"
                  onClick={handleCopy} 
                  disabled={!imageLoaded || isSaving || isCopying}
                  size="lg"
                  className="disabled:opacity-50"
                >
                  {isCopying ? (
                    <Loader2 className="size-4 animate-spin" aria-hidden="true" />
                  ) : (
                    <Copy className="size-4" aria-hidden="true" />
                  )}
                  <span>Copy</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent>
                <p>Copy to Clipboard</p>
              </TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button 
                  variant="cta"
                  onClick={handleSave} 
                  disabled={!imageLoaded || isSaving || isCopying}
                  size="lg"
                  className="disabled:opacity-50"
                >
                  {isSaving ? (
                    <Loader2 className="size-4 animate-spin" aria-hidden="true" />
                  ) : (
                    <ImageDown className="size-4" aria-hidden="true" />
                  )}
                  <span>Export</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent>
                <p>Save</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
      </div>

      <AnnotationToolbar
        selectedTool={selectedTool}
        onToolSelect={setSelectedTool}
        onDelete={selectedAnnotation ? handleDeleteSelected : undefined}
      />

      <div className="flex flex-1 overflow-hidden">
        <div className="w-72 shrink-0 border-r border-border bg-card flex flex-col overflow-hidden">
          <div className="shrink-0 border-b border-border">
            <PropertiesPanel annotation={selectedAnnotation} onUpdate={handleAnnotationUpdate} />
          </div>
          <div className="flex-1 overflow-y-auto [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none]">
            <div className="p-4 space-y-4">
              <BackgroundSelector
                backgroundType={settings.backgroundType as "transparent" | "white" | "black" | "gray" | "gradient" | "custom"}
                customColor={settings.customColor}
                selectedGradient={selectedGradientOption.id}
                onBackgroundTypeChange={actions.setBackgroundType}
                onCustomColorChange={actions.setCustomColor}
                onGradientSelect={actions.setGradient}
              />

              <AssetGrid
                categories={assetCategories}
                selectedImage={settings.selectedImageSrc}
                backgroundType={settings.backgroundType}
                onImageSelect={actions.handleImageSelect}
              />

              <EffectsPanel
                noiseAmount={settings.noiseAmount}
                padding={settings.padding}
                shadow={settings.shadow}
                onNoiseChangeTransient={actions.setNoiseAmountTransient}
                onPaddingChangeTransient={actions.setPaddingTransient}
                onShadowBlurChangeTransient={actions.setShadowBlurTransient}
                onShadowOffsetXChangeTransient={actions.setShadowOffsetXTransient}
                onShadowOffsetYChangeTransient={actions.setShadowOffsetYTransient}
                onShadowOpacityChangeTransient={actions.setShadowOpacityTransient}
                onNoiseChange={actions.setNoiseAmount}
                onPaddingChange={actions.setPadding}
                onShadowBlurChange={actions.setShadowBlur}
                onShadowOffsetXChange={actions.setShadowOffsetX}
                onShadowOffsetYChange={actions.setShadowOffsetY}
                onShadowOpacityChange={actions.setShadowOpacity}
              />

              <ImageRoundnessControl
                borderRadius={settings.borderRadius}
                onBorderRadiusChangeTransient={actions.setBorderRadiusTransient}
                onBorderRadiusChange={actions.setBorderRadius}
              />

              {error && (
                <Card className="bg-red-950/30 border-red-800/50">
                  <CardContent className="pt-6">
                    <div className="text-sm text-red-400 text-pretty">
                      <strong className="block mb-1 text-red-300">Error:</strong>
                      {error}
                      <br />
                      <small className="text-foreground0 break-all mt-2 block text-pretty">Path: {imagePath}</small>
                    </div>
                  </CardContent>
                </Card>
              )}
            </div>
          </div>
        </div>

        <div className="flex-1 flex items-center justify-center p-6 bg-background overflow-hidden min-w-0 min-h-0">
          <div className="w-full h-full flex items-center justify-center min-w-0 min-h-0">
            {previewUrl ? (
              <AnnotationCanvas
                annotations={annotations}
                selectedAnnotation={selectedAnnotation}
                selectedTool={selectedTool}
                previewUrl={previewUrl}
                showTransparencyGrid={settings.backgroundType === "transparent"}
                onAnnotationAdd={handleAnnotationAdd}
                onAnnotationUpdateTransient={handleAnnotationUpdateTransient}
                onAnnotationUpdate={handleAnnotationUpdate}
                onAnnotationSelect={setSelectedAnnotation}
                onAnnotationDelete={handleAnnotationDelete}
              />
            ) : imageLoaded ? (
              <div className="text-muted-foreground text-base text-pretty">Generating preview...</div>
            ) : error ? (
              <div className="text-center text-red-400 p-5">
                <p className="mb-2 text-base font-medium text-balance">Could not load image</p>
                <small className="text-foreground0 text-xs text-pretty">{error}</small>
              </div>
            ) : (
              <div className="text-muted-foreground text-base text-pretty">Loading image...</div>
            )}
            <canvas ref={canvasRef} style={{ display: "none" }} />
          </div>
        </div>
      </div>
    </div>
  );
}
