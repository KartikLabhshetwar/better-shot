"use client"

import { trackDownload } from "@/lib/analytics"
import { cn } from "@/lib/utils"

interface DownloadLinkProps {
  href: string
  label: string
  primary?: boolean
  source?: "navbar" | "hero" | "cta" | "mobile-menu"
}

export function DownloadLink({ href, label, primary, source = "hero" }: DownloadLinkProps) {
  return (
    <a
      href={href}
      onClick={() => trackDownload(source)}
      className={cn(
        "inline-flex items-center justify-center px-5 py-3 text-[15px] font-semibold tracking-tight outline-none transition-colors duration-150",
        primary
          ? "bg-brand text-canvas hover:bg-brand-600 active:bg-brand-700"
          : "border-2 border-rule text-ink hover:border-ink",
      )}
    >
      {label}
    </a>
  )
}
