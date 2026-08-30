export interface Post {
  slug: string
  title: string
  headline: string
  description: string
  date: string
  readingTime: string
  tag: string
  keywords: string[]
}

export const posts: Post[] = [
  {
    slug: "loom-alternative",
    title: "The best free Loom alternative for Mac in 2026",
    headline: "Why Better Shot is the best free Loom alternative for Mac",
    description:
      "A detailed comparison of Better Shot vs Loom for screen recording on macOS. Cursor auto-zoom, face cam, on-device captions, share links you own, and no subscription. Free and open source.",
    date: "2026-08-30",
    readingTime: "7 min read",
    tag: "Loom Alternative",
    keywords: [
      "loom alternative",
      "free loom alternative",
      "loom alternative mac",
      "loom alternative for mac",
      "loom alternative open source",
      "screen recorder mac free",
      "screen recording with zoom",
      "async video mac",
      "loom replacement",
      "loom free alternative 2026",
      "screen recorder no subscription",
      "screen recorder no watermark mac",
    ],
  },
  {
    slug: "cleanshot-x-alternative",
    title: "Better Shot vs CleanShot X: the free screenshot tool for Mac",
    headline: "Better Shot vs CleanShot X: why switch to free",
    description:
      "Feature-by-feature comparison of Better Shot and CleanShot X for macOS screenshots. Annotations, beautify, OCR, pinning, and more. Free and open source vs $29 plus Cloud subscription.",
    date: "2026-08-29",
    readingTime: "6 min read",
    tag: "CleanShot Alternative",
    keywords: [
      "cleanshot x alternative",
      "free cleanshot x alternative",
      "cleanshot alternative mac",
      "screenshot tool mac free",
      "mac screenshot app free",
      "screenshot annotation tool mac",
      "cleanshot x vs better shot",
      "free screenshot tool macOS",
      "open source screenshot mac",
      "screenshot beautify mac",
      "cleanshot replacement",
      "cleanshot x free alternative 2026",
    ],
  },
  {
    slug: "cleanshot-x-capcut-loom-alternative",
    title: "The free CleanShot X, CapCut, and Loom alternative for macOS",
    headline: "One free macOS app instead of CleanShot X, CapCut, and Loom",
    description:
      "A practical comparison of Better Shot against CleanShot X, Loom, and CapCut in 2026: screenshots, screen recording with cursor auto-zoom, video trimming, share links, pricing, and privacy. Free and open source for macOS.",
    date: "2026-08-24",
    readingTime: "9 min read",
    tag: "Comparison",
    keywords: [
      "cleanshot x alternative",
      "free cleanshot x alternative",
      "loom alternative",
      "loom alternative for mac",
      "capcut alternative",
      "capcut alternative for screen recording",
      "open source screenshot tool mac",
      "free screen recorder for macOS",
      "screen recording software mac",
      "screenshot tool with annotation",
      "screen recorder no watermark",
      "local first screen recorder",
      "mac screenshot app free",
      "screen recorder with zoom",
      "loom vs cleanshot x vs capcut",
      "best mac screen capture app 2026",
    ],
  },
]

export function getPost(slug: string): Post | undefined {
  return posts.find((post) => post.slug === slug)
}

export function formatPostDate(date: string): string {
  return new Date(`${date}T00:00:00Z`).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  })
}
