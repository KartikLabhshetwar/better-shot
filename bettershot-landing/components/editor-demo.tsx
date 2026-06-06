"use client";

import React from "react";
import { Player } from "@remotion/player";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";

const COLORS_SOLID = [
  "transparent",
  "#000000",
  "#f5f5f4",
  "#374151",
  "#ef4444",
  "#f97316",
  "#eab308",
  "#22c55e",
  "#3b82f6",
  "#8b5cf6",
  "#ec4899",
  "#06b6d4",
];

const GRADIENTS = [
  "linear-gradient(135deg, #a8edea, #fed6e3)",
  "linear-gradient(135deg, #3b82f6, #8b5cf6)",
  "linear-gradient(135deg, #f97316, #ec4899)",
  "linear-gradient(135deg, #06b6d4, #3b82f6)",
  "linear-gradient(135deg, #8b5cf6, #ec4899)",
  "linear-gradient(135deg, #ef4444, #f97316)",
  "linear-gradient(135deg, #22c55e, #06b6d4)",
  "linear-gradient(135deg, #eab308, #f97316)",
  "linear-gradient(135deg, #ec4899, #8b5cf6, #3b82f6)",
  "linear-gradient(135deg, #f97316, #ef4444, #ec4899)",
  "linear-gradient(135deg, #22c55e, #eab308)",
  "linear-gradient(135deg, #3b82f6, #06b6d4, #22c55e)",
];

const TOOLS = [
  { icon: "↖", label: "Select" },
  { icon: "□", label: "Rectangle" },
  { icon: "■", label: "Filled Rect" },
  { icon: "○", label: "Circle" },
  { icon: "↗", label: "Arrow" },
  { icon: "〰", label: "Freehand" },
  { icon: "✎", label: "Pen" },
  { icon: "①", label: "Number" },
  { icon: "◐", label: "Blur" },
  { icon: "☰", label: "Settings" },
];

function EditorComposition() {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const fadeIn = spring({ frame, fps, config: { damping: 20, stiffness: 80 }, durationInFrames: 25 });
  const sidebarSlide = spring({ frame, fps, config: { damping: 18, stiffness: 100 }, durationInFrames: 30 });
  const imageAppear = spring({ frame: Math.max(0, frame - 15), fps, config: { damping: 15, stiffness: 90 }, durationInFrames: 30 });

  const paddingAnim = interpolate(frame, [50, 80], [0, 8], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  const cornerAnim = interpolate(frame, [65, 95], [0, 18], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  const shadowAnim = interpolate(frame, [80, 110], [0, 36], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });

  const bgPhase = interpolate(frame, [100, 105], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  const activeToolIndex = Math.floor(interpolate(frame, [0, 30, 60, 90, 120, 160], [0, 0, 4, 1, 0, 0], { extrapolateRight: "clamp" }));

  const sliderPadding = interpolate(frame, [50, 80], [0, 40], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const sliderCorner = interpolate(frame, [65, 95], [0, 45], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const sliderShadow = interpolate(frame, [80, 110], [0, 55], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  const selectedGradientIndex = frame >= 100 ? 8 : -1;

  const titleBarOpacity = spring({ frame: Math.max(0, frame - 5), fps, config: { damping: 20, stiffness: 100 }, durationInFrames: 20 });

  return (
    <AbsoluteFill
      style={{
        background: "linear-gradient(145deg, #fce4ec 0%, #e8f5e9 30%, #e3f2fd 60%, #fff3e0 100%)",
        fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      }}
    >
      {/* Window chrome */}
      <div
        style={{
          position: "absolute",
          top: 24,
          left: 24,
          right: 24,
          bottom: 24,
          background: "#ffffff",
          borderRadius: 12,
          boxShadow: "0 25px 60px rgba(0,0,0,0.12), 0 0 0 1px rgba(0,0,0,0.06)",
          overflow: "hidden",
          opacity: fadeIn,
          transform: `scale(${interpolate(fadeIn, [0, 1], [0.96, 1])})`,
        }}
      >
        {/* Title bar */}
        <div
          style={{
            height: 42,
            background: "#fafafa",
            borderBottom: "1px solid rgba(0,0,0,0.06)",
            display: "flex",
            alignItems: "center",
            padding: "0 14px",
            opacity: titleBarOpacity,
          }}
        >
          <div style={{ display: "flex", gap: 7 }}>
            <div style={{ width: 12, height: 12, borderRadius: 6, background: "#ff5f57" }} />
            <div style={{ width: 12, height: 12, borderRadius: 6, background: "#febc2e" }} />
            <div style={{ width: 12, height: 12, borderRadius: 6, background: "#28c840" }} />
          </div>
          <div
            style={{
              flex: 1,
              textAlign: "center",
              fontSize: 12,
              color: "rgba(0,0,0,0.4)",
              fontWeight: 500,
              letterSpacing: "-0.01em",
            }}
          >
            bettershot_screenshot
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            <div style={{ fontSize: 11, color: "rgba(0,0,0,0.3)", padding: "3px 8px", background: "rgba(0,0,0,0.04)", borderRadius: 5 }}>Cancel</div>
            <div style={{ fontSize: 11, color: "#fff", padding: "3px 8px", background: "#3b82f6", borderRadius: 5 }}>Copy</div>
            <div style={{ fontSize: 11, color: "#fff", padding: "3px 8px", background: "#3b82f6", borderRadius: 5 }}>Export</div>
          </div>
        </div>

        <div style={{ display: "flex", height: "calc(100% - 42px)" }}>
          {/* Left sidebar */}
          <div
            style={{
              width: 240,
              borderRight: "1px solid rgba(0,0,0,0.06)",
              background: "#fdfdfd",
              padding: "16px 14px",
              transform: `translateX(${interpolate(sidebarSlide, [0, 1], [-240, 0])}px)`,
              opacity: sidebarSlide,
              overflow: "hidden",
            }}
          >
            {/* Tools */}
            <div style={{ marginBottom: 20 }}>
              <div style={{ fontSize: 10, fontWeight: 600, color: "rgba(0,0,0,0.3)", letterSpacing: "0.05em", textTransform: "uppercase", marginBottom: 10 }}>Tools</div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 4 }}>
                {TOOLS.map((tool, i) => {
                  const isActive = i === activeToolIndex;
                  return (
                    <div
                      key={i}
                      style={{
                        width: 36,
                        height: 36,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        borderRadius: 8,
                        fontSize: 16,
                        background: isActive ? "#3b82f6" : "rgba(0,0,0,0.03)",
                        color: isActive ? "#fff" : "rgba(0,0,0,0.45)",
                        transition: "all 0.2s",
                      }}
                    >
                      {tool.icon}
                    </div>
                  );
                })}
              </div>
              <div style={{ marginTop: 8, fontSize: 13, fontWeight: 500, color: "rgba(0,0,0,0.5)" }}>Aa</div>
            </div>

            {/* Effects */}
            <div style={{ marginBottom: 20 }}>
              <div style={{ fontSize: 10, fontWeight: 600, color: "rgba(0,0,0,0.3)", letterSpacing: "0.05em", textTransform: "uppercase", marginBottom: 10 }}>Effects</div>

              <SliderRow label="Padding" value={`${Math.round(paddingAnim)}%`} progress={sliderPadding} />
              <SliderRow label="Corner Radius" value={Math.round(cornerAnim).toString()} progress={sliderCorner} />
              <SliderRow label="Shadow" value={`${Math.round(shadowAnim)}%`} progress={sliderShadow} />
            </div>

            {/* Layout */}
            <div style={{ marginBottom: 20 }}>
              <div style={{ fontSize: 10, fontWeight: 600, color: "rgba(0,0,0,0.3)", letterSpacing: "0.05em", textTransform: "uppercase", marginBottom: 10 }}>Layout</div>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
                <span style={{ fontSize: 11, color: "rgba(0,0,0,0.4)" }}>Ratio</span>
                <span style={{ fontSize: 11, color: "rgba(0,0,0,0.5)", fontWeight: 500 }}>Auto</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                <span style={{ fontSize: 11, color: "rgba(0,0,0,0.4)" }}>Align</span>
              </div>
              {/* Alignment grid */}
              <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 5, width: 80, margin: "0 auto" }}>
                {Array.from({ length: 9 }).map((_, i) => (
                  <div
                    key={i}
                    style={{
                      width: 8,
                      height: 8,
                      borderRadius: 4,
                      background: i === 4 ? "#3b82f6" : "rgba(0,0,0,0.1)",
                      margin: "0 auto",
                    }}
                  />
                ))}
              </div>
            </div>

            {/* Background */}
            <div>
              <div style={{ fontSize: 10, fontWeight: 600, color: "rgba(0,0,0,0.3)", letterSpacing: "0.05em", textTransform: "uppercase", marginBottom: 10 }}>Background</div>
              <div style={{ fontSize: 10, color: "rgba(0,0,0,0.3)", marginBottom: 6 }}>Solid</div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 4, marginBottom: 10 }}>
                {COLORS_SOLID.map((color, i) => (
                  <div
                    key={i}
                    style={{
                      width: 24,
                      height: 24,
                      borderRadius: 6,
                      background: color === "transparent" ? "linear-gradient(45deg, #eee 25%, transparent 25%, transparent 75%, #eee 75%), linear-gradient(45deg, #eee 25%, transparent 25%, transparent 75%, #eee 75%)" : color,
                      backgroundSize: color === "transparent" ? "8px 8px" : undefined,
                      backgroundPosition: color === "transparent" ? "0 0, 4px 4px" : undefined,
                      border: "1px solid rgba(0,0,0,0.08)",
                    }}
                  />
                ))}
              </div>
              <div style={{ fontSize: 10, color: "rgba(0,0,0,0.3)", marginBottom: 6 }}>Gradients</div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 4 }}>
                {GRADIENTS.map((gradient, i) => (
                  <div
                    key={i}
                    style={{
                      width: 24,
                      height: 24,
                      borderRadius: 6,
                      background: gradient,
                      border: i === selectedGradientIndex ? "2px solid #3b82f6" : "1px solid rgba(0,0,0,0.08)",
                      boxShadow: i === selectedGradientIndex ? "0 0 0 2px rgba(59,130,246,0.3)" : "none",
                    }}
                  />
                ))}
              </div>
            </div>
          </div>

          {/* Canvas */}
          <div
            style={{
              flex: 1,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "#f5f5f4",
              overflow: "hidden",
            }}
          >
            {/* Background + Screenshot */}
            <div
              style={{
                width: "78%",
                aspectRatio: "16/10",
                borderRadius: cornerAnim,
                background: bgPhase > 0
                  ? `linear-gradient(135deg, #ec4899, #8b5cf6, #3b82f6)`
                  : "transparent",
                padding: `${paddingAnim}%`,
                boxShadow: shadowAnim > 0 ? `0 ${shadowAnim}px ${shadowAnim * 2}px rgba(0,0,0,${shadowAnim / 120})` : "none",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                opacity: imageAppear,
                transform: `scale(${interpolate(imageAppear, [0, 1], [0.9, 1])})`,
              }}
            >
              {/* Mock screenshot content */}
              <div
                style={{
                  width: "100%",
                  height: "100%",
                  borderRadius: Math.max(0, cornerAnim - 4),
                  background: "#1a1a2e",
                  overflow: "hidden",
                  boxShadow: "0 4px 20px rgba(0,0,0,0.15)",
                }}
              >
                {/* Mock app title bar */}
                <div
                  style={{
                    height: 28,
                    background: "rgba(255,255,255,0.06)",
                    display: "flex",
                    alignItems: "center",
                    padding: "0 10px",
                    gap: 5,
                  }}
                >
                  <div style={{ width: 8, height: 8, borderRadius: 4, background: "#ff5f57" }} />
                  <div style={{ width: 8, height: 8, borderRadius: 4, background: "#febc2e" }} />
                  <div style={{ width: 8, height: 8, borderRadius: 4, background: "#28c840" }} />
                  <div style={{ flex: 1, textAlign: "center", fontSize: 9, color: "rgba(255,255,255,0.3)" }}>Image Viewer</div>
                </div>

                {/* Mock content area */}
                <div style={{ padding: "12px", height: "calc(100% - 28px)" }}>
                  {/* Simulated desktop/app content */}
                  <div
                    style={{
                      width: "100%",
                      height: "100%",
                      borderRadius: 4,
                      background: "linear-gradient(180deg, #16213e 0%, #0f3460 40%, #533483 70%, #e94560 100%)",
                      display: "flex",
                      flexDirection: "column",
                      alignItems: "center",
                      justifyContent: "center",
                      gap: 8,
                    }}
                  >
                    <div style={{ width: 32, height: 32, borderRadius: 8, background: "rgba(255,255,255,0.15)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 16 }}>⌘</div>
                    <div style={{ fontSize: 11, color: "rgba(255,255,255,0.6)", fontWeight: 600, letterSpacing: "-0.02em" }}>Better Shot</div>
                    <div style={{ fontSize: 8, color: "rgba(255,255,255,0.3)", maxWidth: "60%", textAlign: "center", lineHeight: 1.4 }}>
                      Capture, annotate, and beautify your screenshots
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
}

function SliderRow({
  label,
  value,
  progress,
}: {
  label: string;
  value: string;
  progress: number;
}) {
  return (
    <div style={{ marginBottom: 10 }}>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          marginBottom: 4,
        }}
      >
        <span style={{ fontSize: 11, color: "rgba(0,0,0,0.4)" }}>{label}</span>
        <span style={{ fontSize: 11, color: "rgba(0,0,0,0.5)", fontWeight: 500 }}>{value}</span>
      </div>
      <div
        style={{
          height: 4,
          background: "rgba(0,0,0,0.06)",
          borderRadius: 2,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: "100%",
            width: `${progress}%`,
            background: "#3b82f6",
            borderRadius: 2,
          }}
        />
      </div>
    </div>
  );
}

export function EditorPlayer() {
  return (
    <Player
      component={EditorComposition}
      durationInFrames={180}
      compositionWidth={1200}
      compositionHeight={760}
      fps={30}
      style={{
        width: "100%",
        borderRadius: 8,
      }}
      autoPlay
      loop
      acknowledgeRemotionLicense
    />
  );
}
