export type ToolType = "circle" | "rectangle" | "line" | "arrow" | "text" | "number" | "select" | null;

export type LineType = "straight" | "curved";

export type ArrowType = "thin" | "thick" | "none";

export type HorizontalAlign = "left" | "center" | "right";
export type VerticalAlign = "top" | "middle" | "bottom";

export interface Point {
  x: number;
  y: number;
}

export interface Color {
  hex: string;
  opacity: number;
}

export interface BaseAnnotation {
  id: string;
  type: ToolType;
  x: number;
  y: number;
  fill: Color;
  border: {
    width: number;
    color: Color;
  };
  alignment: {
    horizontal: HorizontalAlign;
    vertical: VerticalAlign;
  };
}

export interface CircleAnnotation extends BaseAnnotation {
  type: "circle";
  radius: number;
}

export interface RectangleAnnotation extends BaseAnnotation {
  type: "rectangle";
  width: number;
  height: number;
}

export interface LineAnnotation extends BaseAnnotation {
  type: "line";
  endX: number;
  endY: number;
  lineType: LineType;
  controlPoints?: Point[];
}

export interface ArrowAnnotation extends BaseAnnotation {
  type: "arrow";
  endX: number;
  endY: number;
  lineType: LineType;
  arrowType: ArrowType;
  controlPoints?: Point[];
}

export interface TextAnnotation extends BaseAnnotation {
  type: "text";
  text: string;
  fontSize: number;
  fontFamily: string;
  width: number;
  height: number;
}

export interface NumberAnnotation extends BaseAnnotation {
  type: "number";
  number: number;
  radius: number;
}

export type Annotation =
  | CircleAnnotation
  | RectangleAnnotation
  | LineAnnotation
  | ArrowAnnotation
  | TextAnnotation
  | NumberAnnotation;
