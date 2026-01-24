import { Annotation } from "@/types/annotations";

export function drawAnnotationOnCanvas(ctx: CanvasRenderingContext2D, annotation: Annotation) {
  const primaryColor = annotation.fill.hex;
  const primaryOpacity = annotation.fill.opacity / 100;

  ctx.save();

  const primaryRgba = hexToRgba(primaryColor, primaryOpacity);

  switch (annotation.type) {
    case "circle": {
      ctx.beginPath();
      ctx.arc(annotation.x, annotation.y, annotation.radius, 0, Math.PI * 2);
      ctx.strokeStyle = primaryRgba;
      ctx.lineWidth = annotation.border.width || 5;
      ctx.stroke();
      break;
    }
    case "rectangle": {
      ctx.strokeStyle = primaryRgba;
      ctx.lineWidth = annotation.border.width || 5;
      ctx.strokeRect(annotation.x, annotation.y, annotation.width, annotation.height);
      break;
    }
    case "line": {
      ctx.beginPath();
      ctx.moveTo(annotation.x, annotation.y);
      if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
        const cp = annotation.controlPoints[0];
        ctx.quadraticCurveTo(cp.x, cp.y, annotation.endX, annotation.endY);
      } else {
        ctx.lineTo(annotation.endX, annotation.endY);
      }
      ctx.strokeStyle = primaryRgba;
      ctx.lineWidth = annotation.border.width || 5;
      ctx.lineCap = "round";
      ctx.stroke();
      break;
    }
    case "arrow": {
      const lineWidth = annotation.border.width || 5;
      
      let angle: number;
      let lineEndX: number;
      let lineEndY: number;
      
      if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
        const cp = annotation.controlPoints[0];
        const dx = annotation.endX - cp.x;
        const dy = annotation.endY - cp.y;
        angle = Math.atan2(dy, dx);
      } else {
        angle = Math.atan2(annotation.endY - annotation.y, annotation.endX - annotation.x);
      }
      
      let arrowHeadLength: number;
      if (annotation.arrowType === "thick") {
        arrowHeadLength = Math.max(lineWidth * 6, 20);
      } else if (annotation.arrowType === "thin") {
        arrowHeadLength = Math.max(lineWidth * 3, 12);
      } else {
        arrowHeadLength = 0;
      }
      
      const shortenBy = annotation.arrowType !== "none" ? arrowHeadLength * 0.7 : 0;
      lineEndX = annotation.endX - shortenBy * Math.cos(angle);
      lineEndY = annotation.endY - shortenBy * Math.sin(angle);
      
      ctx.beginPath();
      ctx.moveTo(annotation.x, annotation.y);
      if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
        const cp = annotation.controlPoints[0];
        ctx.quadraticCurveTo(cp.x, cp.y, lineEndX, lineEndY);
      } else {
        ctx.lineTo(lineEndX, lineEndY);
      }
      ctx.strokeStyle = primaryRgba;
      ctx.lineWidth = lineWidth;
      ctx.lineCap = "round";
      ctx.stroke();

      if (annotation.arrowType !== "none" && arrowHeadLength > 0) {
        ctx.beginPath();
        ctx.moveTo(annotation.endX, annotation.endY);
        ctx.lineTo(
          annotation.endX - arrowHeadLength * Math.cos(angle - Math.PI / 6),
          annotation.endY - arrowHeadLength * Math.sin(angle - Math.PI / 6)
        );
        ctx.lineTo(
          annotation.endX - arrowHeadLength * 0.6 * Math.cos(angle),
          annotation.endY - arrowHeadLength * 0.6 * Math.sin(angle)
        );
        ctx.lineTo(
          annotation.endX - arrowHeadLength * Math.cos(angle + Math.PI / 6),
          annotation.endY - arrowHeadLength * Math.sin(angle + Math.PI / 6)
        );
        ctx.closePath();
        ctx.fillStyle = primaryRgba;
        ctx.fill();
      }
      break;
    }
    case "text": {
      ctx.fillStyle = primaryRgba;
      ctx.font = `${annotation.fontSize}px ${annotation.fontFamily}`;
      ctx.fillText(annotation.text, annotation.x, annotation.y + annotation.fontSize);
      break;
    }
    case "number": {
      ctx.beginPath();
      ctx.arc(annotation.x, annotation.y, annotation.radius, 0, Math.PI * 2);
      ctx.fillStyle = primaryRgba;
      ctx.fill();
      if (annotation.border.width > 0) {
        ctx.strokeStyle = primaryRgba;
        ctx.lineWidth = annotation.border.width;
        ctx.stroke();
      }
      ctx.fillStyle = "#ffffff";
      ctx.font = `bold ${annotation.radius * 1.2}px Arial`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(annotation.number.toString(), annotation.x, annotation.y);
      break;
    }
    case "blur": {
      const x = Math.max(0, Math.floor(annotation.x));
      const y = Math.max(0, Math.floor(annotation.y));
      const width = Math.min(Math.ceil(annotation.width), ctx.canvas.width - x);
      const height = Math.min(Math.ceil(annotation.height), ctx.canvas.height - y);
      
      if (width > 0 && height > 0) {
        const imageData = ctx.getImageData(x, y, width, height);
        const blurAmount = annotation.blurAmount || 20;
        const blurredData = applyBoxBlur(imageData, blurAmount);
        ctx.putImageData(blurredData, x, y);
        
        ctx.strokeStyle = "rgba(100, 100, 255, 0.3)";
        ctx.lineWidth = 2;
        ctx.setLineDash([5, 5]);
        ctx.strokeRect(x, y, width, height);
        ctx.setLineDash([]);
      }
      break;
    }
  }

  ctx.restore();
}

// Box blur algorithm for performance
function applyBoxBlur(imageData: ImageData, radius: number): ImageData {
  const width = imageData.width;
  const height = imageData.height;
  const data = new Uint8ClampedArray(imageData.data);
  const output = new Uint8ClampedArray(imageData.data);
  
  // Horizontal pass
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let r = 0, g = 0, b = 0, a = 0, count = 0;
      
      for (let kx = -radius; kx <= radius; kx++) {
        const px = Math.min(Math.max(x + kx, 0), width - 1);
        const offset = (y * width + px) * 4;
        r += data[offset];
        g += data[offset + 1];
        b += data[offset + 2];
        a += data[offset + 3];
        count++;
      }
      
      const offset = (y * width + x) * 4;
      output[offset] = r / count;
      output[offset + 1] = g / count;
      output[offset + 2] = b / count;
      output[offset + 3] = a / count;
    }
  }
  
  // Vertical pass
  const temp = new Uint8ClampedArray(output);
  for (let x = 0; x < width; x++) {
    for (let y = 0; y < height; y++) {
      let r = 0, g = 0, b = 0, a = 0, count = 0;
      
      for (let ky = -radius; ky <= radius; ky++) {
        const py = Math.min(Math.max(y + ky, 0), height - 1);
        const offset = (py * width + x) * 4;
        r += temp[offset];
        g += temp[offset + 1];
        b += temp[offset + 2];
        a += temp[offset + 3];
        count++;
      }
      
      const offset = (y * width + x) * 4;
      output[offset] = r / count;
      output[offset + 1] = g / count;
      output[offset + 2] = b / count;
      output[offset + 3] = a / count;
    }
  }
  
  return new ImageData(output, width, height);
}

function hexToRgba(hex: string, alpha: number): string {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!result) return `rgba(0, 0, 0, ${alpha})`;
  const r = parseInt(result[1], 16);
  const g = parseInt(result[2], 16);
  const b = parseInt(result[3], 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}
