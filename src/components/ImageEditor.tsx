import { useState, useRef, useEffect, useCallback } from "react";
import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { BackgroundSelector, gradientOptions, type GradientOption } from "./editor/BackgroundSelector";
import { AssetGrid, type AssetCategory } from "./editor/AssetGrid";
import { EffectsPanel } from "./editor/EffectsPanel";
import { ImageRoundnessControl } from "./editor/ImageRoundnessControl";
import { createHighQualityCanvas } from "@/lib/canvas-utils";

// Import all background images
import bgImage13 from "@/assets/bg-images/asset-13.jpg";
import bgImage18 from "@/assets/bg-images/asset-18.jpg";
import bgImage19 from "@/assets/bg-images/asset-19.jpg";
import bgImage24 from "@/assets/bg-images/asset-24.avif";
import bgImage25 from "@/assets/bg-images/asset-25.jpg";
import bgImage26 from "@/assets/bg-images/asset-26.jpeg";
import bgImage27 from "@/assets/bg-images/asset-27.jpeg";
import bgImage28 from "@/assets/bg-images/asset-28.jpeg";
import bgImage29 from "@/assets/bg-images/asset-29.jpeg";
import bgImage30 from "@/assets/bg-images/asset-30.jpeg";

import macImage3 from "@/assets/mac/mac-asset-3.jpg";
import macImage5 from "@/assets/mac/mac-asset-5.jpg";
import macImage6 from "@/assets/mac/mac-asset-6.jpeg";
import macImage7 from "@/assets/mac/mac-asset-7.png";
import macImage8 from "@/assets/mac/mac-asset-8.jpg";
import macImage9 from "@/assets/mac/mac-asset-9.jpg";
import macImage10 from "@/assets/mac/mac-asset-10.jpg";

import mesh1 from "@/assets/mesh/mesh1.webp";
import mesh2 from "@/assets/mesh/mesh2.webp";
import mesh3 from "@/assets/mesh/mesh3.webp";
import mesh4 from "@/assets/mesh/mesh4.webp";
import mesh5 from "@/assets/mesh/mesh5.webp";
import mesh6 from "@/assets/mesh/mesh6.webp";
import mesh7 from "@/assets/mesh/mesh7.webp";
import mesh8 from "@/assets/mesh/mesh8.webp";

interface ImageEditorProps {
  imagePath: string;
  onSave: (editedImageData: string) => void;
  onCancel: () => void;
}

type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom" | "image";

const assetCategories: AssetCategory[] = [
  {
    name: "Wallpapers",
    assets: [
      { id: "bg-13", src: bgImage13, name: "Background 13" },
      { id: "bg-18", src: bgImage18, name: "Background 18" },
      { id: "bg-19", src: bgImage19, name: "Background 19" },
      { id: "bg-24", src: bgImage24, name: "Background 24" },
      { id: "bg-25", src: bgImage25, name: "Background 25" },
      { id: "bg-26", src: bgImage26, name: "Background 26" },
      { id: "bg-27", src: bgImage27, name: "Background 27" },
      { id: "bg-28", src: bgImage28, name: "Background 28" },
      { id: "bg-29", src: bgImage29, name: "Background 29" },
      { id: "bg-30", src: bgImage30, name: "Background 30" },
    ],
  },
  {
    name: "Mac Assets",
    assets: [
      { id: "mac-3", src: macImage3, name: "Mac 3" },
      { id: "mac-5", src: macImage5, name: "Mac 5" },
      { id: "mac-6", src: macImage6, name: "Mac 6" },
      { id: "mac-7", src: macImage7, name: "Mac 7" },
      { id: "mac-8", src: macImage8, name: "Mac 8" },
      { id: "mac-9", src: macImage9, name: "Mac 9" },
      { id: "mac-10", src: macImage10, name: "Mac 10" },
    ],
  },
  {
    name: "Mesh",
    assets: [
      { id: "mesh-1", src: mesh1, name: "Mesh 1" },
      { id: "mesh-2", src: mesh2, name: "Mesh 2" },
      { id: "mesh-3", src: mesh3, name: "Mesh 3" },
      { id: "mesh-4", src: mesh4, name: "Mesh 4" },
      { id: "mesh-5", src: mesh5, name: "Mesh 5" },
      { id: "mesh-6", src: mesh6, name: "Mesh 6" },
      { id: "mesh-7", src: mesh7, name: "Mesh 7" },
      { id: "mesh-8", src: mesh8, name: "Mesh 8" },
    ],
  },
];

export function ImageEditor({ imagePath, onSave, onCancel }: ImageEditorProps) {
  const [backgroundType, setBackgroundType] = useState<BackgroundType>("image");
  const [customColor, setCustomColor] = useState("#667eea");
  const [selectedImage, setSelectedImage] = useState<string | null>(bgImage25);
  const [selectedGradient, setSelectedGradient] = useState<GradientOption>(gradientOptions[0]);
  const [blurAmount, setBlurAmount] = useState(20);
  const [noiseAmount, setNoiseAmount] = useState(0);
  const [borderRadius, setBorderRadius] = useState(18);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [imageLoaded, setImageLoaded] = useState(false);
  const [bgImageLoaded, setBgImageLoaded] = useState(false);
  const [copied, setCopied] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isCopying, setIsCopying] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const imageRef = useRef<HTMLImageElement | null>(null);
  const bgImageRef = useRef<HTMLImageElement | null>(null);

  const drawBackground = useCallback((ctx: CanvasRenderingContext2D, width: number, height: number) => {
    switch (backgroundType) {
      case "transparent":
        const squareSize = 10;
        for (let y = 0; y < height; y += squareSize) {
          for (let x = 0; x < width; x += squareSize) {
            const isEven = ((x / squareSize) + (y / squareSize)) % 2 === 0;
            ctx.fillStyle = isEven ? "#ffffff" : "#e0e0e0";
            ctx.fillRect(x, y, squareSize, squareSize);
          }
        }
        break;
      case "white":
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(0, 0, width, height);
        break;
      case "black":
        ctx.fillStyle = "#000000";
        ctx.fillRect(0, 0, width, height);
        break;
      case "gray":
        ctx.fillStyle = "#f5f5f5";
        ctx.fillRect(0, 0, width, height);
        break;
      case "gradient": {
        const gradient = ctx.createLinearGradient(0, 0, width, height);
        gradient.addColorStop(0, selectedGradient.colors[0]);
        gradient.addColorStop(1, selectedGradient.colors[1]);
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, width, height);
        break;
      }
      case "custom":
        ctx.fillStyle = customColor;
        ctx.fillRect(0, 0, width, height);
        break;
      case "image":
        if (bgImageRef.current && selectedImage) {
          // Draw image to fill the entire background area
          ctx.drawImage(bgImageRef.current, 0, 0, width, height);
        } else {
          ctx.fillStyle = "#ffffff";
          ctx.fillRect(0, 0, width, height);
        }
        break;
    }
  }, [backgroundType, customColor, selectedImage, selectedGradient]);

  const applyNoiseToBackground = useCallback((ctx: CanvasRenderingContext2D, width: number, height: number, amount: number) => {
    if (amount === 0) return;
    
    const imageData = ctx.getImageData(0, 0, width, height);
    const data = imageData.data;
    const noiseIntensity = amount * 2.55;

    for (let i = 0; i < data.length; i += 4) {
      const noise = (Math.random() - 0.5) * noiseIntensity;
      data[i] = Math.max(0, Math.min(255, data[i] + noise));
      data[i + 1] = Math.max(0, Math.min(255, data[i + 1] + noise));
      data[i + 2] = Math.max(0, Math.min(255, data[i + 2] + noise));
    }

    ctx.putImageData(imageData, 0, 0);
  }, []);

  // Load background image when selected
  useEffect(() => {
    if (backgroundType === "image" && selectedImage) {
      setBgImageLoaded(false);
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => {
        bgImageRef.current = img;
        setBgImageLoaded(true);
      };
      img.onerror = () => {
        setError("Failed to load background image");
        setBgImageLoaded(false);
      };
      img.src = selectedImage;
    } else {
      bgImageRef.current = null;
      setBgImageLoaded(false);
    }
  }, [backgroundType, selectedImage]);

  const updatePreview = useCallback(() => {
    if (!imageRef.current || !canvasRef.current || !imageLoaded) return;

    const img = imageRef.current;
    const padding = 100;
    const bgWidth = img.width + padding * 2;
    const bgHeight = img.height + padding * 2;

    const canvas = canvasRef.current;
    canvas.width = bgWidth;
    canvas.height = bgHeight;
    const ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) return;

    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";

    const tempBgCanvas = document.createElement("canvas");
    tempBgCanvas.width = bgWidth;
    tempBgCanvas.height = bgHeight;
    const tempBgCtx = tempBgCanvas.getContext("2d");
    if (!tempBgCtx) return;
    
    drawBackground(tempBgCtx, bgWidth, bgHeight);

    const bgCanvas = document.createElement("canvas");
    bgCanvas.width = bgWidth;
    bgCanvas.height = bgHeight;
    const bgCtx = bgCanvas.getContext("2d");
    if (!bgCtx) return;

    if (blurAmount > 0) {
      // Extend canvas size to prevent edge clipping during blur
      const blurPadding = blurAmount * 3;
      const extendedWidth = bgWidth + blurPadding * 2;
      const extendedHeight = bgHeight + blurPadding * 2;
      
      const extendedCanvas = document.createElement("canvas");
      extendedCanvas.width = extendedWidth;
      extendedCanvas.height = extendedHeight;
      const extendedCtx = extendedCanvas.getContext("2d");
      
      if (extendedCtx) {
        // Draw background at offset position
        extendedCtx.drawImage(tempBgCanvas, blurPadding, blurPadding);
        
        // Fill edges by extending the background
        extendedCtx.drawImage(tempBgCanvas, 0, 0, bgWidth, 1, blurPadding, 0, bgWidth, blurPadding);
        extendedCtx.drawImage(tempBgCanvas, 0, bgHeight - 1, bgWidth, 1, blurPadding, blurPadding + bgHeight, bgWidth, blurPadding);
        extendedCtx.drawImage(tempBgCanvas, 0, 0, 1, bgHeight, 0, blurPadding, blurPadding, bgHeight);
        extendedCtx.drawImage(tempBgCanvas, bgWidth - 1, 0, 1, bgHeight, blurPadding + bgWidth, blurPadding, blurPadding, bgHeight);
        
        // Apply blur to extended canvas
        const blurredExtCanvas = document.createElement("canvas");
        blurredExtCanvas.width = extendedWidth;
        blurredExtCanvas.height = extendedHeight;
        const blurredExtCtx = blurredExtCanvas.getContext("2d");
        
        if (blurredExtCtx) {
          blurredExtCtx.filter = `blur(${blurAmount}px)`;
          blurredExtCtx.drawImage(extendedCanvas, 0, 0);
          blurredExtCtx.filter = "none";
          
          // Crop back to original size
          bgCtx.drawImage(blurredExtCanvas, blurPadding, blurPadding, bgWidth, bgHeight, 0, 0, bgWidth, bgHeight);
        } else {
          bgCtx.drawImage(tempBgCanvas, 0, 0);
        }
      } else {
        bgCtx.drawImage(tempBgCanvas, 0, 0);
      }
    } else {
      bgCtx.drawImage(tempBgCanvas, 0, 0);
    }

    if (noiseAmount > 0) {
      applyNoiseToBackground(bgCtx, bgWidth, bgHeight, noiseAmount);
    }

    ctx.drawImage(bgCanvas, 0, 0);

    ctx.shadowColor = "rgba(0, 0, 0, 0.3)";
    ctx.shadowBlur = 20;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 10;

    ctx.beginPath();
    ctx.roundRect(padding, padding, img.width, img.height, borderRadius);
    ctx.closePath();
    ctx.clip();

    ctx.drawImage(img, padding, padding, img.width, img.height);

    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;

    canvas.toBlob((blob) => {
      if (blob) {
        if (previewUrl) {
          URL.revokeObjectURL(previewUrl);
        }
        const url = URL.createObjectURL(blob);
        setPreviewUrl(url);
      }
    }, "image/png");
  }, [imageLoaded, drawBackground, previewUrl, blurAmount, noiseAmount, applyNoiseToBackground, borderRadius]);

  useEffect(() => {
    setError(null);
    setImageLoaded(false);
    setPreviewUrl(null);

    if (!imagePath) {
      setError("No image path provided");
      return;
    }

    const img = new Image();
    
    img.onload = () => {
      imageRef.current = img;
      setImageLoaded(true);
    };
    
    img.onerror = () => {
      setError(`Failed to load image from: ${imagePath}`);
      setPreviewUrl(null);
    };

    const assetUrl = convertFileSrc(imagePath);
    img.crossOrigin = "anonymous";
    img.src = assetUrl;

    return () => {
      img.onload = null;
      img.onerror = null;
    };
  }, [imagePath]);

  useEffect(() => {
    if (imageLoaded && (backgroundType !== "image" || bgImageLoaded)) {
      updatePreview();
    }
  }, [imageLoaded, backgroundType, customColor, blurAmount, noiseAmount, selectedImage, bgImageLoaded, borderRadius, selectedGradient, updatePreview]);

  useEffect(() => {
    return () => {
      if (previewUrl) {
        URL.revokeObjectURL(previewUrl);
      }
    };
  }, [previewUrl]);

  const renderHighQualityCanvas = useCallback((): HTMLCanvasElement | null => {
    if (!imageRef.current) return null;

    try {
      return createHighQualityCanvas({
        image: imageRef.current,
        backgroundType,
        customColor,
        selectedImage,
        bgImage: bgImageRef.current,
        blurAmount,
        noiseAmount,
        borderRadius,
        padding: 100,
        gradientColors: selectedGradient.colors,
      });
    } catch (err) {
      setError(`Failed to render high-quality image: ${err instanceof Error ? err.message : String(err)}`);
      return null;
    }
  }, [backgroundType, customColor, selectedImage, blurAmount, noiseAmount, borderRadius, selectedGradient]);

  const handleSave = useCallback(() => {
    if (!imageRef.current || isSaving || isCopying) return;
    
    setIsSaving(true);
    const highQualityCanvas = renderHighQualityCanvas();
    
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
            setError("Failed to read image data");
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
  }, [renderHighQualityCanvas, onSave, isSaving, isCopying]);

  const handleCopy = useCallback(async () => {
    if (!imageRef.current || isSaving || isCopying) return;
    
    setIsCopying(true);
    try {
      const highQualityCanvas = renderHighQualityCanvas();
      
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
      
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      setError(`Failed to copy: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setIsCopying(false);
    }
  }, [renderHighQualityCanvas, isSaving, isCopying]);

  const handleImageSelect = (imageSrc: string) => {
    setSelectedImage(imageSrc);
    setBackgroundType("image");
  };

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
          <Button 
            variant="default" 
            onClick={handleCopy} 
            disabled={!imageLoaded || isSaving || isCopying}
            className="bg-emerald-600 hover:bg-emerald-700 text-white disabled:opacity-50 relative"
            title="Copy to clipboard (⌘⇧C)"
          >
            {isCopying ? (
              <span className="flex items-center gap-2">
                <svg className="animate-spin size-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Copying...
              </span>
            ) : copied ? (
              "Copied!"
            ) : (
              "Copy"
            )}
          </Button>
          <Button 
            variant="default" 
            onClick={handleSave} 
            disabled={!imageLoaded || isSaving || isCopying}
            className="bg-blue-600 hover:bg-blue-700 text-white disabled:opacity-50"
            title="Save image (⌘S)"
          >
            {isSaving ? (
              <span className="flex items-center gap-2">
                <svg className="animate-spin size-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Saving...
              </span>
            ) : (
              "Save"
            )}
          </Button>
        </div>
      </div>

      <div className="flex flex-1 overflow-hidden">
        <div className="w-96 p-6 border-r border-zinc-800 bg-zinc-900 overflow-y-auto">
          <div className="space-y-6">
            <BackgroundSelector
              backgroundType={backgroundType as "transparent" | "white" | "black" | "gray" | "gradient" | "custom"}
              customColor={customColor}
              selectedGradient={selectedGradient.id}
              onBackgroundTypeChange={(type) => setBackgroundType(type)}
              onCustomColorChange={setCustomColor}
              onGradientSelect={setSelectedGradient}
            />

            <AssetGrid
              categories={assetCategories}
              selectedImage={selectedImage}
              onImageSelect={handleImageSelect}
            />

            <EffectsPanel
              blurAmount={blurAmount}
              noiseAmount={noiseAmount}
              onBlurChange={setBlurAmount}
              onNoiseChange={setNoiseAmount}
            />

            <ImageRoundnessControl
              borderRadius={borderRadius}
              onBorderRadiusChange={setBorderRadius}
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

        <div className="flex-1 flex items-center justify-center p-10 bg-zinc-950 overflow-auto">
          <div className="max-w-full max-h-full">
            {previewUrl ? (
              <img 
                src={previewUrl} 
                alt="Preview" 
                className="max-w-full max-h-full rounded-lg shadow-2xl border border-zinc-800" 
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
