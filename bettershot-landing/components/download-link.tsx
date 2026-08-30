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
          ? "rounded-xl bg-brand text-white hover:bg-brand-600 active:bg-brand-700"
          : "rounded-xl border border-zinc-200 text-zinc-900 hover:border-zinc-400",
      )}
    >
      {label}
    </a>
  )
}
