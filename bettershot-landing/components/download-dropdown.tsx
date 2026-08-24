"use client"

import * as React from "react"
import { ChevronDown, Download, Terminal } from "lucide-react"
import { Button } from "@/components/ui/button"
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
  sm: "h-9 px-3.5 text-[12.5px] rounded-lg",
  default: "h-11 px-5 text-[13.5px] rounded-lg",
  lg: "h-12 px-6 text-[14px] rounded-xl",
}

interface DownloadDropdownProps {
  release: ReleaseInfo
  source: "navbar" | "hero" | "cta" | "mobile-menu"
  variant?: "default" | "outline"
  size?: "default" | "sm" | "lg"
  className?: string
  showLabel?: boolean
  label?: string
}

export function DownloadDropdown({
  release,
  source,
  variant = "default",
  size = "lg",
  className,
  showLabel = true,
  label,
}: DownloadDropdownProps) {
  const handleDownload = (arch: "appleSilicon" | "intel") => {
    trackDownload(source)
    window.open(release[arch], "_blank")
  }

  const handleHomebrew = () => {
    trackDownload(source)
    window.open("https://formulae.brew.sh/cask/bettershot", "_blank")
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          size={size}
          variant={variant === "outline" ? "outline" : "default"}
          className={cn(
            "font-medium tracking-[-0.01em] transition-all",
            sizeClass[size],
            variant === "outline"
              ? "border-ink/[0.12] bg-white text-ink/70 hover:bg-ink/[0.03] hover:text-ink"
              : "bg-ink text-white hover:bg-ink/85 shadow-[0_1px_2px_rgba(0,0,0,0.2)]",
            className,
          )}
        >
          {showLabel ? (
            <>
              <Download className="mr-2 h-4 w-4" />
              {label ?? "Download for macOS"}
            </>
          ) : (
            <Download className="h-4 w-4" />
          )}
          <ChevronDown className="ml-1.5 h-3 w-3 opacity-50" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="end"
        className="w-60 border border-ink/[0.08] shadow-[0_8px_30px_rgba(0,0,0,0.10)] bg-white rounded-xl p-1.5"
      >
        <DropdownMenuItem onClick={() => handleDownload("appleSilicon")} className="cursor-pointer rounded-md">
          <Download className="mr-2 h-4 w-4" />
          <div className="flex flex-col">
            <span className="font-medium">Apple Silicon</span>
            <span className="text-xs text-muted-foreground">M1, M2, M3, M4</span>
          </div>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => handleDownload("intel")} className="cursor-pointer rounded-md">
          <Download className="mr-2 h-4 w-4" />
          <div className="flex flex-col">
            <span className="font-medium">Intel</span>
            <span className="text-xs text-muted-foreground">x86_64</span>
          </div>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleHomebrew} className="cursor-pointer rounded-md">
          <Terminal className="mr-2 h-4 w-4" />
          <div className="flex flex-col">
            <span className="font-medium">Homebrew</span>
            <span className="text-xs text-muted-foreground">brew install --cask bettershot</span>
          </div>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
