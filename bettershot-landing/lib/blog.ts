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
