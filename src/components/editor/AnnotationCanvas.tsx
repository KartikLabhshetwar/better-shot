import { useRef, useEffect, useState, useCallback, memo } from "react";
import { Annotation, ToolType, Point } from "@/types/annotations";
import { drawAnnotationOnCanvas } from "@/lib/annotation-utils";
import { cn } from "@/lib/utils";

interface AnnotationCanvasProps {
  annotations: Annotation[];
  selectedAnnotation: Annotation | null;
  selectedTool: ToolType;
  previewUrl: string | null;
  onAnnotationAdd: (annotation: Annotation) => void;
  /** Called during drag - should NOT commit to history */
  onAnnotationUpdateTransient?: (annotation: Annotation) => void;
  /** Called on drag end - should commit to history */
  onAnnotationUpdate: (annotation: Annotation) => void;
  onAnnotationSelect: (annotation: Annotation | null) => void;
  onAnnotationDelete?: (id: string) => void;
}

export const AnnotationCanvas = memo(function AnnotationCanvas({
  annotations,
  selectedAnnotation,
  selectedTool,
  previewUrl,
  onAnnotationAdd,
  onAnnotationUpdateTransient,
  onAnnotationUpdate,
  onAnnotationSelect,
}: AnnotationCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const imageRef = useRef<HTMLImageElement | null>(null);
  const rafRef = useRef<number | null>(null);
  
  // Local state for drag operation - avoids store updates during drag
  const [imageLoaded, setImageLoaded] = useState(false);
  const [isDrawing, setIsDrawing] = useState(false);
  const [startPoint, setStartPoint] = useState<Point | null>(null);
  const [currentPoint, setCurrentPoint] = useState<Point | null>(null);
  const [draggingAnnotation, setDraggingAnnotation] = useState<string | null>(null);
  const [dragOffset, setDragOffset] = useState<Point | null>(null);
  const [nextNumber, setNextNumber] = useState(1);
  
  // Track initial position for drag operations
  const dragStartAnnotationRef = useRef<Annotation | null>(null);

  // Load image once and cache it
  useEffect(() => {
    if (!previewUrl) {
      imageRef.current = null;
      setImageLoaded(false);
      return;
    }

    setImageLoaded(false);

    const img = new Image();
    img.onload = () => {
      imageRef.current = img;
      setImageLoaded(true);
    };
    img.src = previewUrl;

    return () => {
      img.onload = null;
    };
  }, [previewUrl]);

  // Cleanup RAF on unmount
  useEffect(() => {
    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, []);

  const getCanvasCoordinates = useCallback((e: React.MouseEvent<HTMLCanvasElement>): Point => {
    const canvas = canvasRef.current;
    if (!canvas) return { x: 0, y: 0 };
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    return {
      x: (e.clientX - rect.left) * scaleX,
      y: (e.clientY - rect.top) * scaleY,
    };
  }, []);

  const generateId = () => `annotation-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

  const createAnnotation = useCallback(
    (type: ToolType, start: Point, end: Point): Annotation | null => {
      if (!type || type === "select") return null;

      const defaultColor = { hex: "#FF3300", opacity: 100 };
      const defaultBorder = { width: 5, color: { hex: "#FF3300", opacity: 100 } };
      const defaultAlignment = { horizontal: "left" as const, vertical: "top" as const };

      switch (type) {
        case "circle": {
          const radius = Math.sqrt(Math.pow(end.x - start.x, 2) + Math.pow(end.y - start.y, 2));
          return {
            id: generateId(),
            type: "circle",
            x: start.x,
            y: start.y,
            radius,
            fill: defaultColor,
            border: defaultBorder,
            alignment: defaultAlignment,
          };
        }
        case "rectangle": {
          return {
            id: generateId(),
            type: "rectangle",
            x: Math.min(start.x, end.x),
            y: Math.min(start.y, end.y),
            width: Math.abs(end.x - start.x),
            height: Math.abs(end.y - start.y),
            fill: defaultColor,
            border: defaultBorder,
            alignment: defaultAlignment,
          };
        }
        case "line": {
          return {
            id: generateId(),
            type: "line",
            x: start.x,
            y: start.y,
            endX: end.x,
            endY: end.y,
            lineType: "straight",
            fill: defaultColor,
            border: defaultBorder,
            alignment: defaultAlignment,
          };
        }
        case "arrow": {
          return {
            id: generateId(),
            type: "arrow",
            x: start.x,
            y: start.y,
            endX: end.x,
            endY: end.y,
            lineType: "straight",
            arrowType: "thick",
            fill: defaultColor,
            border: defaultBorder,
            alignment: defaultAlignment,
          };
        }
        case "text": {
          return {
            id: generateId(),
            type: "text",
            x: start.x,
            y: start.y,
            text: "Text",
            fontSize: 48,
            fontFamily: "Arial",
            width: 200,
            height: 60,
            fill: defaultColor,
            border: defaultBorder,
            alignment: defaultAlignment,
          };
        }
        case "number": {
          return {
            id: generateId(),
            type: "number",
            x: start.x,
            y: start.y,
            number: nextNumber,
            radius: 32,
            fill: defaultColor,
            border: defaultBorder,
            alignment: defaultAlignment,
          };
        }
        case "blur": {
          return {
            id: generateId(),
            type: "blur",
            x: Math.min(start.x, end.x),
            y: Math.min(start.y, end.y),
            width: Math.abs(end.x - start.x),
            height: Math.abs(end.y - start.y),
            blurAmount: 20,
            fill: defaultColor,
            border: defaultBorder,
            alignment: defaultAlignment,
          };
        }
        default:
          return null;
      }
    },
    [nextNumber]
  );

  const isPointInAnnotation = useCallback((point: Point, annotation: Annotation): boolean => {
    switch (annotation.type) {
      case "circle": {
        const distance = Math.sqrt(
          Math.pow(point.x - annotation.x, 2) + Math.pow(point.y - annotation.y, 2)
        );
        return distance <= annotation.radius;
      }
      case "rectangle": {
        return (
          point.x >= annotation.x &&
          point.x <= annotation.x + annotation.width &&
          point.y >= annotation.y &&
          point.y <= annotation.y + annotation.height
        );
      }
      case "line":
      case "arrow": {
        const dx = annotation.endX - annotation.x;
        const dy = annotation.endY - annotation.y;
        const length = Math.sqrt(dx * dx + dy * dy);
        const t = Math.max(
          0,
          Math.min(
            1,
            ((point.x - annotation.x) * dx + (point.y - annotation.y) * dy) / (length * length)
          )
        );
        const projX = annotation.x + t * dx;
        const projY = annotation.y + t * dy;
        const distance = Math.sqrt(
          Math.pow(point.x - projX, 2) + Math.pow(point.y - projY, 2)
        );
        return distance <= 10;
      }
      case "text": {
        return (
          point.x >= annotation.x &&
          point.x <= annotation.x + annotation.width &&
          point.y >= annotation.y &&
          point.y <= annotation.y + annotation.height
        );
      }
      case "number": {
        const distance = Math.sqrt(
          Math.pow(point.x - annotation.x, 2) + Math.pow(point.y - annotation.y, 2)
        );
        return distance <= annotation.radius;
      }
      case "blur": {
        return (
          point.x >= annotation.x &&
          point.x <= annotation.x + annotation.width &&
          point.y >= annotation.y &&
          point.y <= annotation.y + annotation.height
        );
      }
      default:
        return false;
    }
  }, []);

  const drawAnnotation = useCallback(
    (ctx: CanvasRenderingContext2D, annotation: Annotation, isSelected: boolean) => {
      drawAnnotationOnCanvas(ctx, annotation);

      if (isSelected) {
        ctx.save();
        ctx.strokeStyle = "#3b82f6";
        ctx.lineWidth = 2;
        ctx.setLineDash([5, 5]);
        
        switch (annotation.type) {
          case "circle": {
            ctx.beginPath();
            ctx.arc(annotation.x, annotation.y, annotation.radius + 5, 0, Math.PI * 2);
            ctx.stroke();
            break;
          }
          case "rectangle": {
            ctx.strokeRect(annotation.x - 5, annotation.y - 5, annotation.width + 10, annotation.height + 10);
            break;
          }
          case "line":
          case "arrow": {
            const bounds = {
              minX: Math.min(annotation.x, annotation.endX) - 5,
              minY: Math.min(annotation.y, annotation.endY) - 5,
              maxX: Math.max(annotation.x, annotation.endX) + 5,
              maxY: Math.max(annotation.y, annotation.endY) + 5,
            };
            ctx.strokeRect(bounds.minX, bounds.minY, bounds.maxX - bounds.minX, bounds.maxY - bounds.minY);
            break;
          }
          case "text": {
            ctx.strokeRect(annotation.x - 5, annotation.y - 5, annotation.width + 10, annotation.height + 10);
            break;
          }
          case "number": {
            ctx.beginPath();
            ctx.arc(annotation.x, annotation.y, annotation.radius + 5, 0, Math.PI * 2);
            ctx.stroke();
            break;
          }
          case "blur": {
            ctx.strokeRect(annotation.x - 5, annotation.y - 5, annotation.width + 10, annotation.height + 10);
            break;
          }
        }
        
        ctx.setLineDash([]);
        ctx.restore();
      }
    },
    []
  );

  const redraw = useCallback(() => {
    const canvas = canvasRef.current;
    const img = imageRef.current;
    const container = containerRef.current;
    if (!canvas || !img || !imageLoaded || !container) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // Set canvas internal dimensions to match image
    if (canvas.width !== img.width || canvas.height !== img.height) {
      canvas.width = img.width;
      canvas.height = img.height;
    }
    
    // Calculate display size to fit container
    const containerRect = container.getBoundingClientRect();
    const containerWidth = containerRect.width;
    const containerHeight = containerRect.height;
    const imgAspect = img.width / img.height;
    const containerAspect = containerWidth / containerHeight;

    let displayWidth: number;
    let displayHeight: number;

    if (imgAspect > containerAspect) {
      displayWidth = Math.min(containerWidth, img.width);
      displayHeight = displayWidth / imgAspect;
    } else {
      displayHeight = Math.min(containerHeight, img.height);
      displayWidth = displayHeight * imgAspect;
    }

    canvas.style.width = `${displayWidth}px`;
    canvas.style.height = `${displayHeight}px`;
    
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

    annotations.forEach((annotation) => {
      const isSelected = selectedAnnotation?.id === annotation.id;
      drawAnnotation(ctx, annotation, isSelected);
    });

    if (isDrawing && startPoint && currentPoint && selectedTool && selectedTool !== "select") {
      const tempAnnotation = createAnnotation(selectedTool, startPoint, currentPoint);
      if (tempAnnotation) {
        drawAnnotation(ctx, tempAnnotation, false);
      }
    }
  }, [imageLoaded, annotations, selectedAnnotation, isDrawing, startPoint, currentPoint, selectedTool, drawAnnotation, createAnnotation]);

  useEffect(() => {
    redraw();
  }, [redraw]);

  // Handle window resize
  useEffect(() => {
    const handleResize = () => {
      if (imageLoaded) {
        redraw();
      }
    };

    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, [imageLoaded, redraw]);

  const handleMouseDown = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const point = getCanvasCoordinates(e);

    if (selectedTool === "select" || !selectedTool) {
      const clickedAnnotation = [...annotations].reverse().find((ann) => isPointInAnnotation(point, ann));
      if (clickedAnnotation) {
        onAnnotationSelect(clickedAnnotation);
        setDraggingAnnotation(clickedAnnotation.id);
        setDragOffset({
          x: point.x - clickedAnnotation.x,
          y: point.y - clickedAnnotation.y,
        });
        // Store the initial annotation state for undo
        dragStartAnnotationRef.current = { ...clickedAnnotation };
      } else {
        onAnnotationSelect(null);
      }
    } else {
      setIsDrawing(true);
      setStartPoint(point);
      setCurrentPoint(point);
    }
  };

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const point = getCanvasCoordinates(e);

    if (draggingAnnotation && dragOffset) {
      // Cancel any pending RAF
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
      
      rafRef.current = requestAnimationFrame(() => {
        const annotation = annotations.find((ann) => ann.id === draggingAnnotation);
        if (annotation) {
          const dx = point.x - dragOffset.x - annotation.x;
          const dy = point.y - dragOffset.y - annotation.y;
          const updated = {
            ...annotation,
            x: point.x - dragOffset.x,
            y: point.y - dragOffset.y,
          };
          if (annotation.type === "line" || annotation.type === "arrow") {
            (updated as typeof annotation & { endX: number; endY: number }).endX = annotation.endX + dx;
            (updated as typeof annotation & { endX: number; endY: number }).endY = annotation.endY + dy;
          }
          // Use transient update if available (no history push)
          if (onAnnotationUpdateTransient) {
            onAnnotationUpdateTransient(updated as Annotation);
          } else {
            // Fallback - will push to history on every move (bad for perf)
            onAnnotationUpdate(updated as Annotation);
          }
        }
      });
    } else if (isDrawing && startPoint) {
      setCurrentPoint(point);
    }
  }, [getCanvasCoordinates, draggingAnnotation, dragOffset, annotations, isDrawing, startPoint, onAnnotationUpdateTransient, onAnnotationUpdate]);

  const handleMouseUp = () => {
    if (isDrawing && startPoint && currentPoint && selectedTool && selectedTool !== "select") {
      const newAnnotation = createAnnotation(selectedTool, startPoint, currentPoint);
      if (newAnnotation) {
        onAnnotationAdd(newAnnotation);
        if (selectedTool === "number") {
          setNextNumber((prev) => prev + 1);
        }
      }
      setIsDrawing(false);
      setStartPoint(null);
      setCurrentPoint(null);
    } else if (draggingAnnotation) {
      // Commit the final position to history
      const annotation = annotations.find((ann) => ann.id === draggingAnnotation);
      if (annotation && dragStartAnnotationRef.current) {
        // Only commit if position actually changed
        const startAnn = dragStartAnnotationRef.current;
        if (annotation.x !== startAnn.x || annotation.y !== startAnn.y) {
          onAnnotationUpdate(annotation);
        }
      }
      setDraggingAnnotation(null);
      setDragOffset(null);
      dragStartAnnotationRef.current = null;
    }
  };

  if (!previewUrl) {
    return null;
  }

  return (
    <div ref={containerRef} className="relative flex items-center justify-center w-full h-full min-w-0 min-h-0">
      <canvas
        ref={canvasRef}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        style={{
          maxWidth: "100%",
          maxHeight: "100%",
          width: "auto",
          height: "auto",
          display: "block",
        }}
        className={cn(
          "cursor-crosshair rounded-lg shadow-2xl border border-zinc-800",
          selectedTool === "select" && "cursor-pointer"
        )}
      />
    </div>
  );
});
