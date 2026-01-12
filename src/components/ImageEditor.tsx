import { useState, useRef, useEffect, useCallback } from "react";
import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { toast } from "sonner";
import { Copy, Save, Loader2 } from "lucide-react";
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
import { useEditorSettings, usePreviewGenerator, assetCategories } from "@/hooks";

interface ImageEditorProps {
  imagePath: string;
  onSave: (editedImageData: string) => void;
  onCancel: () => void;
}

export function ImageEditor({ imagePath, onSave, onCancel }: ImageEditorProps) {
  // Use custom hooks for settings and preview generation
  const [settings, settingsActions] = useEditorSettings();
  
  // Screenshot image state
  const [screenshotImage, setScreenshotImage] = useState<HTMLImageElement | null>(null);
  const [imageLoaded, setImageLoaded] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  
  // Save/copy state
  const [isSaving, setIsSaving] = useState(false);
  const [isCopying, setIsCopying] = useState(false);
  
  // Annotation state
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [selectedTool, setSelectedTool] = useState<ToolType>("select");
  const [selectedAnnotation, setSelectedAnnotation] = useState<Annotation | null>(null);
  
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // Preview generator hook
  const { previewUrl, error: previewError, renderHighQualityCanvas } = usePreviewGenerator({
    screenshotImage,
    settings,
    canvasRef,
    padding: 100,
  });

  // Combined error
  const error = loadError || previewError;

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
  }, [imagePath]);

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
        saveDir: "/tmp",
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
  }, [screenshotImage, annotations, renderHighQualityCanvas, isSaving, isCopying]);

  // Keyboard shortcuts for save/copy
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "s") {
        e.preventDefault();
        if (imageLoaded && !isSaving && !isCopying) {
          handleSave();
        }
      }
      if ((e.metaKey || e.ctrlKey) && e.key === "c" && e.shiftKey) {
        e.preventDefault();
        if (imageLoaded && !isSaving && !isCopying) {
          handleCopy();
        }
      }
      if (e.key === "Escape") {
        onCancel();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [imageLoaded, isSaving, isCopying, handleSave, handleCopy, onCancel]);

  // Annotation handlers
  const handleAnnotationAdd = useCallback((annotation: Annotation) => {
    setAnnotations((prev) => [...prev, annotation]);
    setSelectedAnnotation(annotation);
    setSelectedTool("select");
  }, []);

  const handleAnnotationUpdate = useCallback((annotation: Annotation) => {
    setAnnotations((prev) => prev.map((ann) => (ann.id === annotation.id ? annotation : ann)));
    setSelectedAnnotation(annotation);
  }, []);

  const handleAnnotationDelete = useCallback((id: string) => {
    setAnnotations((prev) => prev.filter((ann) => ann.id !== id));
    setSelectedAnnotation((prev) => prev?.id === id ? null : prev);
  }, []);

  const handleDeleteSelected = useCallback(() => {
    if (selectedAnnotation) {
      handleAnnotationDelete(selectedAnnotation.id);
    }
  }, [selectedAnnotation, handleAnnotationDelete]);

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

  // Find selected gradient for BackgroundSelector
  const selectedGradientOption = gradientOptions.find(g => g.id === settings.gradientId) || gradientOptions[0];

  return (
    <div className="flex flex-col h-dvh bg-zinc-950 text-zinc-50">
      <div className="flex items-center justify-between px-6 py-4 border-b border-zinc-800 bg-zinc-900">
        <h2 className="text-xl font-semibold text-zinc-50 text-balance">Edit Screenshot</h2>
        <div className="flex gap-3">
          <Button 
            variant="outline" 
            onClick={onCancel}
            className="border-zinc-700 text-zinc-300 hover:bg-zinc-800 hover:text-zinc-50"
          >
            Cancel
          </Button>
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button 
                  variant="outline" 
                  onClick={handleCopy} 
                  disabled={!imageLoaded || isSaving || isCopying}
                  size="icon"
                  className="border-zinc-700 text-zinc-300 hover:bg-zinc-800 hover:text-zinc-50 disabled:opacity-50"
                >
                  {isCopying ? (
                    <Loader2 className="size-4 animate-spin" aria-hidden="true" />
                  ) : (
                    <Copy className="size-4" aria-hidden="true" />
                  )}
                  <span className="sr-only">Copy to clipboard</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent>
                <p>Copy to Clipboard</p>
              </TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button 
                  variant="outline" 
                  onClick={handleSave} 
                  disabled={!imageLoaded || isSaving || isCopying}
                  size="icon"
                  className="border-zinc-700 text-zinc-300 hover:bg-zinc-800 hover:text-zinc-50 disabled:opacity-50"
                >
                  {isSaving ? (
                    <Loader2 className="size-4 animate-spin" aria-hidden="true" />
                  ) : (
                    <Save className="size-4" aria-hidden="true" />
                  )}
                  <span className="sr-only">Save image</span>
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
        <div className="w-72 shrink-0 border-r border-zinc-800 bg-zinc-900 flex flex-col overflow-hidden">
          <div className="shrink-0 border-b border-zinc-800">
            <PropertiesPanel annotation={selectedAnnotation} onUpdate={handleAnnotationUpdate} />
          </div>
          <div className="flex-1 overflow-y-auto [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none]">
            <div className="p-4 space-y-4">
              <BackgroundSelector
                backgroundType={settings.backgroundType as "transparent" | "white" | "black" | "gray" | "gradient" | "custom"}
                customColor={settings.customColor}
                selectedGradient={selectedGradientOption.id}
                onBackgroundTypeChange={settingsActions.setBackgroundType}
                onCustomColorChange={settingsActions.setCustomColor}
                onGradientSelect={settingsActions.setGradient}
              />

              <AssetGrid
                categories={assetCategories}
                selectedImage={settings.selectedImageSrc}
                backgroundType={settings.backgroundType}
                onImageSelect={settingsActions.handleImageSelect}
              />

              <EffectsPanel
                blurAmount={settings.blurAmount}
                noiseAmount={settings.noiseAmount}
                onBlurChange={settingsActions.setBlurAmount}
                onNoiseChange={settingsActions.setNoiseAmount}
              />

              <ImageRoundnessControl
                borderRadius={settings.borderRadius}
                onBorderRadiusChange={settingsActions.setBorderRadius}
              />

              {error && (
                <Card className="bg-red-950/30 border-red-800/50">
                  <CardContent className="pt-6">
                    <div className="text-sm text-red-400 text-pretty">
                      <strong className="block mb-1 text-red-300">Error:</strong>
                      {error}
                      <br />
                      <small className="text-zinc-500 break-all mt-2 block text-pretty">Path: {imagePath}</small>
                    </div>
                  </CardContent>
                </Card>
              )}
            </div>
          </div>
        </div>

        <div className="flex-1 flex items-center justify-center p-6 bg-zinc-950 overflow-hidden min-w-0 min-h-0">
          <div className="w-full h-full flex items-center justify-center min-w-0 min-h-0">
            {previewUrl ? (
              <AnnotationCanvas
                annotations={annotations}
                selectedAnnotation={selectedAnnotation}
                selectedTool={selectedTool}
                previewUrl={previewUrl}
                onAnnotationAdd={handleAnnotationAdd}
                onAnnotationUpdate={handleAnnotationUpdate}
                onAnnotationSelect={setSelectedAnnotation}
                onAnnotationDelete={handleAnnotationDelete}
              />
            ) : imageLoaded ? (
              <div className="text-zinc-400 text-base text-pretty">Generating preview...</div>
            ) : error ? (
              <div className="text-center text-red-400 p-5">
                <p className="mb-2 text-base font-medium text-balance">Could not load image</p>
                <small className="text-zinc-500 text-xs text-pretty">{error}</small>
              </div>
            ) : (
              <div className="text-zinc-400 text-base text-pretty">Loading image...</div>
            )}
            <canvas ref={canvasRef} style={{ display: "none" }} />
          </div>
        </div>
      </div>
    </div>
  );
}
