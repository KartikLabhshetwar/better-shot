import { useState, useCallback, useEffect, useRef } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { toast } from "sonner";
import { Upload, X, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { assetCategories } from "@/hooks/useEditorSettings";
import { cn } from "@/lib/utils";
import { 
  toStorableValue, 
  isDataUrl,
  getAssetIdFromPath 
} from "@/lib/asset-registry";

interface BackgroundImageSelectorProps {
  onImageSelect: (imageSrc: string) => void;
}

export function BackgroundImageSelector({ onImageSelect }: BackgroundImageSelectorProps) {
  // selectedImage stores the asset ID or data URL (storable value)
  const [selectedImage, setSelectedImage] = useState<string | null>(null);
  const [uploadedImages, setUploadedImages] = useState<string[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

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
        const storedBg = await store.get<string>("defaultBackgroundImage");
        const uploaded = await store.get<string[]>("uploadedBackgroundImages");
        
        if (storedBg) {
          // Resolve the stored value to an actual path for display
          // But keep tracking by the stored value (ID or data URL)
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
    // Convert the runtime path to a storable value (asset ID or data URL)
    const storableValue = toStorableValue(imageSrc);
    
    if (!storableValue) {
      console.error("Cannot store this image path:", imageSrc);
      toast.error("Failed to save background selection");
      return;
    }
    
    setSelectedImage(storableValue);
    onImageSelect(imageSrc);
    
    try {
      const store = await Store.load("settings.json");
      // Store the asset ID, not the runtime path
      await store.set("defaultBackgroundImage", storableValue);
      await store.save();
      toast.success("Default background updated");
    } catch (err) {
      console.error("Failed to save default background:", err);
      toast.error("Failed to save default background");
    }
  }, [onImageSelect]);

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
        <label className="text-sm font-medium text-foreground">Default Background Image</label>
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

      <div className="space-y-3">
        {uploadedImages.length > 0 && (
          <div>
            <h4 className="text-xs font-medium text-muted-foreground mb-2 uppercase tracking-wide">Uploaded Images</h4>
            <div className="grid grid-cols-4 gap-2">
              {uploadedImages.map((img, index) => (
                <div key={index} className="relative group">
                  <button
                    onClick={() => handleImageSelect(img)}
                    className={cn(
                      "relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all",
                      isSelected(img)
                        ? "border-blue-500 ring-2 ring-blue-500/50"
                        : "border-border hover:border-ring"
                    )}
                  >
                    <img
                      src={img}
                      alt={`Uploaded ${index + 1}`}
                      className="w-full h-full object-cover"
                    />
                    {isSelected(img) && (
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
            <div className="grid grid-cols-4 gap-2">
              {category.assets.map((asset) => (
                <button
                  key={asset.id}
                  onClick={() => handleImageSelect(asset.src)}
                  className={cn(
                    "relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all",
                    isSelected(asset.src)
                      ? "border-blue-500 ring-2 ring-blue-500/50"
                      : "border-border hover:border-ring"
                  )}
                >
                  <img
                    src={asset.src}
                    alt={asset.name}
                    className="w-full h-full object-cover"
                  />
                  {isSelected(asset.src) && (
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
  );
}
