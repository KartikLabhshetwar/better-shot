import type React from "react"
import type { Metadata } from "next"
import { GeistSans } from "geist/font/sans"
import { GeistMono } from "geist/font/mono"
import "./globals.css"

export const metadata: Metadata = {
  title: "Better Shot - Free Screenshot Tool for macOS",
  description: "An open-source alternative to CleanShot X for macOS. Capture, edit, and enhance your screenshots with professional quality.",
  metadataBase: new URL("https://bettershot.site"),
  openGraph: {
    title: "Better Shot - Free Screenshot Tool for macOS",
    description: "An open-source alternative to CleanShot X for macOS. Capture, edit, and enhance your screenshots with professional quality.",
    url: "https://bettershot.site",
    siteName: "Better Shot",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Better Shot - Free Screenshot Tool for macOS",
      },
    ],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Better Shot - Free Screenshot Tool for macOS",
    description: "An open-source alternative to CleanShot X for macOS. Capture, edit, and enhance your screenshots with professional quality.",
    images: ["/og.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className="dark">
      <head>
      <meta name="google-site-verification" content="zI8OdLzuEkWozadNrjWCYY6B1MSeQ229HiqRMJNaB60" />
      <script defer src="https://cloud.umami.is/script.js" data-website-id="86300559-2d99-4d80-b25e-1d494de4f16b"></script>
        <style>{`
html {
  font-family: ${GeistSans.style.fontFamily};
  --font-sans: ${GeistSans.variable};
  --font-mono: ${GeistMono.variable};
}
        `}</style>
      </head>
      <body className="dark">{children}</body>
    </html>
  )
}
