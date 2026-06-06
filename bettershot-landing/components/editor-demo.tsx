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

const ACTIVE_TOOL = 0;
const SELECTED_GRADIENT = 8;

function SliderRow({ label, value, progress }: { label: string; value: string; progress: number }) {
  return (
    <div className="mb-2.5">
      <div className="flex justify-between mb-1">
        <span className="text-[11px] text-black/40">{label}</span>
        <span className="text-[11px] text-black/50 font-medium">{value}</span>
      </div>
      <div className="h-1 bg-black/[0.06] rounded-sm overflow-hidden">
        <div
          className="h-full bg-blue-500 rounded-sm"
          style={{ width: `${progress}%` }}
        />
      </div>
    </div>
  );
}

export function EditorPreview() {
  return (
    <div
      className="relative w-full font-[-apple-system,BlinkMacSystemFont,'Segoe_UI',sans-serif]"
      style={{
        aspectRatio: "1200/760",
        background: "linear-gradient(145deg, #fce4ec 0%, #e8f5e9 30%, #e3f2fd 60%, #fff3e0 100%)",
      }}
    >
      {/* Window chrome */}
      <div className="absolute inset-4 sm:inset-5 bg-white rounded-xl shadow-[0_25px_60px_rgba(0,0,0,0.12),0_0_0_1px_rgba(0,0,0,0.06)] overflow-hidden flex flex-col">
        {/* Title bar */}
        <div className="h-[42px] shrink-0 bg-[#fafafa] border-b border-black/[0.06] flex items-center px-3.5">
          <div className="flex gap-[7px]">
            <div className="w-3 h-3 rounded-full bg-[#ff5f57]" />
            <div className="w-3 h-3 rounded-full bg-[#febc2e]" />
            <div className="w-3 h-3 rounded-full bg-[#28c840]" />
          </div>
          <div className="flex-1 text-center text-xs text-black/40 font-medium tracking-tight">
            bettershot_screenshot
          </div>
          <div className="flex gap-2">
            <div className="text-[11px] text-black/30 px-2 py-0.5 bg-black/[0.04] rounded-[5px]">Cancel</div>
            <div className="text-[11px] text-white px-2 py-0.5 bg-blue-500 rounded-[5px]">Copy</div>
            <div className="text-[11px] text-white px-2 py-0.5 bg-blue-500 rounded-[5px]">Export</div>
          </div>
        </div>

        <div className="flex flex-1 min-h-0">
          {/* Left sidebar */}
          <div className="w-[240px] shrink-0 border-r border-black/[0.06] bg-[#fdfdfd] p-3.5 overflow-y-auto hidden md:block">
            {/* Tools */}
            <div className="mb-5">
              <div className="text-[10px] font-semibold text-black/30 tracking-widest uppercase mb-2.5">Tools</div>
              <div className="grid grid-cols-5 gap-1">
                {TOOLS.map((tool, i) => (
                  <div
                    key={i}
                    className={`w-9 h-9 flex items-center justify-center rounded-lg text-base ${
                      i === ACTIVE_TOOL
                        ? "bg-blue-500 text-white"
                        : "bg-black/[0.03] text-black/45"
                    }`}
                  >
                    {tool.icon}
                  </div>
                ))}
              </div>
              <div className="mt-2 text-[13px] font-medium text-black/50">Aa</div>
            </div>

            {/* Effects */}
            <div className="mb-5">
              <div className="text-[10px] font-semibold text-black/30 tracking-widest uppercase mb-2.5">Effects</div>
              <SliderRow label="Padding" value="8%" progress={40} />
              <SliderRow label="Corner Radius" value="18" progress={45} />
              <SliderRow label="Shadow" value="36%" progress={55} />
            </div>

            {/* Layout */}
            <div className="mb-5">
              <div className="text-[10px] font-semibold text-black/30 tracking-widest uppercase mb-2.5">Layout</div>
              <div className="flex justify-between items-center mb-1.5">
                <span className="text-[11px] text-black/40">Ratio</span>
                <span className="text-[11px] text-black/50 font-medium">Auto</span>
              </div>
              <div className="flex justify-between items-center mb-2">
                <span className="text-[11px] text-black/40">Align</span>
              </div>
              <div className="grid grid-cols-3 gap-[5px] w-20 mx-auto">
                {Array.from({ length: 9 }).map((_, i) => (
                  <div
                    key={i}
                    className={`w-2 h-2 rounded-full mx-auto ${
                      i === 4 ? "bg-blue-500" : "bg-black/10"
                    }`}
                  />
                ))}
              </div>
            </div>

            {/* Background */}
            <div>
              <div className="text-[10px] font-semibold text-black/30 tracking-widest uppercase mb-2.5">Background</div>
              <div className="text-[10px] text-black/30 mb-1.5">Solid</div>
              <div className="grid grid-cols-6 gap-1 mb-2.5">
                {COLORS_SOLID.map((color, i) => (
                  <div
                    key={i}
                    className="w-6 h-6 rounded-md border border-black/[0.08]"
                    style={{
                      background:
                        color === "transparent"
                          ? "linear-gradient(45deg, #eee 25%, transparent 25%, transparent 75%, #eee 75%), linear-gradient(45deg, #eee 25%, transparent 25%, transparent 75%, #eee 75%)"
                          : color,
                      backgroundSize: color === "transparent" ? "8px 8px" : undefined,
                      backgroundPosition: color === "transparent" ? "0 0, 4px 4px" : undefined,
                    }}
                  />
                ))}
              </div>
              <div className="text-[10px] text-black/30 mb-1.5">Gradients</div>
              <div className="grid grid-cols-6 gap-1">
                {GRADIENTS.map((gradient, i) => (
                  <div
                    key={i}
                    className="w-6 h-6 rounded-md"
                    style={{
                      background: gradient,
                      border:
                        i === SELECTED_GRADIENT
                          ? "2px solid #3b82f6"
                          : "1px solid rgba(0,0,0,0.08)",
                      boxShadow:
                        i === SELECTED_GRADIENT
                          ? "0 0 0 2px rgba(59,130,246,0.3)"
                          : "none",
                    }}
                  />
                ))}
              </div>
            </div>
          </div>

          {/* Canvas */}
          <div className="flex-1 flex items-center justify-center bg-[#f5f5f4] overflow-hidden p-4 sm:p-6">
            {/* Background + Screenshot */}
            <div
              className="w-[78%] rounded-[18px] flex items-center justify-center"
              style={{
                aspectRatio: "16/10",
                background: "linear-gradient(135deg, #ec4899, #8b5cf6, #3b82f6)",
                padding: "8%",
                boxShadow: "0 36px 72px rgba(0,0,0,0.3)",
              }}
            >
              {/* Mock screenshot content */}
              <div className="w-full h-full rounded-[14px] bg-[#1a1a2e] overflow-hidden shadow-[0_4px_20px_rgba(0,0,0,0.15)]">
                {/* Mock app title bar */}
                <div className="h-7 bg-white/[0.06] flex items-center px-2.5 gap-[5px]">
                  <div className="w-2 h-2 rounded-full bg-[#ff5f57]" />
                  <div className="w-2 h-2 rounded-full bg-[#febc2e]" />
                  <div className="w-2 h-2 rounded-full bg-[#28c840]" />
                  <div className="flex-1 text-center text-[9px] text-white/30">Image Viewer</div>
                </div>

                {/* Mock content area */}
                <div className="p-3 h-[calc(100%-28px)]">
                  <div className="w-full h-full rounded bg-gradient-to-b from-[#16213e] via-[#0f3460] via-[70%] to-[#e94560] flex flex-col items-center justify-center gap-2">
                    <div className="w-8 h-8 rounded-lg bg-white/15 flex items-center justify-center text-base">
                      ⌘
                    </div>
                    <div className="text-[11px] text-white/60 font-semibold tracking-tight">
                      Better Shot
                    </div>
                    <div className="text-[8px] text-white/30 max-w-[60%] text-center leading-snug">
                      Capture, annotate, and beautify your screenshots
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
