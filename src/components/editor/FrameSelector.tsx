import { memo } from "react";
import { cn } from "@/lib/utils";
import type { FrameType } from "@/lib/frame-utils";

interface FrameOption {
  type: FrameType;
  label: string;
  preview: React.ReactNode;
}

const FRAME_OPTIONS: FrameOption[] = [
  {
    type: "none",
    label: "None",
    preview: (
      <svg width="32" height="24" viewBox="0 0 32 24" fill="none">
        <rect x="2" y="2" width="28" height="20" rx="3" fill="#2a2a2a" stroke="#444" strokeWidth="1.5" />
        <rect x="6" y="6" width="20" height="12" rx="1" fill="#3a3a3a" />
      </svg>
    ),
  },
  {
    type: "terminal",
    label: "Terminal",
    preview: (
      <svg width="32" height="24" viewBox="0 0 32 24" fill="none">
        <rect x="1" y="1" width="30" height="22" rx="4" fill="#1e1e1e" />
        <rect x="1" y="1" width="30" height="9" rx="4" fill="#2d2d2d" />
        <rect x="1" y="6" width="30" height="4" fill="#2d2d2d" />
        <circle cx="7" cy="5.5" r="2.2" fill="#ff5f57" />
        <circle cx="13" cy="5.5" r="2.2" fill="#febc2e" />
        <circle cx="19" cy="5.5" r="2.2" fill="#28c840" />
        <rect x="5" y="13" width="10" height="1.5" rx="0.75" fill="#444" />
        <rect x="5" y="16.5" width="16" height="1.5" rx="0.75" fill="#3a3a3a" />
      </svg>
    ),
  },
  {
    type: "iphone",
    label: "iPhone",
    preview: (
      // Outer bezel (dark, 40px-radius equivalent), thin p-[6px] bezel, black screen inside
      <svg width="18" height="32" viewBox="0 0 18 32" fill="none">
        {/* Outer frame */}
        <rect x="0.5" y="0.5" width="17" height="31" rx="5.5" fill="#1a1a1a" />
        {/* Inner screen */}
        <rect x="2" y="2" width="14" height="28" rx="4.5" fill="#000" />
        {/* Dynamic Island pill */}
        <rect x="5.5" y="4" width="7" height="2.8" rx="1.4" fill="#1a1a1a" />
        {/* Home indicator */}
        <rect x="6" y="27.5" width="6" height="1.5" rx="0.75" fill="rgba(255,255,255,0.3)" />
        {/* Volume buttons left */}
        <rect x="-1" y="9" width="1.5" height="4" rx="0.75" fill="#1a1a1a" />
        <rect x="-1" y="15" width="1.5" height="4" rx="0.75" fill="#1a1a1a" />
        {/* Power button right */}
        <rect x="17.5" y="12" width="1.5" height="5" rx="0.75" fill="#1a1a1a" />
      </svg>
    ),
  },
  {
    type: "macbook",
    label: "MacBook",
    preview: (
      // Display-only: thin dark bezel, screen, camera notch, small chin at bottom
      <svg width="36" height="24" viewBox="0 0 36 24" fill="none">
        {/* Lid shell */}
        <rect x="0.5" y="0.5" width="35" height="20" rx="2.5" fill="#1e1e1e" />
        {/* Screen */}
        <rect x="2" y="4" width="32" height="14" fill="#000" />
        {/* Camera notch pill */}
        <rect x="15" y="1.5" width="6" height="2" rx="1" fill="#3a3a3a" />
        {/* Bottom chin */}
        <rect x="0.5" y="20.5" width="35" height="3" rx="1" fill="#2a2a2a" />
      </svg>
    ),
  },
];

interface FrameSelectorProps {
  frameType: FrameType;
  onFrameTypeChange: (type: FrameType) => void;
}

export const FrameSelector = memo(function FrameSelector({
  frameType,
  onFrameTypeChange,
}: FrameSelectorProps) {
  return (
    <div>
      <div className="section-header" style={{ paddingTop: 0 }}>
        <span className="section-title">Frame</span>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 6 }}>
        {FRAME_OPTIONS.map(({ type, label, preview }) => {
          const isActive = frameType === type;
          return (
            <button
              key={type}
              onClick={() => onFrameTypeChange(type)}
              aria-label={`${label} frame`}
              title={label}
              className={cn(
                "gradient-thumb",
                isActive && "selected"
              )}
              style={{
                position: "relative",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                gap: 4,
                padding: "6px 4px",
                height: "auto",
                minHeight: 52,
              }}
            >
              {preview}
              <span style={{ fontSize: 9, color: isActive ? "oklch(0.82 0.01 250)" : "oklch(0.50 0.009 250)", letterSpacing: "0.02em" }}>
                {label}
              </span>
              {isActive && (
                <div style={{
                  position: "absolute",
                  inset: 0,
                  background: "oklch(0.65 0.18 255 / 0.20)",
                  borderRadius: "inherit",
                  display: "flex",
                  alignItems: "flex-start",
                  justifyContent: "flex-end",
                  padding: 3,
                }}>
                  <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
});
