import { useState, useCallback, useEffect, useRef } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { toast } from "sonner";
import { Upload, X, Check } from "lucide-react";
import { gradientOptions } from "@/components/editor/BackgroundSelector";
import { Button } from "@/components/ui/button";
import { assetCategories } from "@/hooks/useEditorSettings";
import { cn } from "@/lib/utils";
import {
  getAssetIdFromPath,
  getAssetPath,
  isDataUrl,
  toStorableValue,
} from "@/lib/asset-registry";

type BackgroundType = "transparent" | "white" | "black" | "gray" | "custom" | "image" | "gradient";

interface BackgroundImageSelectorProps {
  onImageSelect: (imageSrc: string) => void;
}

export function BackgroundImageSelector({ onImageSelect }: BackgroundImageSelectorProps) {
  const [backgroundType, setBackgroundType] = useState<BackgroundType>("image");
  const [customColor, setCustomColor] = useState("#667eea");
  const [selectedImage, setSelectedImage] = useState<string | null>(null);
  const [uploadedImages, setUploadedImages] = useState<string[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const solidColors: { type: BackgroundType; color: string }[] = [
    { type: "white", color: "#ffffff" },
    { type: "black", color: "#000000" },
    { type: "gray", color: "#f5f5f5" },
  ];

  // Helper to check if an asset is selected (compares by ID)
  const isSelected = useCallback((assetSrc: string): boolean => {
    if (!selectedImage) return false;
    
    // For data URLs (uploaded images), compare directly
    if (isDataUrl(assetSrc)) {
      return selectedImage === assetSrc;
    }
    
    // For registry assets, compare by asset ID
    const assetId = getAssetIdFromPath(assetSrc);
    return assetId === selectedImage;
  }, [selectedImage]);

  useEffect(() => {
    const loadSettings = async () => {
      try {
        const store = await Store.load("settings.json");
        const storedBgType = await store.get<BackgroundType>("defaultBackgroundType");
        const storedCustomColor = await store.get<string>("defaultCustomColor");
        const storedBg = await store.get<string>("defaultBackgroundImage");
        const uploaded = await store.get<string[]>("uploadedBackgroundImages");
        
        if (storedBgType) {
          setBackgroundType(storedBgType);
        }
        if (storedCustomColor) {
          setCustomColor(storedCustomColor);
        }
        if (storedBg) {
          setSelectedImage(storedBg);
        }
        if (uploaded) {
          setUploadedImages(uploaded);
        }
      } catch (err) {
        console.error("Failed to load background settings:", err);
      }
    };
    loadSettings();
  }, []);

  const handleImageSelect = useCallback(async (imageSrc: string) => {
    const storableValue = toStorableValue(imageSrc);
    
    if (!storableValue) {
      console.error("Cannot store this image path:", imageSrc);
      toast.error("Failed to save background selection");
      return;
    }
    
    setBackgroundType("image");
    setSelectedImage(storableValue);
    onImageSelect(imageSrc);
    
    try {
      const store = await Store.load("settings.json");
      await store.set("defaultBackgroundType", "image");
      await store.set("defaultBackgroundImage", storableValue);
      await store.save();
      toast.success("Default background updated");
    } catch (err) {
      console.error("Failed to save default background:", err);
      toast.error("Failed to save default background");
    }
  }, [onImageSelect]);

  const handleSolidColorSelect = useCallback(async (type: BackgroundType) => {
    setBackgroundType(type);
    setSelectedImage(null);
    
    try {
      const store = await Store.load("settings.json");
      await store.set("defaultBackgroundType", type);
      if (type === "image") {
        await store.set("defaultBackgroundImage", null);
      }
      await store.save();
      toast.success("Default background updated");
    } catch (err) {
      console.error("Failed to save default background:", err);
      toast.error("Failed to save default background");
    }
  }, []);

  const handleCustomColorChange = useCallback(async (color: string) => {
    setCustomColor(color);
    setBackgroundType("custom");
    setSelectedImage(null);
    
    try {
      const store = await Store.load("settings.json");
      await store.set("defaultBackgroundType", "custom");
      await store.set("defaultCustomColor", color);
      await store.set("defaultBackgroundImage", null);
      await store.save();
      toast.success("Default background updated");
    } catch (err) {
      console.error("Failed to save default background:", err);
      toast.error("Failed to save default background");
    }
  }, []);

  const handleFileUpload = useCallback(async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    const reader = new FileReader();
    reader.onloadend = async () => {
      const dataUrl = reader.result as string;
      const newUploadedImages = [...uploadedImages, dataUrl];
      setUploadedImages(newUploadedImages);
      
      try {
        const store = await Store.load("settings.json");
        await store.set("uploadedBackgroundImages", newUploadedImages);
        await store.save();
        toast.success("Image uploaded successfully");
      } catch (err) {
        console.error("Failed to save uploaded image:", err);
        toast.error("Failed to save uploaded image");
      }
    };
    reader.onerror = () => {
      toast.error("Failed to read image file");
    };
    reader.readAsDataURL(file);
    
    event.target.value = "";
  }, [uploadedImages]);

  const handleRemoveUploaded = useCallback(async (index: number) => {
    const newUploadedImages = uploadedImages.filter((_, i) => i !== index);
    setUploadedImages(newUploadedImages);
    
    if (selectedImage === uploadedImages[index]) {
      setSelectedImage(null);
    }
    
    try {
      const store = await Store.load("settings.json");
      await store.set("uploadedBackgroundImages", newUploadedImages);
      await store.save();
      toast.success("Image removed");
    } catch (err) {
      console.error("Failed to remove image:", err);
      toast.error("Failed to remove image");
    }
  }, [uploadedImages, selectedImage]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-foreground">Default Background</label>
        <div>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            onChange={handleFileUpload}
            className="hidden"
          />
          <Button
            type="button"
            variant="cta"
            size="lg"
            onClick={() => fileInputRef.current?.click()}
          >
            <Upload className="size-3 mr-1" aria-hidden="true" />
            Upload
          </Button>
        </div>
      </div>

      <div className="space-y-4">
        <div className="space-y-2">
          <span className="text-xs text-muted-foreground uppercase tracking-wide">Solid</span>
          <div className="flex gap-2">
            {solidColors.map(({ type, color }) => (
              <button
                key={type}
                onClick={() => handleSolidColorSelect(type)}
                aria-label={`Select ${type} background`}
                className={cn(
                  "size-10 rounded-lg transition-all",
                  backgroundType === type
                    ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-card"
                    : "ring-1 ring-border hover:ring-ring"
                )}
                style={{ backgroundColor: color }}
                title={type.charAt(0).toUpperCase() + type.slice(1)}
              />
            ))}
            <div className="relative">
              <button
                onClick={() => handleCustomColorChange(customColor)}
                aria-label="Select custom color background"
                className={cn(
                  "size-10 rounded-lg transition-all",
                  backgroundType === "custom"
                    ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-card"
                    : "ring-1 ring-border hover:ring-ring"
                )}
                style={{ backgroundColor: customColor }}
                title="Custom color"
              />
              <input
                type="color"
                value={customColor}
                onChange={(e) => handleCustomColorChange(e.target.value)}
                className="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
              />
            </div>
          </div>
        </div>

        <div className="space-y-2">
          <span className="text-xs text-muted-foreground uppercase tracking-wide">Transparent</span>
          <div className="flex gap-2">
            <button
              onClick={() => handleSolidColorSelect("transparent")}
              aria-label="Select transparent background"
              className={cn(
                "size-10 rounded-lg transition-all bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGRlZnM+PHBhdHRlcm4gaWQ9ImNoZWNrZXJib2FyZCIgd2lkdGg9IjEwIiBoZWlnaHQ9IjEwIiBwYXR0ZXJuVW5pdHM9InVzZXJTcGFjZU9uVXNlIj48cmVjdCB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjZmZmIi8+PHJlY3QgeD0iNSIgd2lkdGg9IjUiIGhlaWdodD0iNSIgZmlsbD0iI2UwZTBlMCIvPjxyZWN0IHk9IjUiIHdpZHRoPSI1IiBoZWlnaHQ9IjUiIGZpbGw9IiNlMGUwZTAiLz48cmVjdCB4PSI1IiB5PSI1IiB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjZmZmIi8+PC9wYXR0ZXJuPjwvZGVmcz48cmVjdCB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIGZpbGw9InVybCgjY2hlY2tlcmJvYXJkKSIvPjwvc3ZnPg==')]",
                backgroundType === "transparent"
                  ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-card"
                  : ""
              )}
              title="Transparent"
            />
          </div>
        </div>

        <div className="space-y-2">
          <span className="text-xs text-muted-foreground uppercase tracking-wide">Gradients</span>
          <div className="grid grid-cols-7 gap-2">
            {gradientOptions.map((gradient) => {
              const gradientId = gradient.id.replace("mesh-", "gradient-");
              const isGradientSelected = selectedImage === gradientId;

              return (
                <button
                  key={gradient.id}
                  onClick={async () => {
                    const assetPath = getAssetPath(gradientId) ?? gradient.src;

                    setBackgroundType("gradient");
                    setSelectedImage(gradientId);
                    onImageSelect(assetPath);

                    try {
                      const store = await Store.load("settings.json");
                      await store.set("defaultBackgroundType", "gradient");
                      await store.set("defaultBackgroundImage", gradientId);
                      await store.save();
                      toast.success("Default background updated");
                    } catch (err) {
                      console.error("Failed to save default background:", err);
                      toast.error("Failed to save default background");
                    }
                  }}
                  aria-label={`Select ${gradient.name} background`}
                  className={cn(
                    "relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all",
                    backgroundType === "gradient" && isGradientSelected
                      ? "border-blue-500 ring-2 ring-blue-500/50"
                      : "border-border hover:border-ring"
                  )}
                  title={gradient.name}
                >
                  <img
                    src={gradient.src}
                    alt={gradient.name}
                    className="w-full h-full object-cover"
                  />
                  {backgroundType === "gradient" && isGradientSelected && (
                    <div className="absolute inset-0 bg-blue-500/20 flex items-center justify-center">
                      <Check className="size-5 text-blue-400" aria-hidden="true" />
                    </div>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        <div className="space-y-3">
          {uploadedImages.length > 0 && (
            <div>
              <h4 className="text-xs font-medium text-muted-foreground mb-2 uppercase tracking-wide">Uploaded Images</h4>
              <div className="grid grid-cols-7 gap-2">
                {uploadedImages.map((img, index) => (
                  <div key={index} className="relative group">
                    <button
                      onClick={() => handleImageSelect(img)}
                      className={cn(
                        "relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all",
                        backgroundType === "image" && isSelected(img)
                          ? "border-blue-500 ring-2 ring-blue-500/50"
                          : "border-border hover:border-ring"
                      )}
                    >
                      <img
                        src={img}
                        alt={`Uploaded ${index + 1}`}
                        className="w-full h-full object-cover"
                      />
                      {backgroundType === "image" && isSelected(img) && (
                        <div className="absolute inset-0 bg-blue-500/20 flex items-center justify-center">
                          <Check className="size-5 text-blue-400" aria-hidden="true" />
                        </div>
                      )}
                    </button>
                    <button
                      onClick={() => handleRemoveUploaded(index)}
                      className="absolute -top-1 -right-1 size-5 bg-red-500 text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                      aria-label="Remove image"
                    >
                      <X className="size-3" aria-hidden="true" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {assetCategories.map((category) => (
            <div key={category.name}>
              <h4 className="text-xs font-medium text-muted-foreground mb-2 uppercase tracking-wide">{category.name}</h4>
              <div className="grid grid-cols-7 gap-2">
                {category.assets.map((asset) => (
                  <button
                    key={asset.id}
                    onClick={() => handleImageSelect(asset.src)}
                    className={cn(
                      "relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all",
                      backgroundType === "image" && isSelected(asset.src)
                        ? "border-blue-500 ring-2 ring-blue-500/50"
                        : "border-border hover:border-ring"
                    )}
                  >
                    <img
                      src={asset.src}
                      alt={asset.name}
                      className="w-full h-full object-cover"
                    />
                    {backgroundType === "image" && isSelected(asset.src) && (
                      <div className="absolute inset-0 bg-blue-500/20 flex items-center justify-center">
                        <Check className="size-5 text-blue-400" aria-hidden="true" />
                      </div>
                    )}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
