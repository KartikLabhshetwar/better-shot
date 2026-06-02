import type React from "react"
import type { Metadata } from "next"
import { GeistSans } from "geist/font/sans"
import { GeistMono } from "geist/font/mono"
import "./globals.css"

export const metadata: Metadata = {
  title: "Better Shot — Screenshot tool for macOS",
  description:
    "Free, open-source screenshot tool for macOS. Capture, annotate, and beautify screenshots with a single shortcut. No account needed.",
  metadataBase: new URL("https://bettershot.site"),
  alternates: {
    canonical: "/",
  },
  keywords: [
    "screenshot",
    "macOS",
    "screen capture",
    "open source",
    "CleanShot alternative",
    "annotation",
    "free screenshot tool",
  ],
  openGraph: {
    title: "Better Shot — Screenshot tool for macOS",
    description:
      "Free, open-source screenshot tool for macOS. Capture, annotate, and beautify screenshots with a single shortcut.",
    url: "https://bettershot.site",
    siteName: "Better Shot",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Better Shot — Screenshot tool for macOS",
      },
    ],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Better Shot — Screenshot tool for macOS",
    description:
      "Free, open-source screenshot tool for macOS. Capture, annotate, and beautify screenshots with a single shortcut.",
    images: ["/og.png"],
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
  applicationCategory: "UtilitiesApplication",
  operatingSystem: "macOS",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
  },
  description:
    "Free, open-source screenshot tool for macOS. Capture, annotate, and beautify screenshots.",
  url: "https://bettershot.site",
  downloadUrl: "https://github.com/KartikLabhshetwar/better-shot/releases",
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
