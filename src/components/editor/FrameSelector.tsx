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
      // Full MacBook: compact base + centred screen over selected backdrop
      <svg width="38" height="28" viewBox="0 0 38 28" fill="none">
        <defs>
          <linearGradient id="macbook-lid" x1="19" y1="0.5" x2="19" y2="19" gradientUnits="userSpaceOnUse">
            <stop stopColor="#373c42" />
            <stop offset="1" stopColor="#1a1d21" />
          </linearGradient>
          <linearGradient id="macbook-base" x1="19" y1="18" x2="19" y2="27" gradientUnits="userSpaceOnUse">
            <stop stopColor="#bbc2cc" />
            <stop offset="1" stopColor="#737b87" />
          </linearGradient>
        </defs>
        {/* Base — slimmer than previous */}
        <rect x="1" y="19" width="36" height="6.5" rx="1.6" fill="url(#macbook-base)" />
        <rect x="4" y="20.4" width="30" height="1.5" rx="0.75" fill="rgba(30,32,36,0.25)" />
        <rect x="14" y="22" width="10" height="1.8" rx="0.9" stroke="rgba(74,80,88,0.55)" strokeWidth="0.6" />
        <rect x="16.5" y="24.5" width="5" height="0.9" rx="0.45" fill="rgba(58,64,72,0.72)" />
        {/* Rubber feet */}
        <rect x="4" y="26.2" width="4" height="1" rx="0.5" fill="#111" />
        <rect x="30" y="26.2" width="4" height="1" rx="0.5" fill="#111" />
        {/* Lid shell — centred, narrower than base */}
        <rect x="3" y="0.5" width="32" height="18.8" rx="2.6" fill="url(#macbook-lid)" />
        <rect x="4.5" y="2.2" width="29" height="15.3" rx="1.6" fill="#121417" />
        {/* Screen backdrop */}
        <rect x="5.8" y="3.4" width="26.4" height="12.8" rx="1.2" fill="#2d63d8" />
        <path d="M5.8 13.2C11 10.5 15.5 9.6 32.2 6.8V16.2H5.8V13.2Z" fill="#2a1247" />
        <rect x="11.2" y="8.5" width="15.6" height="3.2" rx="0.9" fill="#242437" />
        {/* Camera dot */}
        <rect x="17.3" y="1.8" width="3.4" height="0.9" rx="0.45" fill="rgba(0,0,0,0.2)" />
        <circle cx="19" cy="2.35" r="0.7" fill="#101215" />
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
