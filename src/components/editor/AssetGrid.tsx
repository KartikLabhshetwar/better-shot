import { useState, memo } from "react";
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
  expanded?: boolean;
  onImageSelect: (imageSrc: string) => void;
  onToggle?: () => void;
}

export const AssetGrid = memo(function AssetGrid({
  categories,
  selectedImage,
  backgroundType,
  onImageSelect,
}: AssetGridProps) {
  const [activeCategory, setActiveCategory] = useState(categories[0]?.name || "");
  const currentCategory = categories.find((cat) => cat.name === activeCategory);

  return (
    <div>
      {/* Section header */}
      <div className="section-header">
        <span className="section-title">Wallpapers</span>
      </div>

      {/* Category tabs */}
      {categories.length > 1 && (
        <div style={{
          display: 'flex',
          gap: 4,
          marginBottom: 10,
          background: 'oklch(0.135 0.008 250)',
          borderRadius: 6,
          padding: 3,
          border: '1px solid oklch(0.22 0.009 250)',
        }}>
          {categories.map((category) => (
            <button
              key={category.name}
              onClick={() => setActiveCategory(category.name)}
              aria-label={`Select ${category.name} category`}
              style={{
                flex: 1,
                padding: '4px 8px',
                borderRadius: 4,
                fontSize: 11,
                fontWeight: 500,
                transition: 'all 0.12s ease',
                cursor: 'pointer',
                border: 'none',
                ...(activeCategory === category.name
                  ? {
                      background: 'oklch(0.22 0.009 250)',
                      color: 'oklch(0.80 0.01 250)',
                    }
                  : {
                      background: 'transparent',
                      color: 'oklch(0.45 0.009 250)',
                    }
                ),
              }}
            >
              {category.name === "Wallpapers" ? "Wallpapers" : category.name === "Mac Assets" ? "Mac" : category.name}
            </button>
          ))}
        </div>
      )}

      {/* Asset grid */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(4, 1fr)',
        gap: 6,
        maxHeight: 280,
        overflowY: 'auto',
        paddingRight: 2,
        paddingBottom: 4,
      }}>
        {currentCategory?.assets.map((asset) => {
          const isSelected = backgroundType === "image" && selectedImage === asset.src;
          return (
            <button
              key={asset.id}
              onClick={() => onImageSelect(asset.src)}
              aria-label={`Select ${asset.name}`}
              className={cn("gradient-thumb", isSelected && "selected")}
              style={{ position: 'relative', aspectRatio: '1', overflow: 'hidden' }}
            >
              <img
                src={asset.src}
                alt={asset.name}
                style={{
                  width: '100%', height: '100%', objectFit: 'cover',
                  display: 'block',
                  transition: 'transform 0.15s ease',
                }}
                onMouseEnter={(e) => { (e.currentTarget as HTMLImageElement).style.transform = 'scale(1.08)'; }}
                onMouseLeave={(e) => { (e.currentTarget as HTMLImageElement).style.transform = 'scale(1)'; }}
              />
              {isSelected && (
                <div style={{
                  position: 'absolute', inset: 0,
                  background: 'oklch(0.65 0.18 255 / 0.25)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
});
