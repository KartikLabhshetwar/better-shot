import { ImageResponse } from "next/og";

export const alt = "Better Shot: screenshots and screen recording for macOS";
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
          background: "#fafaf9",
          fontFamily: "system-ui, -apple-system, sans-serif",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            padding: "60px 70px",
            flex: 1,
          }}
        >
          {/* Logo + name */}
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 10,
                background: "linear-gradient(135deg, #f97316, #eab308)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <div
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: 10,
                  background: "white",
                  display: "flex",
                }}
              />
            </div>
            <span
              style={{
                fontSize: 22,
                fontWeight: 600,
                color: "rgba(17, 17, 17, 0.5)",
                letterSpacing: "-0.01em",
              }}
            >
              Better Shot
            </span>
          </div>

          {/* Headline */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              marginTop: 48,
              gap: 4,
            }}
          >
            <div
              style={{
                fontSize: 62,
                fontWeight: 700,
                color: "#111",
                letterSpacing: "-0.035em",
                lineHeight: 1.1,
                display: "flex",
              }}
            >
              Capture your screen,
            </div>
            <div
              style={{
                fontSize: 62,
                fontWeight: 700,
                color: "rgba(17, 17, 17, 0.25)",
                letterSpacing: "-0.035em",
                lineHeight: 1.1,
                display: "flex",
              }}
            >
              make it beautiful.
            </div>
          </div>

          {/* Tagline */}
          <div
            style={{
              fontSize: 22,
              color: "rgba(17, 17, 17, 0.35)",
              lineHeight: 1.6,
              marginTop: 32,
              display: "flex",
            }}
          >
            Screenshots, recordings, annotations, and effects. Free & open source for macOS.
          </div>

          {/* Bottom bar */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              marginTop: "auto",
            }}
          >
            {/* Feature pills */}
            <div style={{ display: "flex", gap: 10 }}>
              {["Screenshots", "Recording", "Annotations", "Effects"].map((label) => (
                <div
                  key={label}
                  style={{
                    padding: "8px 18px",
                    borderRadius: 6,
                    background: "rgba(17, 17, 17, 0.04)",
                    border: "1px solid rgba(17, 17, 17, 0.06)",
                    fontSize: 14,
                    fontWeight: 500,
                    color: "rgba(17, 17, 17, 0.4)",
                    display: "flex",
                  }}
                >
                  {label}
                </div>
              ))}
            </div>

            {/* Platform badges */}
            <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
              <span style={{ fontSize: 13, color: "rgba(17, 17, 17, 0.2)", display: "flex" }}>
                macOS 14+
              </span>
              <span style={{ width: 1, height: 14, background: "rgba(17, 17, 17, 0.08)", display: "flex" }} />
              <span style={{ fontSize: 13, color: "rgba(17, 17, 17, 0.2)", display: "flex" }}>
                Apple Silicon & Intel
              </span>
              <span style={{ width: 1, height: 14, background: "rgba(17, 17, 17, 0.08)", display: "flex" }} />
              <span style={{ fontSize: 13, color: "rgba(17, 17, 17, 0.2)", display: "flex" }}>
                Homebrew
              </span>
            </div>
          </div>
        </div>
      </div>
    ),
    { ...size }
  );
}
