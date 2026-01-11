import { useState } from "react";
import { cn } from "@/lib/utils";

export interface Asset {
  id: string;
  src: string;
  name: string;
}

export interface AssetCategory {
  name: string;
  assets: Asset[];
}

interface AssetGridProps {
  categories: AssetCategory[];
  selectedImage: string | null;
  backgroundType: string;
  onImageSelect: (imageSrc: string) => void;
}

export function AssetGrid({ categories, selectedImage, backgroundType, onImageSelect }: AssetGridProps) {
  const [activeCategory, setActiveCategory] = useState(categories[0]?.name || "");

  const currentCategory = categories.find((cat) => cat.name === activeCategory);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-zinc-200 font-mono text-balance">Wallpapers</h3>
      </div>
      
      {categories.length > 1 && (
        <div className="flex p-1 bg-zinc-800/50 rounded-lg border border-zinc-700/50">
          {categories.map((category) => (
            <button
              key={category.name}
              onClick={() => setActiveCategory(category.name)}
              aria-label={`Select ${category.name} category`}
              className={cn(
                "flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-all",
                activeCategory === category.name
                  ? "bg-zinc-700 text-white shadow-sm"
                  : "text-zinc-400 hover:text-zinc-200 hover:bg-zinc-700/30"
              )}
            >
              {category.name === "Wallpapers" ? "Wallpapers" : category.name === "Mac Assets" ? "Mac" : category.name}
            </button>
          ))}
        </div>
      )}

      <div className="grid grid-cols-4 gap-2 max-h-[400px] overflow-y-auto pr-4 pb-2 [&::-webkit-scrollbar]:w-1.5 [&::-webkit-scrollbar-thumb]:bg-zinc-700 [&::-webkit-scrollbar-thumb]:rounded-full [&::-webkit-scrollbar-track]:bg-transparent">
        {currentCategory?.assets.map((asset) => (
          <button
            key={asset.id}
            onClick={() => onImageSelect(asset.src)}
            aria-label={`Select ${asset.name} background`}
            className={cn(
              "group relative w-full aspect-square rounded-lg overflow-hidden transition-all",
              backgroundType === "image" && selectedImage === asset.src
                ? "ring-2 ring-blue-500 ring-offset-2 ring-offset-zinc-900"
                : "ring-1 ring-zinc-700 hover:ring-zinc-500"
            )}
          >
            <img
              src={asset.src}
              alt={asset.name}
              className="w-full h-full object-cover transition-transform group-hover:scale-110"
            />
            {backgroundType === "image" && selectedImage === asset.src && (
              <div className="absolute inset-0 bg-blue-500/20 flex items-center justify-center">
                <div className="size-6 rounded-full bg-blue-500 flex items-center justify-center shadow-lg">
                  <svg className="size-3.5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" />
                  </svg>
                </div>
              </div>
            )}
          </button>
        ))}
      </div>
    </div>
  );
}
