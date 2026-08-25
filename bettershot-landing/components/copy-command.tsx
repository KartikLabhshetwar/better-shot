"use client"

import { useEffect, useState } from "react"
import { CheckIcon, CopyIcon } from "@phosphor-icons/react/dist/ssr"
import { cn } from "@/lib/utils"

export function CopyCommand({ command, className }: { command: string; className?: string }) {
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => setCopied(false), 2000)
    return () => clearTimeout(timer)
  }, [copied])

  return (
    <button
      type="button"
      aria-live="polite"
      aria-label={`Copy ${command}`}
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(command)
          setCopied(true)
        } catch {
          window.prompt("Copy this command", command)
        }
      }}
      className={cn(
        "group inline-flex items-center gap-3 border-2 border-rule bg-transparent px-4 py-3 font-sans text-[15px] text-ink outline-none transition-colors duration-150 hover:border-ink",
        className,
      )}
    >
      {command}
      <span className="grid h-4 w-4 place-content-center opacity-60">
        <CheckIcon
          size={14}
          weight="bold"
          className={`col-start-1 row-start-1 duration-300 ${copied ? "scale-100 opacity-100" : "scale-50 opacity-0"}`}
        />
        <CopyIcon
          size={14}
          weight="bold"
          className={`col-start-1 row-start-1 duration-300 ${copied ? "scale-50 opacity-0" : "scale-100 opacity-100"}`}
        />
      </span>
    </button>
  )
}
