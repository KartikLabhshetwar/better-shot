import { ImageResponse } from "next/og"
import fs from "fs"
import path from "path"

export const ogAlt = "Better Shot: free, open source screen recorder for Mac"
export const ogSize = { width: 1200, height: 630 }
export const ogContentType = "image/png"

export function renderOgImage() {
  const logoPath = path.join(process.cwd(), "public", "logo.png")
  const logoData = fs.readFileSync(logoPath)
  const logoSrc = `data:image/png;base64,${logoData.toString("base64")}`

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          background: "#ffffff",
          fontFamily: "system-ui, -apple-system, sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <img
            src={logoSrc}
            width={56}
            height={56}
            style={{ borderRadius: 16 }}
          />
          <span
            style={{
              fontSize: 32,
              fontWeight: 600,
              color: "#18181b",
              letterSpacing: "-0.4px",
              display: "flex",
            }}
          >
            Better Shot
          </span>
        </div>

        <div
          style={{
            fontSize: 64,
            fontWeight: 500,
            color: "#18181b",
            letterSpacing: "-1.2px",
            lineHeight: 1.1,
            marginTop: 40,
            display: "flex",
          }}
        >
          Screen recorder for Mac.
        </div>
        <div
          style={{
            fontSize: 64,
            fontWeight: 500,
            color: "#a1a1aa",
            letterSpacing: "-1.2px",
            lineHeight: 1.1,
            marginTop: 8,
            display: "flex",
          }}
        >
          Free and open source.
        </div>

        <div
          style={{
            position: "absolute",
            bottom: 0,
            left: 0,
            right: 0,
            height: 6,
            background: "#7c3aed",
            display: "flex",
          }}
        />
      </div>
    ),
    { ...ogSize },
  )
}
