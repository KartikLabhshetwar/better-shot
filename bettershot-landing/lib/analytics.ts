export type DownloadSource = "navbar" | "hero" | "cta" | "mobile-menu"

export function trackDownload(source: DownloadSource) {
  if (typeof window !== "undefined" && window.umami) {
    window.umami.track("download", {
      source,
    })
  }
}

declare global {
  interface Window {
    umami?: {
      track: (
        eventName: string,
        eventData?: Record<string, string | number | boolean>
      ) => void
    }
  }
}
