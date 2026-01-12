import { useState, useCallback, useEffect, useRef } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { toast } from "sonner";
import { Upload, X, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { assetCategories } from "@/hooks/useEditorSettings";
import { cn } from "@/lib/utils";

interface BackgroundImageSelectorProps {
  onImageSelect: (imageSrc: string) => void;
}

export function BackgroundImageSelector({ onImageSelect }: BackgroundImageSelectorProps) {
  const [selectedImage, setSelectedImage] = useState<string | null>(null);
  const [uploadedImages, setUploadedImages] = useState<string[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const loadSettings = async () => {
      try {
        const store = await Store.load("settings.json");
        const defaultBg = await store.get<string>("defaultBackgroundImage");
        const uploaded = await store.get<string[]>("uploadedBackgroundImages");
        
        if (defaultBg) {
          setSelectedImage(defaultBg);
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
    setSelectedImage(imageSrc);
    onImageSelect(imageSrc);
    
    try {
      const store = await Store.load("settings.json");
      await store.set("defaultBackgroundImage", imageSrc);
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
        <label className="text-sm font-medium text-zinc-200">Default Background Image</label>
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
            variant="outline"
            size="sm"
            className="border-zinc-700 text-zinc-300 hover:bg-zinc-800 hover:text-zinc-50"
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
            <h4 className="text-xs font-medium text-zinc-400 mb-2 uppercase tracking-wide">Uploaded Images</h4>
            <div className="grid grid-cols-4 gap-2">
              {uploadedImages.map((img, index) => (
                <div key={index} className="relative group">
                  <button
                    onClick={() => handleImageSelect(img)}
                    className={cn(
                      "relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all",
                      selectedImage === img
                        ? "border-blue-500 ring-2 ring-blue-500/50"
                        : "border-zinc-700 hover:border-zinc-600"
                    )}
                  >
                    <img
                      src={img}
                      alt={`Uploaded ${index + 1}`}
                      className="w-full h-full object-cover"
                    />
                    {selectedImage === img && (
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
            <h4 className="text-xs font-medium text-zinc-400 mb-2 uppercase tracking-wide">{category.name}</h4>
            <div className="grid grid-cols-4 gap-2">
              {category.assets.map((asset) => (
                <button
                  key={asset.id}
                  onClick={() => handleImageSelect(asset.src)}
                  className={cn(
                    "relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all",
                    selectedImage === asset.src
                      ? "border-blue-500 ring-2 ring-blue-500/50"
                      : "border-zinc-700 hover:border-zinc-600"
                  )}
                >
                  <img
                    src={asset.src}
                    alt={asset.name}
                    className="w-full h-full object-cover"
                  />
                  {selectedImage === asset.src && (
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
