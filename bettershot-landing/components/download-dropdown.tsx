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

interface DownloadDropdownProps {
  release: ReleaseInfo
  source: "navbar" | "hero" | "cta" | "mobile-menu"
  variant?: "default" | "outline"
  size?: "default" | "sm" | "lg"
  className?: string
  showLabel?: boolean
}

export function DownloadDropdown({
  release,
  source,
  variant = "default",
  size = "lg",
  className,
  showLabel = true,
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
        <Button size={size} variant={variant === "outline" ? "outline" : "default"} className={className}>
          {showLabel ? (
            <>
              <Download className="mr-2 h-4 w-4" />
              Download
            </>
          ) : (
            <Download className="h-4 w-4" />
          )}
          <ChevronDown className="ml-1.5 h-3 w-3 opacity-50" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56 border-none shadow-lg bg-white rounded-lg p-1">
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
