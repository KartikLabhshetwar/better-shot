import { useRef, useEffect, useState, useCallback, memo } from "react";
import { Annotation, ToolType, Point } from "@/types/annotations";
import { drawAnnotationOnCanvas } from "@/lib/annotation-utils";
import { cn } from "@/lib/utils";

function getDistanceToQuadraticCurve(
  point: Point,
  start: Point,
  control: Point,
  end: Point
): number {
  let minDistance = Infinity;
  const steps = 50;
  
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const x = (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * control.x + t * t * end.x;
    const y = (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * control.y + t * t * end.y;
    const distance = Math.sqrt(Math.pow(point.x - x, 2) + Math.pow(point.y - y, 2));
    minDistance = Math.min(minDistance, distance);
  }
  
  return minDistance;
}

interface AnnotationCanvasProps {
  annotations: Annotation[];
  selectedAnnotation: Annotation | null;
  selectedTool: ToolType;
  previewUrl: string | null;
  showTransparencyGrid?: boolean;
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
  showTransparencyGrid = false,
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
  const [resizingAnnotation, setResizingAnnotation] = useState<string | null>(null);
  const [resizeHandle, setResizeHandle] = useState<string | null>(null);
  const [resizeStartPoint, setResizeStartPoint] = useState<Point | null>(null);
  const [hoveredHandleId, setHoveredHandleId] = useState<string | null>(null);
  
  // Track initial position for drag operations
  const dragStartAnnotationRef = useRef<Annotation | null>(null);
  const resizeStartAnnotationRef = useRef<Annotation | null>(null);

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

  const HANDLE_SIZE = 12;
  const HANDLE_HIT_SIZE = 24;
  const HANDLE_HOVER_SIZE = 16;
  const LINE_HANDLE_SIZE = 14;
  const LINE_HANDLE_HIT_SIZE = 28;

  const getResizeHandles = useCallback((annotation: Annotation): Array<{ id: string; x: number; y: number }> => {
    switch (annotation.type) {
      case "circle": {
        return [
          { id: "e", x: annotation.x + annotation.radius, y: annotation.y },
          { id: "w", x: annotation.x - annotation.radius, y: annotation.y },
          { id: "n", x: annotation.x, y: annotation.y - annotation.radius },
          { id: "s", x: annotation.x, y: annotation.y + annotation.radius },
        ];
      }
      case "rectangle": {
        return [
          { id: "nw", x: annotation.x, y: annotation.y },
          { id: "ne", x: annotation.x + annotation.width, y: annotation.y },
          { id: "sw", x: annotation.x, y: annotation.y + annotation.height },
          { id: "se", x: annotation.x + annotation.width, y: annotation.y + annotation.height },
          { id: "n", x: annotation.x + annotation.width / 2, y: annotation.y },
          { id: "s", x: annotation.x + annotation.width / 2, y: annotation.y + annotation.height },
          { id: "w", x: annotation.x, y: annotation.y + annotation.height / 2 },
          { id: "e", x: annotation.x + annotation.width, y: annotation.y + annotation.height / 2 },
        ];
      }
      case "line":
      case "arrow": {
        const handles = [
          { id: "start", x: annotation.x, y: annotation.y },
          { id: "end", x: annotation.endX, y: annotation.endY },
        ];
        if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
          handles.push({ id: "control", x: annotation.controlPoints[0].x, y: annotation.controlPoints[0].y });
        }
        return handles;
      }
      case "text": {
        return [
          { id: "nw", x: annotation.x, y: annotation.y },
          { id: "ne", x: annotation.x + annotation.width, y: annotation.y },
          { id: "sw", x: annotation.x, y: annotation.y + annotation.height },
          { id: "se", x: annotation.x + annotation.width, y: annotation.y + annotation.height },
        ];
      }
      case "number": {
        return [
          { id: "e", x: annotation.x + annotation.radius, y: annotation.y },
          { id: "w", x: annotation.x - annotation.radius, y: annotation.y },
          { id: "n", x: annotation.x, y: annotation.y - annotation.radius },
          { id: "s", x: annotation.x, y: annotation.y + annotation.radius },
        ];
      }
      default:
        return [];
    }
  }, []);

  const isPointOnHandle = useCallback((point: Point, handle: { x: number; y: number }, annotation?: Annotation): boolean => {
    const distance = Math.sqrt(Math.pow(point.x - handle.x, 2) + Math.pow(point.y - handle.y, 2));
    const isLineOrArrow = annotation && (annotation.type === "line" || annotation.type === "arrow");
    const hitSize = isLineOrArrow ? LINE_HANDLE_HIT_SIZE : HANDLE_HIT_SIZE;
    return distance <= hitSize / 2;
  }, []);

  const getHandleAtPoint = useCallback((point: Point, annotation: Annotation): string | null => {
    const handles = getResizeHandles(annotation);
    for (const handle of handles) {
      if (isPointOnHandle(point, handle, annotation)) {
        return handle.id;
      }
    }
    return null;
  }, [getResizeHandles, isPointOnHandle]);

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
        const lineWidth = annotation.border?.width || 5;
        const hitTolerance = Math.max(20, lineWidth + 15);
        
        if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
          const cp = annotation.controlPoints[0];
          const minDistance = getDistanceToQuadraticCurve(
            point,
            { x: annotation.x, y: annotation.y },
            cp,
            { x: annotation.endX, y: annotation.endY }
          );
          return minDistance <= hitTolerance;
        } else {
          const dx = annotation.endX - annotation.x;
          const dy = annotation.endY - annotation.y;
          const length = Math.sqrt(dx * dx + dy * dy);
          
          if (length === 0) {
            const distance = Math.sqrt(
              Math.pow(point.x - annotation.x, 2) + Math.pow(point.y - annotation.y, 2)
            );
            return distance <= hitTolerance;
          }
          
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
          return distance <= hitTolerance;
        }
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

  const drawResizeHandles = useCallback((ctx: CanvasRenderingContext2D, annotation: Annotation, activeHandleId?: string | null) => {
    const handles = getResizeHandles(annotation);
    ctx.save();
    
    if ((annotation.type === "line" || annotation.type === "arrow") && 
        annotation.lineType === "curved" && 
        annotation.controlPoints && 
        annotation.controlPoints.length > 0) {
      const cp = annotation.controlPoints[0];
      ctx.strokeStyle = "rgba(59, 130, 246, 0.3)";
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(annotation.x, annotation.y);
      ctx.lineTo(cp.x, cp.y);
      ctx.lineTo(annotation.endX, annotation.endY);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    
    handles.forEach((handle) => {
      const isHovered = hoveredHandleId === handle.id && !activeHandleId;
      const isActive = activeHandleId === handle.id;
      const isControl = handle.id === "control";
      const isLineOrArrow = annotation.type === "line" || annotation.type === "arrow";
      const baseSize = isLineOrArrow ? LINE_HANDLE_SIZE : HANDLE_SIZE;
      const hoverSize = isLineOrArrow ? LINE_HANDLE_SIZE + 4 : HANDLE_HOVER_SIZE;
      const size = (isHovered || isActive) ? hoverSize : baseSize;
      const fillColor = isControl ? "#10b981" : (isActive ? "#2563eb" : "#3b82f6");
      
      ctx.save();
      
      if (isHovered || isActive) {
        ctx.shadowColor = "rgba(59, 130, 246, 0.6)";
        ctx.shadowBlur = isActive ? 12 : 8;
      } else {
        ctx.shadowColor = "transparent";
        ctx.shadowBlur = 0;
      }
      
      ctx.fillStyle = "rgba(255, 255, 255, 0.9)";
      ctx.beginPath();
      ctx.arc(handle.x, handle.y, size / 2 + 2, 0, Math.PI * 2);
      ctx.fill();
      
      ctx.fillStyle = fillColor;
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = (isHovered || isActive) ? 3.5 : 2.5;
      
      ctx.beginPath();
      ctx.arc(handle.x, handle.y, size / 2, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      
      if (isHovered || isActive) {
        ctx.shadowColor = "transparent";
        ctx.shadowBlur = 0;
        ctx.strokeStyle = isActive ? "rgba(37, 99, 235, 0.6)" : "rgba(59, 130, 246, 0.5)";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(handle.x, handle.y, size / 2 + 6, 0, Math.PI * 2);
        ctx.stroke();
      }
      
      ctx.restore();
    });
    
    ctx.restore();
  }, [getResizeHandles, hoveredHandleId]);

  const drawAnnotation = useCallback(
    (ctx: CanvasRenderingContext2D, annotation: Annotation, isSelected: boolean) => {
      drawAnnotationOnCanvas(ctx, annotation);

      if (isSelected && annotation.type !== "blur") {
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
            let minX = Math.min(annotation.x, annotation.endX);
            let minY = Math.min(annotation.y, annotation.endY);
            let maxX = Math.max(annotation.x, annotation.endX);
            let maxY = Math.max(annotation.y, annotation.endY);
            
            if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
              const cp = annotation.controlPoints[0];
              minX = Math.min(minX, cp.x);
              minY = Math.min(minY, cp.y);
              maxX = Math.max(maxX, cp.x);
              maxY = Math.max(maxY, cp.y);
            }
            
            const padding = 8;
            ctx.strokeRect(
              minX - padding,
              minY - padding,
              maxX - minX + padding * 2,
              maxY - minY + padding * 2
            );
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
        }
        
        ctx.setLineDash([]);
        ctx.restore();
        
        drawResizeHandles(ctx, annotation, resizingAnnotation === annotation.id ? resizeHandle : null);
      }
    },
    [drawResizeHandles]
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
  }, [imageLoaded, annotations, selectedAnnotation, isDrawing, startPoint, currentPoint, selectedTool, drawAnnotation, createAnnotation, hoveredHandleId]);

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
      if (selectedAnnotation && selectedAnnotation.type !== "blur") {
        const handle = getHandleAtPoint(point, selectedAnnotation);
        if (handle) {
          setResizingAnnotation(selectedAnnotation.id);
          setResizeHandle(handle);
          setResizeStartPoint(point);
          resizeStartAnnotationRef.current = { ...selectedAnnotation };
          return;
        }
      }

      let clickedAnnotation = null;
      let clickedHandle = null;
      
      for (const ann of [...annotations].reverse()) {
        if (ann.type !== "blur") {
          const handle = getHandleAtPoint(point, ann);
          if (handle) {
            clickedAnnotation = ann;
            clickedHandle = handle;
            break;
          }
        }
      }
      
      if (!clickedAnnotation) {
        clickedAnnotation = [...annotations].reverse().find((ann) => isPointInAnnotation(point, ann));
      }
      
      if (clickedAnnotation) {
        onAnnotationSelect(clickedAnnotation);
        if (clickedHandle && clickedAnnotation.type !== "blur") {
          setResizingAnnotation(clickedAnnotation.id);
          setResizeHandle(clickedHandle);
          setResizeStartPoint(point);
          resizeStartAnnotationRef.current = { ...clickedAnnotation };
        } else {
          setDraggingAnnotation(clickedAnnotation.id);
          setDragOffset({
            x: point.x - clickedAnnotation.x,
            y: point.y - clickedAnnotation.y,
          });
          dragStartAnnotationRef.current = { ...clickedAnnotation };
        }
      } else {
        onAnnotationSelect(null);
      }
    } else {
      setIsDrawing(true);
      setStartPoint(point);
      setCurrentPoint(point);
    }
  };

  const applyResize = useCallback((annotation: Annotation, handle: string, point: Point, startPoint: Point, startAnnotation: Annotation): Annotation => {
    switch (annotation.type) {
      case "circle": {
        const distance = Math.sqrt(
          Math.pow(point.x - startAnnotation.x, 2) + Math.pow(point.y - startAnnotation.y, 2)
        );
        const newRadius = Math.max(5, distance);
        return { ...annotation, radius: newRadius };
      }
      case "rectangle": {
        if (annotation.type !== "rectangle" || startAnnotation.type !== "rectangle") return annotation;
        const dx = point.x - startPoint.x;
        const dy = point.y - startPoint.y;
        let { x, y, width, height } = startAnnotation;
        
        if (handle === "nw") {
          x = startAnnotation.x + dx;
          y = startAnnotation.y + dy;
          width = Math.max(10, startAnnotation.width - dx);
          height = Math.max(10, startAnnotation.height - dy);
        } else if (handle === "ne") {
          y = startAnnotation.y + dy;
          width = Math.max(10, startAnnotation.width + dx);
          height = Math.max(10, startAnnotation.height - dy);
        } else if (handle === "sw") {
          x = startAnnotation.x + dx;
          width = Math.max(10, startAnnotation.width - dx);
          height = Math.max(10, startAnnotation.height + dy);
        } else if (handle === "se") {
          width = Math.max(10, startAnnotation.width + dx);
          height = Math.max(10, startAnnotation.height + dy);
        } else if (handle === "n") {
          y = startAnnotation.y + dy;
          height = Math.max(10, startAnnotation.height - dy);
        } else if (handle === "s") {
          height = Math.max(10, startAnnotation.height + dy);
        } else if (handle === "w") {
          x = startAnnotation.x + dx;
          width = Math.max(10, startAnnotation.width - dx);
        } else if (handle === "e") {
          width = Math.max(10, startAnnotation.width + dx);
        }
        
        return { ...annotation, x, y, width, height };
      }
      case "line":
      case "arrow": {
        if (annotation.type !== "line" && annotation.type !== "arrow") return annotation;
        if (handle === "start") {
          const updated = { ...annotation, x: point.x, y: point.y };
          if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
            const dx = point.x - startAnnotation.x;
            const dy = point.y - startAnnotation.y;
            updated.controlPoints = [{
              x: annotation.controlPoints[0].x + dx,
              y: annotation.controlPoints[0].y + dy,
            }];
          }
          return updated;
        } else if (handle === "end") {
          if (startAnnotation.type !== "line" && startAnnotation.type !== "arrow") return annotation;
          const updated = { ...annotation, endX: point.x, endY: point.y };
          if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
            const dx = point.x - startAnnotation.endX;
            const dy = point.y - startAnnotation.endY;
            updated.controlPoints = [{
              x: annotation.controlPoints[0].x + dx,
              y: annotation.controlPoints[0].y + dy,
            }];
          }
          return updated;
        } else if (handle === "control" && annotation.lineType === "curved") {
          return { ...annotation, controlPoints: [{ x: point.x, y: point.y }] };
        }
        return annotation;
      }
      case "text": {
        if (annotation.type !== "text" || startAnnotation.type !== "text") return annotation;
        
        const isRightHandle = handle === "ne" || handle === "se" || handle === "e";
        const isBottomHandle = handle === "sw" || handle === "se" || handle === "s";
        const isLeftHandle = handle === "nw" || handle === "sw" || handle === "w";
        const isTopHandle = handle === "nw" || handle === "ne" || handle === "n";
        
        let scaleX = 1;
        let scaleY = 1;
        
        if (isRightHandle) {
          scaleX = Math.max(0.1, (point.x - startAnnotation.x) / startAnnotation.width);
        } else if (isLeftHandle) {
          scaleX = Math.max(0.1, (startAnnotation.x - point.x) / startAnnotation.width);
        }
        
        if (isBottomHandle) {
          scaleY = Math.max(0.1, (point.y - startAnnotation.y) / startAnnotation.height);
        } else if (isTopHandle) {
          scaleY = Math.max(0.1, (startAnnotation.y - point.y) / startAnnotation.height);
        }
        
        const scale = Math.max(scaleX, scaleY);
        const newFontSize = Math.max(8, Math.round(startAnnotation.fontSize * scale));
        const fontScale = newFontSize / startAnnotation.fontSize;
        
        let newX = startAnnotation.x;
        let newY = startAnnotation.y;
        
        if (isLeftHandle) {
          newX = startAnnotation.x + startAnnotation.width - (startAnnotation.width * fontScale);
        }
        if (isTopHandle) {
          newY = startAnnotation.y + startAnnotation.height - (startAnnotation.height * fontScale);
        }
        
        const newWidth = Math.max(50, Math.round(startAnnotation.width * fontScale));
        const newHeight = Math.max(20, Math.round(startAnnotation.height * fontScale));
        
        return { 
          ...annotation, 
          x: newX, 
          y: newY, 
          fontSize: newFontSize, 
          width: newWidth, 
          height: newHeight 
        };
      }
      case "number": {
        const distance = Math.sqrt(
          Math.pow(point.x - startAnnotation.x, 2) + Math.pow(point.y - startAnnotation.y, 2)
        );
        const newRadius = Math.max(10, distance);
        return { ...annotation, radius: newRadius };
      }
      default:
        return annotation;
    }
  }, []);

  const getCursorForHandle = useCallback((handle: string | null): string => {
    if (!handle) return "default";
    
    const cursorMap: Record<string, string> = {
      "nw": "nw-resize",
      "ne": "ne-resize",
      "sw": "sw-resize",
      "se": "se-resize",
      "n": "n-resize",
      "s": "s-resize",
      "w": "w-resize",
      "e": "e-resize",
      "start": "move",
      "end": "move",
      "control": "crosshair",
    };
    
    return cursorMap[handle] || "default";
  }, []);

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const point = getCanvasCoordinates(e);
    const canvas = canvasRef.current;

    if (resizingAnnotation && resizeHandle && resizeStartPoint && resizeStartAnnotationRef.current) {
      setHoveredHandleId(null);
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
      
      rafRef.current = requestAnimationFrame(() => {
        const annotation = annotations.find((ann) => ann.id === resizingAnnotation);
        if (annotation && resizeStartAnnotationRef.current) {
          const updated = applyResize(annotation, resizeHandle, point, resizeStartPoint, resizeStartAnnotationRef.current);
          if (onAnnotationUpdateTransient) {
            onAnnotationUpdateTransient(updated);
          } else {
            onAnnotationUpdate(updated);
          }
        }
      });
    } else if (draggingAnnotation && dragOffset) {
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
          if (onAnnotationUpdateTransient) {
            onAnnotationUpdateTransient(updated as Annotation);
          } else {
            onAnnotationUpdate(updated as Annotation);
          }
        }
      });
    } else if (isDrawing && startPoint) {
      setCurrentPoint(point);
    } else if (selectedTool === "select" && selectedAnnotation && selectedAnnotation.type !== "blur" && canvas) {
      const handle = getHandleAtPoint(point, selectedAnnotation);
      if (handle) {
        canvas.style.cursor = getCursorForHandle(handle);
        if (hoveredHandleId !== handle) {
          setHoveredHandleId(handle);
        }
      } else {
        if (hoveredHandleId !== null) {
          setHoveredHandleId(null);
        }
        if (isPointInAnnotation(point, selectedAnnotation)) {
          canvas.style.cursor = "move";
        } else {
          canvas.style.cursor = "default";
        }
      }
    } else if (canvas && selectedTool === "select") {
      canvas.style.cursor = "default";
      if (hoveredHandleId !== null) {
        setHoveredHandleId(null);
      }
    } else {
      if (hoveredHandleId !== null) {
        setHoveredHandleId(null);
      }
    }
  }, [getCanvasCoordinates, resizingAnnotation, resizeHandle, resizeStartPoint, draggingAnnotation, dragOffset, annotations, isDrawing, startPoint, selectedTool, selectedAnnotation, applyResize, getHandleAtPoint, isPointInAnnotation, getCursorForHandle, onAnnotationUpdateTransient, onAnnotationUpdate]);

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
    } else if (resizingAnnotation && resizeStartAnnotationRef.current) {
      const annotation = annotations.find((ann) => ann.id === resizingAnnotation);
      if (annotation) {
        const startAnn = resizeStartAnnotationRef.current;
        let changed = false;
        
        if (annotation.type === "circle" && startAnn.type === "circle") {
          changed = annotation.radius !== startAnn.radius;
        } else if (annotation.type === "number" && startAnn.type === "number") {
          changed = annotation.radius !== startAnn.radius;
        } else if (annotation.type === "rectangle" && startAnn.type === "rectangle") {
          changed = annotation.x !== startAnn.x || annotation.y !== startAnn.y || 
                   annotation.width !== startAnn.width || annotation.height !== startAnn.height;
        } else if (annotation.type === "text" && startAnn.type === "text") {
          changed = annotation.x !== startAnn.x || annotation.y !== startAnn.y || 
                    annotation.width !== startAnn.width || annotation.height !== startAnn.height ||
                    annotation.fontSize !== startAnn.fontSize;
        } else if ((annotation.type === "line" || annotation.type === "arrow") && 
                   (startAnn.type === "line" || startAnn.type === "arrow")) {
          changed = annotation.x !== startAnn.x || annotation.y !== startAnn.y ||
                   annotation.endX !== startAnn.endX || annotation.endY !== startAnn.endY;
        }
        
        if (changed) {
          onAnnotationUpdate(annotation);
        }
      }
      setResizingAnnotation(null);
      setResizeHandle(null);
      setResizeStartPoint(null);
      resizeStartAnnotationRef.current = null;
    } else if (draggingAnnotation) {
      const annotation = annotations.find((ann) => ann.id === draggingAnnotation);
      if (annotation && dragStartAnnotationRef.current) {
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
          "rounded-lg shadow-2xl border border-border",
          showTransparencyGrid &&
            "bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGRlZnM+PHBhdHRlcm4gaWQ9ImNoZWNrZXJib2FyZCIgd2lkdGg9IjEwIiBoZWlnaHQ9IjEwIiBwYXR0ZXJuVW5pdHM9InVzZXJTcGFjZU9uVXNlIj48cmVjdCB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjZmZmIi8+PHJlY3QgeD0iNSIgd2lkdGg9IjUiIGhlaWdodD0iNSIgZmlsbD0iI2UwZTBlMCIvPjxyZWN0IHk9IjUiIHdpZHRoPSI1IiBoZWlnaHQ9IjUiIGZpbGw9IiNlMGUwZTAiLz48cmVjdCB4PSI1IiB5PSI1IiB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjZmZmIi8+PC9wYXR0ZXJuPjwvZGVmcz48cmVjdCB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIGZpbGw9InVybCgjY2hlY2tlcmJvYXJkKSIvPjwvc3ZnPg==')]",
          selectedTool === "select" ? "" : "cursor-crosshair"
        )}
      />
    </div>
  );
});
