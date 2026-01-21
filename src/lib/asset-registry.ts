/**
 * Asset Registry
 * 
 * This module provides a centralized way to look up bundled assets by ID.
 * We store asset IDs in settings instead of runtime paths because:
 * - In development, Vite serves assets from /src/assets/...
 * - In production, assets are bundled with hashed names like /assets/asset-18-abc123.jpg
 * 
 * By storing IDs and looking up paths at runtime, we avoid path mismatches
 * between development and production builds.
 */

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

// Gradient images
import gradient1 from "@/assets/mesh/mesh1.webp";
import gradient2 from "@/assets/mesh/mesh2.webp";
import gradient3 from "@/assets/mesh/mesh3.webp";
import gradient4 from "@/assets/mesh/mesh4.webp";
import gradient5 from "@/assets/mesh/mesh5.webp";
import gradient6 from "@/assets/mesh/mesh6.webp";
import gradient7 from "@/assets/mesh/mesh7.webp";
import gradient8 from "@/assets/mesh/mesh8.webp";
import gradient9 from "@/assets/mesh/mesh9.webp";
import gradient10 from "@/assets/mesh/mesh10.webp";
import gradient11 from "@/assets/mesh/mesh11.webp";
import gradient12 from "@/assets/mesh/mesh12.webp";
import gradient13 from "@/assets/mesh/mesh13.webp";
import gradient14 from "@/assets/mesh/mesh14.webp";
import gradient15 from "@/assets/mesh/mesh15.webp";
import gradient16 from "@/assets/mesh/mesh16.webp";
import gradient17 from "@/assets/mesh/mesh17.webp";

/**
 * Map of asset IDs to their runtime-resolved paths
 * This ensures we always use the correct path regardless of dev/prod environment
 */
export const assetRegistry: Record<string, string> = {
  // Background images
  "bg-13": bgImage13,
  "bg-18": bgImage18,
  "bg-19": bgImage19,
  "bg-24": bgImage24,
  "bg-25": bgImage25,
  "bg-26": bgImage26,
  "bg-27": bgImage27,
  "bg-28": bgImage28,
  "bg-29": bgImage29,
  "bg-30": bgImage30,
  
  // Mac assets
  "mac-3": macImage3,
  "mac-5": macImage5,
  "mac-6": macImage6,
  "mac-7": macImage7,
  "mac-8": macImage8,
  "mac-9": macImage9,
  "mac-10": macImage10,
  
  // Gradients
  "gradient-1": gradient1,
  "gradient-2": gradient2,
  "gradient-3": gradient3,
  "gradient-4": gradient4,
  "gradient-5": gradient5,
  "gradient-6": gradient6,
  "gradient-7": gradient7,
  "gradient-8": gradient8,
  "gradient-9": gradient9,
  "gradient-10": gradient10,
  "gradient-11": gradient11,
  "gradient-12": gradient12,
  "gradient-13": gradient13,
  "gradient-14": gradient14,
  "gradient-15": gradient15,
  "gradient-16": gradient16,
  "gradient-17": gradient17,
};

/** Default background asset ID */
export const DEFAULT_BACKGROUND_ID = "bg-18";

/** Get the runtime path for an asset by ID */
export function getAssetPath(assetId: string): string | null {
  return assetRegistry[assetId] ?? null;
}

/** Get the default background image path */
export function getDefaultBackgroundPath(): string {
  return assetRegistry[DEFAULT_BACKGROUND_ID];
}

/**
 * Check if a string is an asset ID (exists in registry)
 */
export function isAssetId(value: string): boolean {
  return value in assetRegistry;
}

/**
 * Check if a string is a data URL (uploaded image)
 */
export function isDataUrl(value: string): boolean {
  return value.startsWith("data:");
}

/**
 * Resolve a stored background value to an actual path
 * Handles:
 * - Asset IDs (e.g., "bg-18") -> looks up in registry
 * - Data URLs (uploaded images) -> returns as-is
 * - Legacy paths (e.g., "/src/assets/...") -> tries to match and migrate
 */
export function resolveBackgroundPath(storedValue: string | null): string {
  if (!storedValue) {
    return getDefaultBackgroundPath();
  }
  
  // If it's an asset ID, look it up
  if (isAssetId(storedValue)) {
    return assetRegistry[storedValue];
  }
  
  // If it's a data URL (uploaded image), use it directly
  if (isDataUrl(storedValue)) {
    return storedValue;
  }
  
  // Legacy path migration: try to extract asset ID from old paths
  // Old paths look like: /src/assets/bg-images/asset-18.jpg or /assets/asset-18-hash.jpg
  const legacyMatch = storedValue.match(/asset-(\d+)/);
  if (legacyMatch) {
    const assetId = `bg-${legacyMatch[1]}`;
    if (isAssetId(assetId)) {
      console.log(`Migrating legacy path to asset ID: ${storedValue} -> ${assetId}`);
      return assetRegistry[assetId];
    }
  }
  
  // Check for mac assets
  const macMatch = storedValue.match(/mac-asset-(\d+)/);
  if (macMatch) {
    const assetId = `mac-${macMatch[1]}`;
    if (isAssetId(assetId)) {
      console.log(`Migrating legacy path to asset ID: ${storedValue} -> ${assetId}`);
      return assetRegistry[assetId];
    }
  }
  
  // Fallback to default
  console.warn(`Unable to resolve background path: ${storedValue}, using default`);
  return getDefaultBackgroundPath();
}

/**
 * Find the asset ID for a given path (reverse lookup)
 * Used when saving to convert runtime paths back to IDs
 */
export function getAssetIdFromPath(path: string): string | null {
  for (const [id, assetPath] of Object.entries(assetRegistry)) {
    if (assetPath === path) {
      return id;
    }
  }
  return null;
}

/**
 * Convert a path to a storable value
 * - If it's a registry asset, returns the asset ID
 * - If it's a data URL, returns it as-is
 * - Otherwise returns null (shouldn't be stored)
 */
export function toStorableValue(path: string): string | null {
  // Check if it's a registered asset
  const assetId = getAssetIdFromPath(path);
  if (assetId) {
    return assetId;
  }
  
  // Data URLs can be stored directly
  if (isDataUrl(path)) {
    return path;
  }
  
  return null;
}

/**
 * Migrate a legacy stored value to the new format
 * Returns the migrated value (asset ID) or the original if it's already valid
 */
export function migrateStoredValue(storedValue: string): string | null {
  // Already a valid asset ID
  if (isAssetId(storedValue)) {
    return storedValue;
  }
  
  // Data URLs are valid
  if (isDataUrl(storedValue)) {
    return storedValue;
  }
  
  // Try to extract asset ID from legacy paths like:
  // /src/assets/bg-images/asset-18.jpg
  // /assets/asset-18-hash.jpg
  const legacyBgMatch = storedValue.match(/asset-(\d+)/);
  if (legacyBgMatch) {
    const assetId = `bg-${legacyBgMatch[1]}`;
    if (isAssetId(assetId)) {
      return assetId;
    }
  }
  
  // Check for mac assets: mac-asset-5.jpg
  const macMatch = storedValue.match(/mac-asset-(\d+)/);
  if (macMatch) {
    const assetId = `mac-${macMatch[1]}`;
    if (isAssetId(assetId)) {
      return assetId;
    }
  }
  
  // Check for mesh/gradient: mesh1.webp
  const meshMatch = storedValue.match(/mesh(\d+)/);
  if (meshMatch) {
    const assetId = `gradient-${meshMatch[1]}`;
    if (isAssetId(assetId)) {
      return assetId;
    }
  }
  
  // Unknown format - return default
  console.warn(`Unable to migrate stored value: ${storedValue}`);
  return DEFAULT_BACKGROUND_ID;
}
