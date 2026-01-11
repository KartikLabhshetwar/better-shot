import { useEffect, useMemo, useRef } from "react";
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
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rafRef = useRef<number>(0);
  
  // Selection state stored in refs for performance
  const isSelectingRef = useRef(false);
  const startRef = useRef({ x: 0, y: 0 });
  const currentRef = useRef({ x: 0, y: 0 });
  const needsUpdateRef = useRef(false);

  // Calculate bounds for multi-monitor
  const bounds = useMemo(() => {
    if (!monitorShots.length) return { minX: 0, minY: 0, width: 0, height: 0 };
    const result = monitorShots.reduce(
      (acc, s) => ({
        minX: Math.min(acc.minX, s.x),
        minY: Math.min(acc.minY, s.y),
        maxX: Math.max(acc.maxX, s.x + s.width),
        maxY: Math.max(acc.maxY, s.y + s.height),
      }),
      { 
        minX: monitorShots[0].x, 
        minY: monitorShots[0].y,
        maxX: monitorShots[0].x + monitorShots[0].width,
        maxY: monitorShots[0].y + monitorShots[0].height,
      }
    );
    return {
      minX: result.minX,
      minY: result.minY,
      width: result.maxX - result.minX,
      height: result.maxY - result.minY,
    };
  }, [monitorShots]);

  // Normalized shots for rendering
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

  // Canvas rendering loop - runs on RAF for smooth updates
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) return;

    // Set canvas size to match container
    const updateCanvasSize = () => {
      const dpr = window.devicePixelRatio || 1;
      canvas.width = bounds.width * dpr;
      canvas.height = bounds.height * dpr;
      canvas.style.width = `${bounds.width}px`;
      canvas.style.height = `${bounds.height}px`;
      ctx.scale(dpr, dpr);
    };
    updateCanvasSize();

    const render = () => {
      if (!needsUpdateRef.current && isSelectingRef.current) {
        rafRef.current = requestAnimationFrame(render);
        return;
      }

      // Clear canvas
      ctx.clearRect(0, 0, bounds.width, bounds.height);

      if (isSelectingRef.current || needsUpdateRef.current) {
        const x = Math.min(startRef.current.x, currentRef.current.x);
        const y = Math.min(startRef.current.y, currentRef.current.y);
        const width = Math.abs(currentRef.current.x - startRef.current.x);
        const height = Math.abs(currentRef.current.y - startRef.current.y);

        if (width > 0 && height > 0) {
          // Draw dark overlay with cutout (using composite operation for performance)
          ctx.fillStyle = "rgba(0, 0, 0, 0.5)";
          
          // Top
          ctx.fillRect(0, 0, bounds.width, y);
          // Left
          ctx.fillRect(0, y, x, height);
          // Right
          ctx.fillRect(x + width, y, bounds.width - x - width, height);
          // Bottom
          ctx.fillRect(0, y + height, bounds.width, bounds.height - y - height);

          // Selection border
          ctx.strokeStyle = "#3b82f6";
          ctx.lineWidth = 2;
          ctx.strokeRect(x, y, width, height);

          // Corner handles
          const handleSize = 6;
          ctx.fillStyle = "#3b82f6";
          const corners = [
            [x - handleSize/2, y - handleSize/2],
            [x + width - handleSize/2, y - handleSize/2],
            [x - handleSize/2, y + height - handleSize/2],
            [x + width - handleSize/2, y + height - handleSize/2],
          ];
          corners.forEach(([cx, cy]) => {
            ctx.fillRect(cx, cy, handleSize, handleSize);
            ctx.strokeStyle = "#fff";
            ctx.lineWidth = 1;
            ctx.strokeRect(cx, cy, handleSize, handleSize);
          });

          // Dimension label
          const label = `${Math.round(width)} × ${Math.round(height)}`;
          ctx.font = "12px ui-monospace, monospace";
          const textMetrics = ctx.measureText(label);
          const labelPadding = 8;
          const labelHeight = 20;
          const labelWidth = textMetrics.width + labelPadding * 2;
          const labelX = x + width / 2 - labelWidth / 2;
          const labelY = y - labelHeight - 8;

          if (labelY > 0) {
            ctx.fillStyle = "rgba(0, 0, 0, 0.8)";
            ctx.beginPath();
            ctx.roundRect(labelX, labelY, labelWidth, labelHeight, 4);
            ctx.fill();

            ctx.fillStyle = "#fff";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(label, x + width / 2, labelY + labelHeight / 2);
          }
        }
        needsUpdateRef.current = false;
      } else {
        // No selection - just draw the overlay
        ctx.fillStyle = "rgba(0, 0, 0, 0.5)";
        ctx.fillRect(0, 0, bounds.width, bounds.height);
      }

      rafRef.current = requestAnimationFrame(render);
    };

    rafRef.current = requestAnimationFrame(render);

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [bounds.width, bounds.height]);

  // Event handlers
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const handleMouseDown = (e: MouseEvent) => {
      e.preventDefault();
      isSelectingRef.current = true;
      startRef.current = { x: e.clientX, y: e.clientY };
      currentRef.current = { x: e.clientX, y: e.clientY };
      needsUpdateRef.current = true;
    };

    const handleMouseMove = (e: MouseEvent) => {
      if (!isSelectingRef.current) return;
      currentRef.current = { x: e.clientX, y: e.clientY };
      needsUpdateRef.current = true;
    };

    const handleMouseUp = () => {
      if (!isSelectingRef.current) return;
      isSelectingRef.current = false;

      const x = Math.min(startRef.current.x, currentRef.current.x);
      const y = Math.min(startRef.current.y, currentRef.current.y);
      const width = Math.abs(currentRef.current.x - startRef.current.x);
      const height = Math.abs(currentRef.current.y - startRef.current.y);

      if (width > 10 && height > 10) {
        onSelect({
          x: x + bounds.minX,
          y: y + bounds.minY,
          width,
          height,
        });
      } else {
        // Reset selection if too small
        needsUpdateRef.current = true;
      }
    };

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };

    container.addEventListener("mousedown", handleMouseDown);
    window.addEventListener("mousemove", handleMouseMove);
    window.addEventListener("mouseup", handleMouseUp);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      container.removeEventListener("mousedown", handleMouseDown);
      window.removeEventListener("mousemove", handleMouseMove);
      window.removeEventListener("mouseup", handleMouseUp);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [bounds.minX, bounds.minY, onSelect, onCancel]);

  return (
    <div
      ref={containerRef}
      className="fixed inset-0 z-50 cursor-crosshair select-none overflow-hidden"
    >
      {/* Screenshot backgrounds */}
      {normalizedShots.map((shot) => (
        <img
          key={shot.id}
          src={shot.url}
          alt=""
          draggable={false}
          className="absolute select-none pointer-events-none"
          style={{
            left: shot.left,
            top: shot.top,
            width: shot.width,
            height: shot.height,
          }}
        />
      ))}

      {/* Canvas overlay for selection - GPU accelerated */}
      <canvas
        ref={canvasRef}
        className="absolute inset-0 pointer-events-none"
      />

      {/* Instructions */}
      <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-black/80 text-white px-4 py-2 rounded-lg text-sm pointer-events-none">
        Drag to select · ESC to cancel
      </div>
    </div>
  );
}
