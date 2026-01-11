import { useEffect, useMemo, useRef, useState } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import "./RegionSelector.css";

interface Region {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface RegionSelectorProps {
  onSelect: (region: Region) => void;
  onCancel: () => void;
  monitorShots: {
    id: number;
    x: number;
    y: number;
    width: number;
    height: number;
    path: string;
  }[];
}

export function RegionSelector({ onSelect, onCancel, monitorShots }: RegionSelectorProps) {
  const [isSelecting, setIsSelecting] = useState(false);
  const [startPos, setStartPos] = useState({ x: 0, y: 0 });
  const [currentPos, setCurrentPos] = useState({ x: 0, y: 0 });
  const [cursorPos, setCursorPos] = useState({ x: -100, y: -100 });
  const overlayRef = useRef<HTMLDivElement>(null);

  // Calculate the bounds offset (for multi-monitor support)
  const bounds = useMemo(() => {
    if (!monitorShots.length) {
      return { minX: 0, minY: 0 };
    }
    return monitorShots.reduce(
      (acc, s) => ({
        minX: Math.min(acc.minX, s.x),
        minY: Math.min(acc.minY, s.y),
      }),
      { minX: monitorShots[0].x, minY: monitorShots[0].y }
    );
  }, [monitorShots]);

  // Normalize shots for rendering (adjust positions relative to window)
  const normalizedShots = useMemo(
    () =>
      monitorShots.map((shot) => ({
        ...shot,
        left: shot.x - bounds.minX,
        top: shot.y - bounds.minY,
        url: convertFileSrc(shot.path),
      })),
    [monitorShots, bounds.minX, bounds.minY]
  );

  // Calculate the selection box in window coordinates (for rendering)
  const selectionBox = useMemo(() => {
    if (!isSelecting) return null;
    
    const x = Math.min(startPos.x, currentPos.x);
    const y = Math.min(startPos.y, currentPos.y);
    const width = Math.abs(currentPos.x - startPos.x);
    const height = Math.abs(currentPos.y - startPos.y);
    
    return { x, y, width, height };
  }, [isSelecting, startPos, currentPos]);

  useEffect(() => {
    const handleMouseDown = (e: MouseEvent) => {
      e.preventDefault();
      setIsSelecting(true);
      setStartPos({ x: e.clientX, y: e.clientY });
      setCurrentPos({ x: e.clientX, y: e.clientY });
    };

    const handleMouseMove = (e: MouseEvent) => {
      setCursorPos({ x: e.clientX, y: e.clientY });
      
      if (isSelecting) {
        setCurrentPos({ x: e.clientX, y: e.clientY });
      }
    };

    const handleMouseUp = () => {
      if (isSelecting) {
        setIsSelecting(false);
        
        // Calculate region with proper width/height
        const x = Math.min(startPos.x, currentPos.x);
        const y = Math.min(startPos.y, currentPos.y);
        const width = Math.abs(currentPos.x - startPos.x);
        const height = Math.abs(currentPos.y - startPos.y);
        
        if (width > 10 && height > 10) {
          // Convert window coords to absolute screen coords for cropping
          const region: Region = {
            x: x + bounds.minX,
            y: y + bounds.minY,
            width,
            height,
          };
          onSelect(region);
        }
      }
    };

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        onCancel();
      }
    };

    // Initialize cursor position
    const initCursor = (e: MouseEvent) => {
      setCursorPos({ x: e.clientX, y: e.clientY });
    };

    document.addEventListener("mousedown", handleMouseDown);
    document.addEventListener("mousemove", handleMouseMove);
    document.addEventListener("mouseup", handleMouseUp);
    document.addEventListener("keydown", handleKeyDown);
    window.addEventListener("mousemove", initCursor, { once: true });

    return () => {
      document.removeEventListener("mousedown", handleMouseDown);
      document.removeEventListener("mousemove", handleMouseMove);
      document.removeEventListener("mouseup", handleMouseUp);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [isSelecting, startPos, currentPos, bounds, onSelect, onCancel]);

  return (
    <div ref={overlayRef} className="region-selector-overlay">
      {/* Screenshot images as background */}
      {normalizedShots.map((shot) => (
        <img
          key={shot.id}
          className="region-selector-shot"
          src={shot.url}
          alt={`Captured monitor ${shot.id}`}
          style={{
            left: `${shot.left}px`,
            top: `${shot.top}px`,
            width: `${shot.width}px`,
            height: `${shot.height}px`,
          }}
          draggable={false}
        />
      ))}

      {/* Dim overlay with cutout for selection */}
      {selectionBox ? (
        <>
          {/* Top dim */}
          <div 
            className="region-selector-dim"
            style={{
              top: 0,
              left: 0,
              right: 0,
              height: `${selectionBox.y}px`,
            }}
          />
          {/* Left dim */}
          <div 
            className="region-selector-dim"
            style={{
              top: `${selectionBox.y}px`,
              left: 0,
              width: `${selectionBox.x}px`,
              height: `${selectionBox.height}px`,
            }}
          />
          {/* Right dim */}
          <div 
            className="region-selector-dim"
            style={{
              top: `${selectionBox.y}px`,
              left: `${selectionBox.x + selectionBox.width}px`,
              right: 0,
              height: `${selectionBox.height}px`,
            }}
          />
          {/* Bottom dim */}
          <div 
            className="region-selector-dim"
            style={{
              top: `${selectionBox.y + selectionBox.height}px`,
              left: 0,
              right: 0,
              bottom: 0,
            }}
          />
        </>
      ) : (
        <div className="region-selector-dim region-selector-dim-full" />
      )}

      {/* Selection box border */}
      {selectionBox && selectionBox.width > 0 && selectionBox.height > 0 && (
        <div
          className="region-selector-box"
          style={{
            left: `${selectionBox.x}px`,
            top: `${selectionBox.y}px`,
            width: `${selectionBox.width}px`,
            height: `${selectionBox.height}px`,
          }}
        >
          <div className="region-selector-info">
            {selectionBox.width} x {selectionBox.height}
          </div>
          {/* Corner handles */}
          <div className="selection-handle handle-nw" />
          <div className="selection-handle handle-ne" />
          <div className="selection-handle handle-sw" />
          <div className="selection-handle handle-se" />
        </div>
      )}

      {/* Crosshair cursor - full screen spanning lines */}
      <div 
        className="crosshair-horizontal"
        style={{ top: `${cursorPos.y}px` }}
      />
      <div 
        className="crosshair-vertical"
        style={{ left: `${cursorPos.x}px` }}
      />
      
      {/* Cursor position indicator */}
      <div 
        className="cursor-coords"
        style={{
          left: `${cursorPos.x + 15}px`,
          top: `${cursorPos.y + 15}px`,
        }}
      >
        {Math.round(cursorPos.x)}, {Math.round(cursorPos.y)}
      </div>

      {/* Instructions */}
      <div className="region-selector-instructions">
        Click and drag to select region &bull; Press ESC to cancel
      </div>
    </div>
  );
}
