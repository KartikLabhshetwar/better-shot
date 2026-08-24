import type React from "react"
import type { Metadata } from "next"
import { GeistSans } from "geist/font/sans"
import { GeistMono } from "geist/font/mono"
import "./globals.css"

const title = "Better Shot: free screenshot and screen recorder for macOS"
const description =
  "Free, open-source screenshot and screen recording app for macOS. Cursor auto-zoom, face cam, annotations, backgrounds, and share links on your own storage. No account, no subscription, no uploads."

export const metadata: Metadata = {
  title,
  description,
  metadataBase: new URL("https://bettershot.site"),
  alternates: {
    canonical: "/",
  },
  keywords: [
    "screenshot tool mac",
    "screen recorder mac",
    "free screen recorder for macOS",
    "cleanshot x alternative",
    "loom alternative",
    "capcut alternative",
    "open source screenshot tool",
    "screen recording with cursor zoom",
    "screen recorder no watermark",
    "screenshot annotation tool",
    "screenshot background editor",
    "local first screen capture",
    "mac screen capture app",
    "MP4 screen recording mac",
    "free CleanShot alternative",
  ],
  openGraph: {
    title,
    description,
    url: "https://bettershot.site",
    siteName: "Better Shot",
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    creator: "@code_kartik",
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

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Better Shot",
  alternateName: "BetterShot",
  applicationCategory: "MultimediaApplication",
  applicationSubCategory: "Screen capture and screen recording",
  operatingSystem: "macOS 14.0 or later",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
  },
  description,
  url: "https://bettershot.site",
  downloadUrl: "https://github.com/KartikLabhshetwar/better-shot/releases",
  softwareHelp: "https://bettershot.site/changelog",
  license: "https://github.com/KartikLabhshetwar/better-shot/blob/main/LICENSE",
  isAccessibleForFree: true,
  featureList: [
    "Region, window, and fullscreen screenshots",
    "Screen recording with cursor auto-zoom",
    "Face cam bubble and microphone capture",
    "Multi-clip timeline with per-clip speed",
    "Annotations, blur, and spotlight",
    "Backgrounds, padding, shadow, and rounded corners",
    "Share links uploaded to your own Cloudflare R2 bucket",
    "OCR text extraction and color picker",
  ],
  sameAs: [
    "https://github.com/KartikLabhshetwar/better-shot",
    "https://x.com/code_kartik",
  ],
  author: {
    "@type": "Person",
    name: "Kartik Labhshetwar",
    url: "https://x.com/code_kartik",
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <head>
        <meta
          name="google-site-verification"
          content="zI8OdLzuEkWozadNrjWCYY6B1MSeQ229HiqRMJNaB60"
        />
        <script
          defer
          src="https://cloud.umami.is/script.js"
          data-website-id="86300559-2d99-4d80-b25e-1d494de4f16b"
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  )
}
