"use client"

import { useCallback, useEffect, useState } from "react"
import Image from "next/image"
import { ArrowUpRight, Check, Download, Link2 } from "lucide-react"
import type { ResolvedShare } from "@/lib/share"
import { formatBytes, formatDuration, formatRelativeTime } from "@/lib/share"
import { cn } from "@/lib/utils"
import { ImageViewer } from "./image-viewer"
import { VideoPlayer } from "./video-player"

interface ShareViewProps {
  share: ResolvedShare
}

export function ShareView({ share }: ShareViewProps) {
  const { manifest, mediaUrl, posterUrl } = share
  const isVideo = manifest.kind === "video"
  const title = manifest.title?.trim() || (isVideo ? "Untitled recording" : "Untitled screenshot")
  const aspectRatio =
    manifest.width && manifest.height ? manifest.width / manifest.height : isVideo ? 16 / 9 : 4 / 3

  const meta = [
    manifest.createdAt ? formatRelativeTime(manifest.createdAt) : null,
    isVideo && manifest.durationSeconds ? formatDuration(manifest.durationSeconds) : null,
    manifest.width && manifest.height ? `${manifest.width} × ${manifest.height}` : null,
    manifest.byteSize ? formatBytes(manifest.byteSize) : null,
  ].filter(Boolean) as string[]

  return (
    <div className="relative flex min-h-dvh flex-col bg-[#08080a] text-white">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 h-[420px] bg-[radial-gradient(ellipse_at_top,rgba(255,255,255,0.07),transparent_65%)]"
      />

      <header className="sticky top-0 z-20 border-b border-white/5 bg-[#08080a]/70 backdrop-blur-xl">
        <div className="mx-auto flex h-14 w-full max-w-6xl items-center gap-3 px-4 sm:px-6">
          <a href="/" className="flex shrink-0 items-center gap-2 outline-none focus-visible:ring-2 focus-visible:ring-white/70 focus-visible:ring-offset-2 focus-visible:ring-offset-[#08080a] rounded-md">
            <Image src="/logo.png" alt="" width={24} height={24} className="rounded-md" />
            <span className="text-sm font-semibold tracking-tight">Better Shot</span>
          </a>

          <div className="mx-1 hidden h-5 w-px bg-white/10 sm:block" />

          <p className="min-w-0 flex-1 truncate text-sm text-white/60 sm:text-white/75" title={title}>
            {title}
          </p>

          <CopyLinkButton />

          <a
            href={mediaUrl}
            download
            className="hidden h-8 items-center gap-1.5 rounded-lg bg-white px-3 text-xs font-semibold text-black transition-transform duration-150 ease-out will-change-transform hover:scale-[1.03] active:scale-[0.97] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70 focus-visible:ring-offset-2 focus-visible:ring-offset-[#08080a] motion-reduce:transition-none motion-reduce:hover:scale-100 sm:inline-flex"
          >
            <Download className="size-3.5" />
            Download
          </a>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 pb-10 pt-6 sm:px-6 sm:pt-10">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
          <div className="min-w-0">
            <h1 className="text-balance text-xl font-semibold tracking-tight sm:text-2xl">{title}</h1>
            {meta.length > 0 && (
              <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-white/45">
                {meta.map((entry, index) => (
                  <span key={entry} className="flex items-center gap-2">
                    {index > 0 && <span aria-hidden className="text-white/20">·</span>}
                    {entry}
                  </span>
                ))}
              </p>
            )}
          </div>

          <a
            href={mediaUrl}
            download
            className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-white/10 px-3 text-xs font-medium text-white/80 transition-colors duration-150 hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70 sm:hidden"
          >
            <Download className="size-3.5" />
            Download
          </a>
        </div>

        {isVideo ? (
          <VideoPlayer src={mediaUrl} poster={posterUrl} title={title} aspectRatio={aspectRatio} />
        ) : (
          <ImageViewer src={mediaUrl} title={title} aspectRatio={aspectRatio} />
        )}

        {isVideo && (
          <p className="mt-3 hidden text-center text-[11px] text-white/30 sm:block">
            Space play/pause · ← → seek 5s · J L seek 10s · M mute · F full screen
          </p>
        )}
      </main>

      <footer className="pb-10">
        <a
          href="https://bettershot.site"
          target="_blank"
          rel="noreferrer"
          className="group mx-auto flex w-fit items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] py-2 pl-3 pr-3.5 text-xs text-white/60 transition-colors duration-150 hover:bg-white/[0.08] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70"
        >
          <Image src="/logo.png" alt="" width={16} height={16} className="rounded" />
          {isVideo ? "Recorded" : "Captured"} with <span className="font-semibold text-white/85">Better Shot</span>
          <ArrowUpRight className="size-3.5 text-white/40 transition-transform duration-150 ease-out group-hover:-translate-y-px group-hover:translate-x-px motion-reduce:transition-none" />
        </a>
      </footer>
    </div>
  )
}

function CopyLinkButton() {
  const [copied, setCopied] = useState(false)

  const copy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(window.location.href)
      setCopied(true)
    } catch {
      window.prompt("Copy this link", window.location.href)
    }
  }, [])

  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => setCopied(false), 2000)
    return () => clearTimeout(timer)
  }, [copied])

  return (
    <button
      type="button"
      onClick={copy}
      aria-live="polite"
      className={cn(
        "inline-flex h-8 items-center gap-1.5 rounded-lg border border-white/10 px-2.5 text-xs font-medium transition-colors duration-150",
        "hover:bg-white/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70",
        copied ? "text-emerald-300" : "text-white/80 hover:text-white"
      )}
    >
      {copied ? <Check className="size-3.5" /> : <Link2 className="size-3.5" />}
      <span className="hidden sm:inline">{copied ? "Copied" : "Copy link"}</span>
    </button>
  )
}
