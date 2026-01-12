import { Annotation } from "@/types/annotations";

export function drawAnnotationOnCanvas(ctx: CanvasRenderingContext2D, annotation: Annotation) {
  const fillColor = annotation.fill.hex;
  const fillOpacity = annotation.fill.opacity / 100;
  const borderColor = annotation.border.color.hex;
  const borderOpacity = annotation.border.color.opacity / 100;
  const borderWidth = annotation.border.width;

  ctx.save();

  const fillRgba = hexToRgba(fillColor, fillOpacity);
  const borderRgba = hexToRgba(borderColor, borderOpacity);

  switch (annotation.type) {
    case "circle": {
      ctx.beginPath();
      ctx.arc(annotation.x, annotation.y, annotation.radius, 0, Math.PI * 2);
      ctx.strokeStyle = borderRgba;
      ctx.lineWidth = borderWidth || 5;
      ctx.stroke();
      break;
    }
    case "rectangle": {
      ctx.strokeStyle = borderRgba;
      ctx.lineWidth = borderWidth || 5;
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
      ctx.strokeStyle = fillRgba;
      ctx.lineWidth = borderWidth || 5;
      ctx.lineCap = "round";
      ctx.stroke();
      break;
    }
    case "arrow": {
      const lineWidth = borderWidth || 5;
      
      // Calculate arrow properties based on line width
      const arrowHeadLength = annotation.arrowType === "thick" ? lineWidth * 4 : lineWidth * 3;
      
      // Calculate the angle of the line
      const angle = Math.atan2(annotation.endY - annotation.y, annotation.endX - annotation.x);
      
      // Shorten the line so it doesn't overlap with the arrowhead
      const shortenBy = annotation.arrowType !== "none" ? arrowHeadLength * 0.7 : 0;
      const lineEndX = annotation.endX - shortenBy * Math.cos(angle);
      const lineEndY = annotation.endY - shortenBy * Math.sin(angle);
      
      // Draw the line
      ctx.beginPath();
      ctx.moveTo(annotation.x, annotation.y);
      if (annotation.lineType === "curved" && annotation.controlPoints && annotation.controlPoints.length > 0) {
        const cp = annotation.controlPoints[0];
        ctx.quadraticCurveTo(cp.x, cp.y, lineEndX, lineEndY);
      } else {
        ctx.lineTo(lineEndX, lineEndY);
      }
      ctx.strokeStyle = fillRgba;
      ctx.lineWidth = lineWidth;
      ctx.lineCap = "round";
      ctx.stroke();

      // Draw the arrowhead
      if (annotation.arrowType !== "none") {
        ctx.beginPath();
        ctx.moveTo(annotation.endX, annotation.endY);
        ctx.lineTo(
          annotation.endX - arrowHeadLength * Math.cos(angle - Math.PI / 7),
          annotation.endY - arrowHeadLength * Math.sin(angle - Math.PI / 7)
        );
        ctx.lineTo(
          annotation.endX - arrowHeadLength * 0.6 * Math.cos(angle),
          annotation.endY - arrowHeadLength * 0.6 * Math.sin(angle)
        );
        ctx.lineTo(
          annotation.endX - arrowHeadLength * Math.cos(angle + Math.PI / 7),
          annotation.endY - arrowHeadLength * Math.sin(angle + Math.PI / 7)
        );
        ctx.closePath();
        ctx.fillStyle = fillRgba;
        ctx.fill();
      }
      break;
    }
    case "text": {
      ctx.fillStyle = fillRgba;
      ctx.font = `${annotation.fontSize}px ${annotation.fontFamily}`;
      ctx.fillText(annotation.text, annotation.x, annotation.y + annotation.fontSize);
      break;
    }
    case "number": {
      ctx.beginPath();
      ctx.arc(annotation.x, annotation.y, annotation.radius, 0, Math.PI * 2);
      ctx.fillStyle = fillRgba;
      ctx.fill();
      if (borderWidth > 0) {
        ctx.strokeStyle = borderRgba;
        ctx.lineWidth = borderWidth;
        ctx.stroke();
      }
      ctx.fillStyle = "#ffffff";
      ctx.font = `bold ${annotation.radius * 1.2}px Arial`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(annotation.number.toString(), annotation.x, annotation.y);
      break;
    }
  }

  ctx.restore();
}

function hexToRgba(hex: string, alpha: number): string {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!result) return `rgba(0, 0, 0, ${alpha})`;
  const r = parseInt(result[1], 16);
  const g = parseInt(result[2], 16);
  const b = parseInt(result[3], 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}
