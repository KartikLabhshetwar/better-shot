"use client"

import * as React from "react"
import { ChevronDown, Download } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { trackDownload } from "@/lib/analytics"
import { downloadLinks } from "@/lib/downloads"
import { cn } from "@/lib/utils"

interface DownloadDropdownProps {
  source: "navbar" | "hero" | "cta" | "mobile-menu"
  variant?: "default" | "outline"
  size?: "default" | "sm" | "lg"
  className?: string
  showLabel?: boolean
  children?: React.ReactNode
}

export function DownloadDropdown({
  source,
  variant = "default",
  size = "lg",
  className,
  showLabel = true,
  children,
}: DownloadDropdownProps) {
  const handleDownload = (arch: "appleSilicon" | "intel") => {
    trackDownload(source)
    window.open(downloadLinks[arch], "_blank")
  }

  const buttonContent = children || (
    <>
      <ChevronDown className="mr-2 h-5 w-5" />
      {showLabel ? "Download for macOS" : "Download"}
    </>
  )

  if (variant === "default") {
    return (
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            size={size}
            className={cn(
              "rounded-lg bg-gradient-to-b from-primary to-primary/80 text-primary-foreground",
              "shadow-[0px_2px_0px_0px_rgba(255,255,255,0.3)_inset]",
              "hover:shadow-[0px_4px_0px_0px_rgba(255,255,255,0.3)_inset]",
              "transition-all px-6 py-3 text-base font-medium",
              className
            )}
          >
            {buttonContent}
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuItem
            onClick={() => handleDownload("appleSilicon")}
            className="cursor-pointer"
          >
            <Download className="mr-2 h-4 w-4" />
            <div className="flex flex-col">
              <span className="font-medium">Apple Silicon</span>
              <span className="text-xs text-muted-foreground">M1, M2, M3</span>
            </div>
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => handleDownload("intel")}
            className="cursor-pointer"
          >
            <Download className="mr-2 h-4 w-4" />
            <div className="flex flex-col">
              <span className="font-medium">Intel Mac</span>
              <span className="text-xs text-muted-foreground">x64</span>
            </div>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    )
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          size={size}
          variant={variant}
          className={cn("rounded-lg border-2", className)}
        >
          {buttonContent}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuItem
          onClick={() => handleDownload("appleSilicon")}
          className="cursor-pointer"
        >
          <Download className="mr-2 h-4 w-4" />
          <div className="flex flex-col">
            <span className="font-medium">Apple Silicon</span>
            <span className="text-xs text-muted-foreground">M1, M2, M3</span>
          </div>
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => handleDownload("intel")}
          className="cursor-pointer"
        >
          <Download className="mr-2 h-4 w-4" />
          <div className="flex flex-col">
            <span className="font-medium">Intel Mac</span>
            <span className="text-xs text-muted-foreground">x64</span>
          </div>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
