import { ImageResponse } from "next/og"

export const ogAlt =
  "Better Shot: screenshots, screen recording, captions, and a video editor for macOS"
export const ogSize = { width: 1200, height: 630 }
export const ogContentType = "image/png"

const stats = [
  { value: "$0", label: "forever, no tiers" },
  { value: "0 KB", label: "uploaded by default" },
  { value: "BSD 3", label: "clause, auditable" },
  { value: "macOS 14+", label: "Silicon and Intel" },
]

const ink = "#111111"
const muted = "rgba(17, 17, 17, 0.38)"

export function renderOgImage() {
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
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", padding: "56px 70px", flex: 1 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <div
              style={{
                width: 38,
                height: 38,
                borderRadius: 12,
                background: "#e78a53",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <div
                style={{
                  width: 17,
                  height: 17,
                  borderRadius: 9,
                  background: "#fafaf9",
                  display: "flex",
                }}
              />
            </div>
            <span
              style={{
                fontSize: 21,
                fontWeight: 600,
                color: "rgba(17, 17, 17, 0.5)",
                letterSpacing: "-0.2px",
              }}
            >
              Better Shot
            </span>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              flex: 1,
              justifyContent: "center",
            }}
          >
            <div
              style={{
                fontSize: 86,
                fontWeight: 700,
                color: ink,
                letterSpacing: "-1.6px",
                lineHeight: 1,
                display: "flex",
              }}
            >
              Beautiful screen capture,
            </div>
            <div
              style={{
                fontSize: 86,
                fontWeight: 700,
                color: "rgba(17, 17, 17, 0.28)",
                letterSpacing: "-1.6px",
                lineHeight: 1,
                display: "flex",
                marginTop: 6,
              }}
            >
              without the subscription.
            </div>

            <div
              style={{
                fontSize: 23,
                color: muted,
                lineHeight: 1.45,
                marginTop: 30,
                maxWidth: 860,
                display: "flex",
              }}
            >
              Cursor tracked recording, on device captions, a keystroke overlay, redaction masks,
              and a timeline editor.
            </div>
          </div>

          <div style={{ display: "flex", gap: 64, alignItems: "flex-end" }}>
            {stats.map((stat) => (
              <div key={stat.value} style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                <span
                  style={{
                    fontSize: 38,
                    fontWeight: 700,
                    color: ink,
                    letterSpacing: "-0.8px",
                    lineHeight: 1,
                    display: "flex",
                  }}
                >
                  {stat.value}
                </span>
                <span
                  style={{
                    fontSize: 15,
                    color: "rgba(17, 17, 17, 0.3)",
                    letterSpacing: "0.2px",
                    display: "flex",
                  }}
                >
                  {stat.label}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div style={{ display: "flex", height: 8, background: "#e78a53" }} />
      </div>
    ),
    { ...ogSize },
  )
}
