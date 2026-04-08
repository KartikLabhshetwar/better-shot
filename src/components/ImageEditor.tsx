import { useState, useRef, useEffect, useCallback } from "react";
import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { toast } from "sonner";
import {
  Copy, Loader2, Redo2, Undo2,
  Circle, Square, Minus, ArrowUpRight, Type, Hash, MousePointer2, Scan, Trash2,
  Palette, Layers, Maximize2, Move, Settings2, Image as ImageIcon, X, RotateCcw,
  PanelLeftClose, PanelLeftOpen,
} from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { BackgroundSelector, gradientOptions } from "./editor/BackgroundSelector";
import { AssetGrid } from "./editor/AssetGrid";
import { EffectsPanel } from "./editor/EffectsPanel";
import { ImageRoundnessControl } from "./editor/ImageRoundnessControl";
import { AnnotationCanvas } from "./editor/AnnotationCanvas";
import { PropertiesPanel } from "./editor/PropertiesPanel";
import { BackgroundSizePanel } from "./editor/BackgroundSizePanel";
import { ImagePositionPanel } from "./editor/ImagePositionPanel";
import { ExportSettingsPanel } from "./editor/ExportSettingsPanel";
import { Annotation, ToolType } from "@/types/annotations";
import { usePreviewGenerator } from "@/hooks/usePreviewGenerator";
import { assetCategories } from "@/hooks/useEditorSettings";
import {
  useSettings,
  useAnnotations,
  useCanUndo,
  useCanRedo,
  editorActions,
  clearPersistedEditorSettings,
} from "@/stores";

interface ImageEditorProps {
  imagePath: string;
  onSave: (editedImageData: string, filenameOverride?: string) => void;
  onCancel: () => void;
  saveDir: string;
  onSaveDirChange: (value: string) => void;
}

type SidebarTab = "image" | "background" | "effects" | "size" | "position" | "export" | "annotation";

const annotationTools: Array<{ type: ToolType; icon: React.ReactNode; label: string; shortcut?: string }> = [
  { type: "select",    icon: <MousePointer2 className="size-[15px]" />, label: "Select",    shortcut: "V" },
  { type: "circle",   icon: <Circle className="size-[15px]" />,        label: "Circle",    shortcut: "C" },
  { type: "rectangle",icon: <Square className="size-[15px]" />,        label: "Rectangle", shortcut: "R" },
  { type: "line",     icon: <Minus className="size-[15px]" />,         label: "Line",      shortcut: "L" },
  { type: "arrow",    icon: <ArrowUpRight className="size-[15px]" />,  label: "Arrow",     shortcut: "A" },
  { type: "number",   icon: <Hash className="size-[15px]" />,          label: "Number",    shortcut: "N" },
  { type: "text",     icon: <Type className="size-[15px]" />,          label: "Text",      shortcut: "T" },
  { type: "blur",     icon: <Scan className="size-[15px]" />,          label: "Blur",      shortcut: "B" },
];

const sidebarTabs: Array<{ id: SidebarTab; icon: React.ReactNode; label: string }> = [
  { id: "image",      icon: <ImageIcon className="size-4" />,      label: "Image" },
  { id: "background", icon: <Palette className="size-4" />,    label: "BG" },
  { id: "effects",    icon: <Layers className="size-4" />,     label: "Effects" },
  { id: "size",       icon: <Maximize2 className="size-4" />,  label: "Size" },
  { id: "position",   icon: <Move className="size-4" />,       label: "Position" },
  { id: "export",     icon: <Settings2 className="size-4" />,  label: "Export" },
];

export function ImageEditor({
  imagePath,
  onSave,
  onCancel,
  saveDir,
  onSaveDirChange,
}: ImageEditorProps) {
  const settings = useSettings();
  const annotations = useAnnotations();
  const canUndo = useCanUndo();
  const canRedo = useCanRedo();
  const actions = editorActions;

  const [screenshotImage, setScreenshotImage] = useState<HTMLImageElement | null>(null);
  const [imageLoaded, setImageLoaded] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [isSaving, setIsSaving] = useState(false);
  const [isCopying, setIsCopying] = useState(false);
  const [tempDir, setTempDir] = useState<string>("/private/tmp");
  const [exportName, setExportName] = useState<string>("");
  const [isResettingConfig, setIsResettingConfig] = useState(false);

  const [selectedTool, setSelectedTool] = useState<ToolType>("select");
  const [selectedAnnotation, setSelectedAnnotation] = useState<Annotation | null>(null);
  const [activeTab, setActiveTab] = useState<SidebarTab>("image");
  const [sidebarVisible, setSidebarVisible] = useState(true);

  // If annotation selected, auto-show annotation tab info
  const [, setShowAnnotationPanel] = useState(false);

  const canvasRef = useRef<HTMLCanvasElement>(null);

  const { previewUrl, error: previewError, renderHighQualityCanvas } = usePreviewGenerator({
    screenshotImage,
    settings,
    canvasRef,
    padding: settings.padding,
  });

  const error = loadError || previewError;

  useEffect(() => { editorActions.initialize(); }, []);
  useEffect(() => { editorActions.reset(); editorActions.initialize(); }, [imagePath]);

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
    invoke<string>("get_temp_directory")
      .then((dir) => setTempDir(dir))
      .catch((err) => console.error("Failed to get temp directory:", err));
  }, []);

  useEffect(() => {
    setLoadError(null);
    setImageLoaded(false);
    setScreenshotImage(null);
    if (!imagePath) { setLoadError("No image path provided"); return; }
    const img = new Image();
    img.onload = () => {
      setScreenshotImage(img);
      setImageLoaded(true);
      const avgDimension = (img.width + img.height) / 2;
      const defaultPadding = Math.min(Math.round(avgDimension * 0.05), 200);
      actions.setPaddingTransient(defaultPadding);
    };
    img.onerror = () => { setLoadError(`Failed to load image from: ${imagePath}`); };
    const assetUrl = convertFileSrc(imagePath);
    img.crossOrigin = "anonymous";
    img.src = assetUrl;
    return () => { img.onload = null; img.onerror = null; };
  }, [imagePath, actions]);

  const handleSave = useCallback(async () => {
    if (!screenshotImage || isSaving || isCopying) return;
    setIsSaving(true);
    try {
      const highQualityCanvas = await renderHighQualityCanvas(annotations);
      if (!highQualityCanvas) { setIsSaving(false); return; }
      highQualityCanvas.toBlob((blob) => {
        if (blob) {
          const reader = new FileReader();
          reader.onloadend = () => {
            onSave(reader.result as string, exportName.trim() !== "" ? exportName.trim() : undefined);
            setIsSaving(false);
          };
          reader.onerror = () => { setLoadError("Failed to read image data"); setIsSaving(false); };
          reader.readAsDataURL(blob);
        } else { setIsSaving(false); }
      }, "image/png", 1.0);
    } catch (err) {
      setLoadError(`Failed to save: ${err instanceof Error ? err.message : String(err)}`);
      setIsSaving(false);
    }
  }, [screenshotImage, annotations, renderHighQualityCanvas, onSave, isSaving, isCopying, exportName]);

  const handleCopy = useCallback(async () => {
    if (!screenshotImage || isSaving || isCopying) return;
    setIsCopying(true);
    try {
      const highQualityCanvas = await renderHighQualityCanvas(annotations);
      if (!highQualityCanvas) { setIsCopying(false); return; }
      const dataUrl = highQualityCanvas.toDataURL("image/png");
      await invoke<string>("save_edited_image", {
        imageData: dataUrl, saveDir: tempDir, copyToClip: true, prefix: "bettershot",
      });
      toast.success("Copied to clipboard", { duration: 2000 });
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      setLoadError(`Failed to copy: ${errorMessage}`);
      toast.error("Failed to copy", { description: errorMessage, duration: 3000 });
    } finally { setIsCopying(false); }
  }, [screenshotImage, annotations, renderHighQualityCanvas, isSaving, isCopying, tempDir]);

  const handleBrowseSaveDir = useCallback(async () => {
    try {
      const selectedPath = await invoke<string | null>("select_directory_dialog", { defaultPath: saveDir || undefined });
      if (selectedPath) onSaveDirChange(selectedPath);
    } catch (err) {
      console.error("Failed to open directory picker:", err);
      toast.error("Unable to open directory picker");
    }
  }, [saveDir, onSaveDirChange]);

  const handleResetToDefaults = useCallback(async () => {
    if (isResettingConfig) return;
    setIsResettingConfig(true);
    try {
      const cleared = await clearPersistedEditorSettings();
      if (!cleared) throw new Error("Unable to clear saved configuration");
      actions.reset();
      await actions.initialize();
      toast.success("Reset to defaults");
    } catch (err) {
      console.error("Failed to reset configuration:", err);
      toast.error("Unable to reset configuration");
    } finally { setIsResettingConfig(false); }
  }, [actions, isResettingConfig]);

  const handleAnnotationAdd = useCallback((annotation: Annotation) => {
    actions.addAnnotation(annotation);
    setSelectedAnnotation(annotation);
    setShowAnnotationPanel(true);
    if (annotation.type !== "number") setSelectedTool("select");
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
    setShowAnnotationPanel(false);
  }, [actions]);

  const handleDeleteSelected = useCallback(() => {
    if (selectedAnnotation) handleAnnotationDelete(selectedAnnotation.id);
  }, [selectedAnnotation, handleAnnotationDelete]);

  const handleUndo = useCallback(() => { actions.undo(); setSelectedAnnotation(null); setShowAnnotationPanel(false); }, [actions]);
  const handleRedo = useCallback(() => { actions.redo(); setSelectedAnnotation(null); setShowAnnotationPanel(false); }, [actions]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === "Delete" || e.key === "Backspace") {
        if (selectedAnnotation) { e.preventDefault(); handleAnnotationDelete(selectedAnnotation.id); }
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectedAnnotation, handleAnnotationDelete]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if ((e.metaKey || e.ctrlKey) && e.key === "s") { e.preventDefault(); if (imageLoaded && !isSaving && !isCopying) handleSave(); }
      if ((e.metaKey || e.ctrlKey) && e.key === "c" && e.shiftKey) { e.preventDefault(); if (imageLoaded && !isSaving && !isCopying) handleCopy(); }
      if ((e.metaKey || e.ctrlKey) && e.key === "z" && !e.shiftKey) { e.preventDefault(); handleUndo(); }
      if ((e.metaKey || e.ctrlKey) && ((e.key === "z" && e.shiftKey) || e.key === "y")) { e.preventDefault(); handleRedo(); }
      if (e.key === "Escape") onCancel();
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [imageLoaded, isSaving, isCopying, handleSave, handleCopy, handleUndo, handleRedo, onCancel]);

  const selectedGradientOption = gradientOptions.find(g => g.id === settings.gradientId) || gradientOptions[0];

  const canReposition = !!(screenshotImage &&
    (screenshotImage.width > ((settings.canvasDimensions.width > 0 ? settings.canvasDimensions.width : screenshotImage.width + settings.padding * 2)) ||
     screenshotImage.height > ((settings.canvasDimensions.height > 0 ? settings.canvasDimensions.height : screenshotImage.height + settings.padding * 2))));

  return (
    <div className="flex flex-col h-dvh" style={{ background: 'oklch(0.115 0.008 250)', fontFamily: 'var(--font-sans)' }}>

      {/* ─── Header ─── */}
      <header style={{
        height: 48,
        background: 'oklch(0.155 0.008 250)',
        borderBottom: '1px solid oklch(0.22 0.009 250)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 14px',
        gap: 12,
        flexShrink: 0,
      }}>
        {/* Left: title + undo/redo */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: 'oklch(0.82 0.01 250)', letterSpacing: '-0.01em' }}>
            Better Shot
          </span>
          <div style={{ width: 1, height: 16, background: 'oklch(0.26 0.009 250)' }} />
          <TooltipProvider delayDuration={400}>
            <div style={{ display: 'flex', gap: 2 }}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleUndo}
                    disabled={!canUndo}
                    className="tool-btn"
                    style={{ opacity: canUndo ? 1 : 0.3 }}
                    aria-label="Undo"
                  >
                    <Undo2 className="size-[15px]" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="text-xs">Undo <kbd className="ml-1 opacity-60">⌘Z</kbd></TooltipContent>
              </Tooltip>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleRedo}
                    disabled={!canRedo}
                    className="tool-btn"
                    style={{ opacity: canRedo ? 1 : 0.3 }}
                    aria-label="Redo"
                  >
                    <Redo2 className="size-[15px]" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="text-xs">Redo <kbd className="ml-1 opacity-60">⌘⇧Z</kbd></TooltipContent>
              </Tooltip>
            </div>
          </TooltipProvider>
        </div>

        {/* Center: annotation tools */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 2,
          background: 'oklch(0.135 0.008 250)',
          border: '1px solid oklch(0.22 0.009 250)',
          borderRadius: 8,
          padding: '3px 4px',
        }}>
          <TooltipProvider delayDuration={300}>
            {annotationTools.map((tool) => (
              <Tooltip key={tool.type}>
                <TooltipTrigger asChild>
                  <button
                    onClick={() => setSelectedTool(tool.type)}
                    className={`tool-btn ${selectedTool === tool.type ? 'active' : ''}`}
                    aria-label={tool.label}
                  >
                    {tool.icon}
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="text-xs">
                  {tool.label}
                  {tool.shortcut && <kbd className="ml-1.5 opacity-50">{tool.shortcut}</kbd>}
                </TooltipContent>
              </Tooltip>
            ))}
            {selectedAnnotation && (
              <>
                <div style={{ width: 1, height: 16, background: 'oklch(0.26 0.009 250)', margin: '0 4px' }} />
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      onClick={handleDeleteSelected}
                      className="tool-btn"
                      style={{ color: 'oklch(0.62 0.18 25)' }}
                      aria-label="Delete annotation"
                    >
                      <Trash2 className="size-[15px]" />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom" className="text-xs">Delete</TooltipContent>
                </Tooltip>
              </>
            )}
          </TooltipProvider>
        </div>

        {/* Right: actions */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <button className="header-btn header-btn-ghost" onClick={onCancel} aria-label="Cancel">
            <X className="size-[13px]" />
            <span>Cancel</span>
          </button>
          <TooltipProvider delayDuration={400}>
            <Tooltip>
              <TooltipTrigger asChild>
                <button
                  className="header-btn header-btn-secondary"
                  onClick={handleCopy}
                  disabled={!imageLoaded || isSaving || isCopying}
                  aria-label="Copy to clipboard"
                >
                  {isCopying
                    ? <Loader2 className="size-[13px] animate-spin" />
                    : <Copy className="size-[13px]" />
                  }
                  <span>Copy</span>
                </button>
              </TooltipTrigger>
              <TooltipContent side="bottom" className="text-xs">Copy to Clipboard <kbd className="ml-1 opacity-60">⌘⇧C</kbd></TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
      </header>

      {/* ─── Body ─── */}
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden', minHeight: 0 }}>

        {/* ─── Tab Nav Rail ─── */}
        <nav style={{
          width: 54,
          background: 'oklch(0.155 0.008 250)',
          borderRight: '1px solid oklch(0.20 0.009 250)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          padding: '8px 0',
          gap: 2,
          flexShrink: 0,
        }}>
          <TooltipProvider delayDuration={300}>
            {sidebarTabs.map((tab) => (
              <Tooltip key={tab.id}>
                <TooltipTrigger asChild>
                  <button
                    onClick={() => setActiveTab(tab.id)}
                    className={`tab-nav-btn ${activeTab === tab.id ? 'active' : ''}`}
                    aria-label={tab.label}
                  >
                    {tab.icon}
                    <span style={{ fontSize: 8, letterSpacing: '0.03em', lineHeight: 1 }}>{tab.label}</span>
                  </button>
                </TooltipTrigger>
                <TooltipContent side="right" className="text-xs">{tab.label}</TooltipContent>
              </Tooltip>
            ))}

            {/* Spacer */}
            <div style={{ flex: 1 }} />

            {/* Toggle panel visibility */}
            <Tooltip>
              <TooltipTrigger asChild>
                <button
                  onClick={() => setSidebarVisible(v => !v)}
                  className="tab-nav-btn"
                  aria-label={sidebarVisible ? 'Collapse panel' : 'Expand panel'}
                >
                  {sidebarVisible
                    ? <PanelLeftClose className="size-4" />
                    : <PanelLeftOpen className="size-4" />
                  }
                  <span style={{ fontSize: 8, letterSpacing: '0.03em', lineHeight: 1 }}>
                    {sidebarVisible ? 'Hide' : 'Show'}
                  </span>
                </button>
              </TooltipTrigger>
              <TooltipContent side="right" className="text-xs">
                {sidebarVisible ? 'Collapse panel' : 'Expand panel'}
              </TooltipContent>
            </Tooltip>

            {/* Reset button at bottom */}
            <Tooltip>
              <TooltipTrigger asChild>
                <button
                  onClick={handleResetToDefaults}
                  disabled={isResettingConfig}
                  className="tab-nav-btn"
                  aria-label="Reset to defaults"
                  style={{ opacity: isResettingConfig ? 0.4 : 1 }}
                >
                  <RotateCcw className="size-4" />
                  <span style={{ fontSize: 8, letterSpacing: '0.03em', lineHeight: 1 }}>Reset</span>
                </button>
              </TooltipTrigger>
              <TooltipContent side="right" className="text-xs">Reset to defaults</TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </nav>

        {/* ─── Panel Content ─── */}
        {sidebarVisible && <div style={{
          width: 240,
          background: 'oklch(0.155 0.008 250)',
          borderRight: '1px solid oklch(0.20 0.009 250)',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
          flexShrink: 0,
        }}>
          {/* Panel header */}
          <div style={{
            padding: '10px 14px 8px',
            borderBottom: '1px solid oklch(0.20 0.009 250)',
            flexShrink: 0,
          }}>
            <span style={{
              fontSize: 10,
              fontWeight: 700,
              letterSpacing: '0.08em',
              textTransform: 'uppercase',
              color: 'oklch(0.42 0.012 250)',
            }}>
              {sidebarTabs.find(t => t.id === activeTab)?.label || activeTab}
            </span>
          </div>

          {/* Panel scrollable content */}
          <div style={{ flex: 1, overflowY: 'auto', padding: '12px 14px' }}>

            {/* ── Image Tab ── */}
            {activeTab === "image" && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                {/* Annotation properties if selected */}
                {selectedAnnotation && (
                  <div>
                    <div className="section-header" style={{ paddingTop: 0 }}>
                      <span className="section-title">Annotation</span>
                      <button
                        onClick={() => { setSelectedAnnotation(null); setShowAnnotationPanel(false); }}
                        style={{ color: 'oklch(0.42 0.012 250)', cursor: 'pointer', background: 'none', border: 'none', padding: 2 }}
                      >
                        <X className="size-3" />
                      </button>
                    </div>
                    <PropertiesPanel annotation={selectedAnnotation} onUpdate={handleAnnotationUpdate} />
                    <hr className="panel-divider" />
                  </div>
                )}
                <ImageRoundnessControl
                  borderRadius={settings.borderRadius}
                  onBorderRadiusChangeTransient={actions.setBorderRadiusTransient}
                  onBorderRadiusChange={actions.setBorderRadius}
                />
                {error && (
                  <div style={{
                    padding: '8px 10px',
                    background: 'oklch(0.22 0.10 25 / 0.25)',
                    border: '1px solid oklch(0.42 0.15 25 / 0.4)',
                    borderRadius: 6,
                    fontSize: 11,
                    color: 'oklch(0.72 0.15 25)',
                  }}>
                    <strong style={{ display: 'block', marginBottom: 3 }}>Error</strong>
                    {error}
                  </div>
                )}
              </div>
            )}

            {/* ── Background Tab ── */}
            {activeTab === "background" && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
                <BackgroundSelector
                  backgroundType={settings.backgroundType as "transparent" | "white" | "black" | "gray" | "gradient" | "custom"}
                  customColor={settings.customColor}
                  selectedGradient={selectedGradientOption.id}
                  expanded={true}
                  onBackgroundTypeChange={actions.setBackgroundType}
                  onCustomColorChange={actions.setCustomColor}
                  onGradientSelect={actions.setGradient}
                  onToggle={() => {}}
                />
                <hr className="panel-divider" />
                <AssetGrid
                  categories={assetCategories}
                  selectedImage={settings.selectedImageSrc}
                  backgroundType={settings.backgroundType}
                  expanded={true}
                  onImageSelect={actions.handleImageSelect}
                  onToggle={() => {}}
                />
              </div>
            )}

            {/* ── Effects Tab ── */}
            {activeTab === "effects" && (
              <EffectsPanel
                noiseAmount={settings.noiseAmount}
                padding={settings.padding}
                shadow={settings.shadow}
                noiseExpanded={true}
                shadowExpanded={true}
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
                onNoiseToggle={() => {}}
                onShadowToggle={() => {}}
              />
            )}

            {/* ── Size Tab ── */}
            {activeTab === "size" && (
              <BackgroundSizePanel
                dimensions={settings.canvasDimensions}
                screenshotWidth={screenshotImage?.width || 0}
                screenshotHeight={screenshotImage?.height || 0}
                padding={settings.padding}
                imageScalingMode={settings.imageScalingMode}
                imageBorderSize={settings.imageBorderSize}
                expanded={true}
                onWidthChange={actions.setCanvasWidth}
                onHeightChange={actions.setCanvasHeight}
                onAspectRatioLockedChange={actions.setAspectRatioLocked}
                onPresetSelect={(width, height) => {
                  actions.setCanvasDimensions({ width, height });
                  if (settings.imageScalingMode === "none") actions.setImageScalingMode("cover");
                }}
                onScalingModeChange={actions.setImageScalingMode}
                onBorderSizeChange={actions.setImageBorderSize}
                onReset={() => {
                  actions.setCanvasDimensions({ width: 0, height: 0 });
                  actions.setImageScalingMode("none");
                  actions.setImageOffset({ x: 0, y: 0 });
                }}
                onToggle={() => {}}
              />
            )}

            {/* ── Position Tab ── */}
            {activeTab === "position" && (
              canReposition ? (
                <ImagePositionPanel
                  imageOffset={settings.imageOffset}
                  screenshotWidth={screenshotImage?.width || 0}
                  screenshotHeight={screenshotImage?.height || 0}
                  backgroundWidth={
                    settings.canvasDimensions.width > 0
                      ? settings.canvasDimensions.width
                      : (screenshotImage?.width || 0) + settings.padding * 2
                  }
                  backgroundHeight={
                    settings.canvasDimensions.height > 0
                      ? settings.canvasDimensions.height
                      : (screenshotImage?.height || 0) + settings.padding * 2
                  }
                  imageScalingMode={settings.imageScalingMode}
                  expanded={true}
                  onOffsetXChange={actions.setImageOffsetX}
                  onOffsetYChange={actions.setImageOffsetY}
                  onReset={() => actions.setImageOffset({ x: 0, y: 0 })}
                  onToggle={() => {}}
                />
              ) : (
                <div style={{
                  padding: '20px 0',
                  textAlign: 'center',
                  color: 'oklch(0.42 0.009 250)',
                  fontSize: 12,
                  lineHeight: 1.5,
                }}>
                  <Move className="size-6" style={{ margin: '0 auto 8px', opacity: 0.4 }} />
                  <p>Image position is only available when the image is larger than the canvas or in Cover scaling mode.</p>
                </div>
              )
            )}

            {/* ── Export Tab ── */}
            {activeTab === "export" && (
              <ExportSettingsPanel
                saveDir={saveDir}
                exportName={exportName}
                isSaving={isSaving}
                imageLoaded={imageLoaded}
                onSaveDirChange={onSaveDirChange}
                onExportNameChange={setExportName}
                onBrowseSaveDir={handleBrowseSaveDir}
                onSave={handleSave}
              />
            )}
          </div>
        </div>}

        {/* ─── Canvas ─── */}
        <div style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'oklch(0.115 0.008 250)',
          overflow: 'hidden',
          minWidth: 0,
          minHeight: 0,
          position: 'relative',
        }}>
          {/* Subtle dot grid pattern */}
          <div style={{
            position: 'absolute',
            inset: 0,
            backgroundImage: 'radial-gradient(circle, oklch(0.26 0.009 250) 1px, transparent 1px)',
            backgroundSize: '24px 24px',
            opacity: 0.5,
            pointerEvents: 'none',
          }} />

          <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative', padding: 24 }}>
            {previewUrl ? (
              <AnnotationCanvas
                annotations={annotations}
                selectedAnnotation={selectedAnnotation}
                selectedTool={selectedTool}
                previewUrl={previewUrl}
                showTransparencyGrid={settings.backgroundType === "transparent"}
                imageOffset={settings.imageOffset}
                canReposition={canReposition}
                onImageOffsetUpdateTransient={(offset) => {
                  actions.setImageOffsetXTransient(offset.x);
                  actions.setImageOffsetYTransient(offset.y);
                }}
                onImageOffsetUpdate={(offset) => { actions.setImageOffset(offset); }}
                onAnnotationAdd={handleAnnotationAdd}
                onAnnotationUpdateTransient={handleAnnotationUpdateTransient}
                onAnnotationUpdate={handleAnnotationUpdate}
                onAnnotationSelect={(ann) => {
                  setSelectedAnnotation(ann);
                  if (ann) { setShowAnnotationPanel(true); setActiveTab("image"); }
                }}
                onAnnotationDelete={handleAnnotationDelete}
              />
            ) : imageLoaded ? (
              <span style={{ color: 'oklch(0.42 0.009 250)', fontSize: 13 }}>Generating preview…</span>
            ) : error ? (
              <div style={{ textAlign: 'center', color: 'oklch(0.62 0.15 25)', padding: 24 }}>
                <p style={{ fontWeight: 500, marginBottom: 6 }}>Could not load image</p>
                <small style={{ fontSize: 11, color: 'oklch(0.48 0.009 250)', wordBreak: 'break-all' }}>{error}</small>
              </div>
            ) : (
              <span style={{ color: 'oklch(0.42 0.009 250)', fontSize: 13 }}>Loading image…</span>
            )}
            <canvas ref={canvasRef} style={{ display: "none" }} />
          </div>
        </div>
      </div>
    </div>
  );
}
