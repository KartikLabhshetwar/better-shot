import { useState, useRef, useEffect, useCallback } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import "./ImageEditor.css";

interface ImageEditorProps {
  imagePath: string;
  onSave: (editedImageData: string) => void;
  onCancel: () => void;
}

type BackgroundType = "transparent" | "white" | "black" | "gray" | "gradient" | "custom";

export function ImageEditor({ imagePath, onSave, onCancel }: ImageEditorProps) {
  const [backgroundType, setBackgroundType] = useState<BackgroundType>("gradient");
  const [customColor, setCustomColor] = useState("#667eea");
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [imageLoaded, setImageLoaded] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const imageRef = useRef<HTMLImageElement | null>(null);

  const drawBackground = useCallback((ctx: CanvasRenderingContext2D, width: number, height: number) => {
    switch (backgroundType) {
      case "transparent":
        // Draw checkerboard pattern for transparency
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
        gradient.addColorStop(0, "#667eea");
        gradient.addColorStop(1, "#764ba2");
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, width, height);
        break;
      }
      case "custom":
        ctx.fillStyle = customColor;
        ctx.fillRect(0, 0, width, height);
        break;
    }
  }, [backgroundType, customColor]);

  const updatePreview = useCallback(() => {
    if (!imageRef.current || !canvasRef.current || !imageLoaded) return;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const img = imageRef.current;
    const padding = 40;
    const borderRadius = 12;
    const bgWidth = img.width + padding * 2;
    const bgHeight = img.height + padding * 2;

    canvas.width = bgWidth;
    canvas.height = bgHeight;

    // Draw background
    drawBackground(ctx, bgWidth, bgHeight);

    // Draw shadow
    ctx.shadowColor = "rgba(0, 0, 0, 0.3)";
    ctx.shadowBlur = 20;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 10;

    // Draw rounded rectangle clip path for the image
    ctx.beginPath();
    ctx.roundRect(padding, padding, img.width, img.height, borderRadius);
    ctx.closePath();
    ctx.clip();

    // Draw the image
    ctx.drawImage(img, padding, padding, img.width, img.height);

    // Reset shadow
    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;

    canvas.toBlob((blob) => {
      if (blob) {
        // Revoke previous URL to prevent memory leak
        if (previewUrl) {
          URL.revokeObjectURL(previewUrl);
        }
        const url = URL.createObjectURL(blob);
        setPreviewUrl(url);
      }
    }, "image/png");
  }, [imageLoaded, drawBackground, previewUrl]);

  // Load image when path changes
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
      console.log("Image loaded successfully:", img.width, "x", img.height);
      imageRef.current = img;
      setImageLoaded(true);
    };
    
    img.onerror = (e) => {
      console.error("Failed to load image:", e);
      setError(`Failed to load image from: ${imagePath}`);
      setPreviewUrl(null);
    };

    // Convert the file path to an asset URL
    const assetUrl = convertFileSrc(imagePath);
    console.log("Loading image from:", imagePath);
    console.log("Asset URL:", assetUrl);
    
    img.crossOrigin = "anonymous";
    img.src = assetUrl;

    return () => {
      img.onload = null;
      img.onerror = null;
    };
  }, [imagePath]);

  // Update preview when image is loaded or background changes
  useEffect(() => {
    if (imageLoaded) {
      updatePreview();
    }
  }, [imageLoaded, backgroundType, customColor, updatePreview]);

  // Cleanup preview URL on unmount
  useEffect(() => {
    return () => {
      if (previewUrl) {
        URL.revokeObjectURL(previewUrl);
      }
    };
  }, []);

  const handleSave = () => {
    if (!canvasRef.current) return;
    
    canvasRef.current.toBlob((blob) => {
      if (blob) {
        const reader = new FileReader();
        reader.onloadend = () => {
          onSave(reader.result as string);
        };
        reader.readAsDataURL(blob);
      }
    }, "image/png");
  };

  return (
    <div className="image-editor">
      <div className="image-editor-header">
        <h2>Edit Screenshot</h2>
        <div className="image-editor-actions">
          <button onClick={onCancel} className="btn-cancel">
            Cancel
          </button>
          <button onClick={handleSave} className="btn-save" disabled={!imageLoaded}>
            Save
          </button>
        </div>
      </div>

      <div className="image-editor-content">
        <div className="image-editor-sidebar">
          <div className="editor-section">
            <h3>Background</h3>
            <div className="background-options">
              {(["gradient", "white", "black", "gray", "transparent", "custom"] as BackgroundType[]).map((type) => (
                <button
                  key={type}
                  className={`bg-option ${backgroundType === type ? "active" : ""}`}
                  onClick={() => setBackgroundType(type)}
                >
                  {type.charAt(0).toUpperCase() + type.slice(1)}
                </button>
              ))}
            </div>

            {backgroundType === "custom" && (
              <div className="custom-color-picker">
                <label>Color:</label>
                <input
                  type="color"
                  value={customColor}
                  onChange={(e) => setCustomColor(e.target.value)}
                />
              </div>
            )}
          </div>

          {error && (
            <div className="editor-section">
              <div className="editor-error">
                <strong>Error:</strong> {error}
                <br />
                <small>Path: {imagePath}</small>
              </div>
            </div>
          )}
        </div>

        <div className="image-editor-preview">
          <div className="preview-container">
            {previewUrl ? (
              <img src={previewUrl} alt="Preview" className="preview-image" />
            ) : imageLoaded ? (
              <div className="preview-loading">Generating preview...</div>
            ) : error ? (
              <div className="preview-error">
                <p>Could not load image</p>
                <small>{error}</small>
              </div>
            ) : (
              <div className="preview-loading">Loading image...</div>
            )}
            <canvas ref={canvasRef} style={{ display: "none" }} />
          </div>
        </div>
      </div>
    </div>
  );
}
