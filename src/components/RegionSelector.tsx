import { useEffect, useMemo, useRef, useState } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";

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
    scale_factor: number;
    path: string;
  }[];
}

export function RegionSelector({ onSelect, onCancel, monitorShots }: RegionSelectorProps) {
  const [isSelecting, setIsSelecting] = useState(false);
  const [startPos, setStartPos] = useState({ x: 0, y: 0 });
  const [currentPos, setCurrentPos] = useState({ x: 0, y: 0 });
  const [cursorPos, setCursorPos] = useState({ x: -100, y: -100 });
  const [isReady, setIsReady] = useState(false);
  const overlayRef = useRef<HTMLDivElement>(null);

  // Fade in after mount for smooth appearance
  useEffect(() => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => setIsReady(true));
    });
  }, []);

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
    <div 
      ref={overlayRef} 
      className={`fixed inset-0 bg-transparent z-50 cursor-none select-none overflow-hidden transition-opacity ${isReady ? 'opacity-100' : 'opacity-0'}`}
    >
      {normalizedShots.map((shot) => (
        <img
          key={shot.id}
          className="absolute object-contain select-none pointer-events-none"
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

      {selectionBox ? (
        <>
          <div 
            className="absolute bg-black/50 pointer-events-none"
            style={{
              top: 0,
              left: 0,
              right: 0,
              height: `${selectionBox.y}px`,
            }}
          />
          <div 
            className="absolute bg-black/50 pointer-events-none"
            style={{
              top: `${selectionBox.y}px`,
              left: 0,
              width: `${selectionBox.x}px`,
              height: `${selectionBox.height}px`,
            }}
          />
          <div 
            className="absolute bg-black/50 pointer-events-none"
            style={{
              top: `${selectionBox.y}px`,
              left: `${selectionBox.x + selectionBox.width}px`,
              right: 0,
              height: `${selectionBox.height}px`,
            }}
          />
          <div 
            className="absolute bg-black/50 pointer-events-none"
            style={{
              top: `${selectionBox.y + selectionBox.height}px`,
              left: 0,
              right: 0,
              bottom: 0,
            }}
          />
        </>
      ) : (
        <div className="absolute inset-0 bg-black/50 pointer-events-none" />
      )}

      {selectionBox && selectionBox.width > 0 && selectionBox.height > 0 && (
        <div
          className="absolute border-2 border-blue-500 bg-transparent pointer-events-none shadow-[0_0_0_1px_rgba(0,0,0,0.3),inset_0_0_0_1px_rgba(255,255,255,0.1)]"
          style={{
            left: `${selectionBox.x}px`,
            top: `${selectionBox.y}px`,
            width: `${selectionBox.width}px`,
            height: `${selectionBox.height}px`,
          }}
        >
          <div className="absolute -top-7 left-1/2 -translate-x-1/2 bg-black/85 text-white px-2.5 py-1 text-xs font-medium rounded backdrop-blur-sm border border-white/10 whitespace-nowrap tabular-nums">
            {selectionBox.width} x {selectionBox.height}
          </div>
          <div className="absolute -top-1 -left-1 size-2 bg-blue-500 border border-white rounded-sm" />
          <div className="absolute -top-1 -right-1 size-2 bg-blue-500 border border-white rounded-sm" />
          <div className="absolute -bottom-1 -left-1 size-2 bg-blue-500 border border-white rounded-sm" />
          <div className="absolute -bottom-1 -right-1 size-2 bg-blue-500 border border-white rounded-sm" />
        </div>
      )}

      <div 
        className="fixed h-px bg-blue-500/80 pointer-events-none z-[51] shadow-[0_0_2px_rgba(0,0,0,0.5)]"
        style={{ 
          top: `${cursorPos.y}px`,
          left: `${cursorPos.x - 40}px`,
          width: '80px',
        }}
      />
      <div 
        className="fixed w-px bg-blue-500/80 pointer-events-none z-[51] shadow-[0_0_2px_rgba(0,0,0,0.5)]"
        style={{ 
          left: `${cursorPos.x}px`,
          top: `${cursorPos.y - 40}px`,
          height: '80px',
        }}
      />
      
      <div 
        className="fixed bg-black/75 text-white px-1.5 py-0.5 text-[11px] font-mono rounded pointer-events-none z-[52] whitespace-nowrap tabular-nums"
        style={{
          left: `${cursorPos.x + 15}px`,
          top: `${cursorPos.y + 15}px`,
        }}
      >
        {Math.round(cursorPos.x)}, {Math.round(cursorPos.y)}
      </div>

      <div className="fixed bottom-8 left-1/2 -translate-x-1/2 bg-black/85 text-white px-6 py-3 rounded-lg text-sm pointer-events-none backdrop-blur-md border border-white/15 z-[52] text-pretty">
        Click and drag to select region &bull; Press ESC to cancel
      </div>
    </div>
  );
}
