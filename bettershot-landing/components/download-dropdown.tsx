"use client"

import { AppleLogoIcon, CaretDownIcon, DownloadSimpleIcon, TerminalWindowIcon } from "@phosphor-icons/react/dist/ssr"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { trackDownload } from "@/lib/analytics"
import type { ReleaseInfo } from "@/lib/downloads"
import { cn } from "@/lib/utils"

const sizeClass = {
  sm: "px-3.5 py-2 text-[14px] gap-2",
  default: "px-4 py-2.5 text-[15px] gap-2",
  lg: "px-6 py-3.5 text-[15px] gap-2.5",
} as const

interface DownloadDropdownProps {
  release: ReleaseInfo
  source: "navbar" | "hero" | "cta" | "mobile-menu"
  variant?: "default" | "outline"
  size?: "default" | "sm" | "lg"
  className?: string
  label?: string
}

export function DownloadDropdown({
  release,
  source,
  variant = "default",
  size = "lg",
  className,
  label,
}: DownloadDropdownProps) {
  const open = (url: string) => {
    trackDownload(source)
    window.open(url, "_blank", "noopener,noreferrer")
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          "inline-flex items-center justify-center rounded-xl font-semibold tracking-tight outline-none",
          "transition-colors duration-150",
          sizeClass[size],
          variant === "outline"
            ? "border border-zinc-200 text-zinc-600 hover:border-zinc-400"
            : "bg-brand text-white hover:bg-brand-600 active:bg-brand-700",
          className,
        )}
      >
        <DownloadSimpleIcon size={16} weight="bold" />
        {label ?? "Download for macOS"}
        <CaretDownIcon size={12} weight="bold" className="opacity-50" />
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="end"
        sideOffset={8}
        className="w-64 rounded-xl border border-zinc-200 bg-white p-0 shadow-lg"
      >
        <DropdownMenuItem
          onClick={() => open(release.appleSilicon)}
          className="cursor-pointer gap-3 border-b border-zinc-100 px-3 py-2.5 last:border-b-0"
        >
          <AppleLogoIcon size={16} weight="fill" />
          <span className="flex flex-col">
            <span className="text-sm font-semibold text-zinc-900">Apple Silicon</span>
            <span className="text-xs text-zinc-500">M1, M2, M3, M4</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => open(release.intel)}
          className="cursor-pointer gap-3 border-b border-zinc-100 px-3 py-2.5 last:border-b-0"
        >
          <DownloadSimpleIcon size={16} weight="bold" />
          <span className="flex flex-col">
            <span className="text-sm font-semibold text-zinc-900">Intel</span>
            <span className="text-xs text-zinc-500">x86_64</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => open("https://formulae.brew.sh/cask/bettershot")}
          className="cursor-pointer gap-3 border-b border-zinc-100 px-3 py-2.5 last:border-b-0"
        >
          <TerminalWindowIcon size={16} weight="bold" />
          <span className="flex flex-col">
            <span className="text-sm font-semibold text-zinc-900">Homebrew</span>
            <span className="font-mono text-xs text-zinc-500">brew install --cask bettershot</span>
          </span>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
