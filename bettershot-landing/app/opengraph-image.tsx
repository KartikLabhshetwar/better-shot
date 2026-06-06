import { ImageResponse } from "next/og";

export const alt = "Better Shot — Screenshot tool for macOS";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          background: "linear-gradient(145deg, #fce4ec 0%, #e8f5e9 30%, #e3f2fd 60%, #fff3e0 100%)",
          fontFamily: "system-ui, -apple-system, sans-serif",
          position: "relative",
          overflow: "hidden",
        }}
      >
        {/* Subtle decorative circles */}
        <div
          style={{
            position: "absolute",
            top: -80,
            right: -80,
            width: 300,
            height: 300,
            borderRadius: 150,
            background: "rgba(249, 115, 22, 0.08)",
            display: "flex",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: -60,
            left: -60,
            width: 200,
            height: 200,
            borderRadius: 100,
            background: "rgba(59, 130, 246, 0.06)",
            display: "flex",
          }}
        />

        {/* Content */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            padding: "60px 70px",
            flex: 1,
          }}
        >
          {/* Top: Logo + name */}
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            {/* Logo circles */}
            <div
              style={{
                width: 44,
                height: 44,
                borderRadius: 22,
                background: "linear-gradient(135deg, #f97316, #eab308)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <div
                style={{
                  width: 22,
                  height: 22,
                  borderRadius: 11,
                  background: "white",
                  display: "flex",
                }}
              />
            </div>
            <span
              style={{
                fontSize: 22,
                fontWeight: 500,
                color: "rgba(17, 17, 17, 0.45)",
                letterSpacing: "-0.01em",
              }}
            >
              Better Shot
            </span>
          </div>

          {/* Middle: Headline */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              marginTop: 50,
              gap: 16,
            }}
          >
            <div
              style={{
                fontSize: 64,
                fontWeight: 700,
                color: "#111",
                letterSpacing: "-0.035em",
                lineHeight: 1.1,
              }}
            >
              Screenshots that look
            </div>
            <div
              style={{
                fontSize: 64,
                fontWeight: 700,
                color: "#111",
                letterSpacing: "-0.035em",
                lineHeight: 1.1,
              }}
            >
              like you tried.
            </div>
          </div>

          {/* Bottom: Tagline + badges */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              marginTop: "auto",
            }}
          >
            <div
              style={{
                fontSize: 22,
                color: "rgba(17, 17, 17, 0.35)",
                lineHeight: 1.6,
              }}
            >
              Capture, annotate, beautify. Free & open source for macOS.
            </div>

            <div style={{ display: "flex", gap: 12 }}>
              {/* Feature badges */}
              {["Capture", "Annotate", "Beautify"].map((label) => (
                <div
                  key={label}
                  style={{
                    padding: "8px 18px",
                    borderRadius: 8,
                    background: "rgba(17, 17, 17, 0.04)",
                    border: "1px solid rgba(17, 17, 17, 0.06)",
                    fontSize: 15,
                    fontWeight: 500,
                    color: "rgba(17, 17, 17, 0.4)",
                    display: "flex",
                  }}
                >
                  {label}
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Editor preview strip at bottom */}
        <div
          style={{
            height: 120,
            margin: "0 70px 40px",
            borderRadius: 12,
            background: "white",
            boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 0 0 1px rgba(0,0,0,0.04)",
            display: "flex",
            overflow: "hidden",
          }}
        >
          {/* Sidebar hint */}
          <div
            style={{
              width: 160,
              borderRight: "1px solid rgba(0,0,0,0.06)",
              padding: "14px",
              display: "flex",
              flexDirection: "column",
              gap: 6,
            }}
          >
            <div
              style={{
                fontSize: 9,
                fontWeight: 600,
                color: "rgba(0,0,0,0.25)",
                letterSpacing: "0.06em",
                textTransform: "uppercase" as const,
                display: "flex",
              }}
            >
              TOOLS
            </div>
            <div style={{ display: "flex", gap: 4 }}>
              {Array.from({ length: 5 }).map((_, i) => (
                <div
                  key={i}
                  style={{
                    width: 22,
                    height: 22,
                    borderRadius: 5,
                    background: i === 0 ? "#3b82f6" : "rgba(0,0,0,0.04)",
                    display: "flex",
                  }}
                />
              ))}
            </div>
            <div style={{ display: "flex", gap: 4 }}>
              {Array.from({ length: 5 }).map((_, i) => (
                <div
                  key={i}
                  style={{
                    width: 22,
                    height: 22,
                    borderRadius: 5,
                    background: "rgba(0,0,0,0.04)",
                    display: "flex",
                  }}
                />
              ))}
            </div>
          </div>

          {/* Canvas hint */}
          <div
            style={{
              flex: 1,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "#f5f5f4",
            }}
          >
            <div
              style={{
                width: "70%",
                height: "80%",
                borderRadius: 10,
                background: "linear-gradient(135deg, #ec4899, #8b5cf6, #3b82f6)",
                padding: 8,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <div
                style={{
                  width: "100%",
                  height: "100%",
                  borderRadius: 6,
                  background: "#1a1a2e",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <div
                  style={{
                    fontSize: 11,
                    color: "rgba(255,255,255,0.4)",
                    display: "flex",
                  }}
                >
                  Better Shot
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    ),
    { ...size }
  );
}
