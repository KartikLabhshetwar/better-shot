"use client"

import { useCallback, useEffect, useState } from "react"
import Image from "next/image"
import { ArrowUpRightIcon, CheckIcon, DownloadSimpleIcon, LinkIcon } from "@phosphor-icons/react/dist/ssr"
import type { ResolvedShare } from "@/lib/share"
import { formatBytes, formatDuration, formatRelativeTime } from "@/lib/share"
import { cn } from "@/lib/utils"
import { ImageViewer } from "./image-viewer"
import { VideoPlayer } from "./video-player"

interface ShareViewProps {
  share: ResolvedShare
}

const fluid = "duration-300 ease-[cubic-bezier(0.32,0.72,0,1)]"

export function ShareView({ share }: ShareViewProps) {
  const { manifest, mediaUrl, posterUrl, downloadUrl } = share
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
    <div className="flex min-h-dvh flex-col bg-canvas text-ink selection:bg-brand/20">
      <header className="sticky top-0 z-20 border-b border-ink/[0.06] bg-canvas/80 backdrop-blur-xl">
        <div className="mx-auto flex h-16 w-full max-w-[1080px] items-center gap-3 px-6">
          <a
            href="/"
            className={cn(
              "flex shrink-0 items-center gap-2 rounded-md outline-none",
              fluid,
              "focus-visible:ring-2 focus-visible:ring-brand/60",
            )}
          >
            <Image src="/logo.png" alt="" width={24} height={24} className="rounded-md" />
            <span className="text-sm font-semibold tracking-tight text-ink/75">Better Shot</span>
          </a>

          <span aria-hidden className="mx-1 hidden h-4 w-px bg-ink/10 sm:block" />

          <p className="min-w-0 flex-1 truncate text-sm text-ink/60" title={title}>
            {title}
          </p>

          <CopyLinkButton />

          <a
            href={downloadUrl}
            className={cn(
              "hidden items-center gap-2 rounded-lg bg-ink px-3 py-2 text-xs font-semibold text-canvas outline-none sm:inline-flex",
              fluid,
              "hover:bg-ink/85 focus-visible:ring-2 focus-visible:ring-brand/60 active:scale-[0.98]",
            )}
          >
            <DownloadSimpleIcon size={14} weight="bold" />
            Download
          </a>
        </div>
      </header>

      <main id="main" className="mx-auto w-full max-w-[1080px] flex-1 px-6 pb-12 pt-8">
        <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div className="min-w-0">
            <h1 className="display-sm text-xl sm:text-2xl">{title}</h1>
            {meta.length > 0 && (
              <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-ink/55">
                {meta.map((entry, index) => (
                  <span key={entry} className="flex items-center gap-2">
                    {index > 0 && (
                      <span aria-hidden className="text-ink/20">
                        ·
                      </span>
                    )}
                    {entry}
                  </span>
                ))}
              </p>
            )}
          </div>

          <a
            href={downloadUrl}
            className={cn(
              "inline-flex items-center gap-2 rounded-lg border border-ink/[0.1] px-3 py-2 text-xs font-medium text-ink/60 outline-none sm:hidden",
              fluid,
              "hover:border-ink/[0.18] hover:text-ink focus-visible:ring-2 focus-visible:ring-brand/60 active:scale-[0.98]",
            )}
          >
            <DownloadSimpleIcon size={14} weight="bold" />
            Download
          </a>
        </div>

        {isVideo ? (
          <VideoPlayer src={mediaUrl} poster={posterUrl} title={title} aspectRatio={aspectRatio} />
        ) : (
          <ImageViewer src={mediaUrl} title={title} aspectRatio={aspectRatio} />
        )}

        {isVideo && (
          <p className="mt-3 hidden text-center text-xs text-ink/60 sm:block">
            Space play and pause · Arrow keys seek 5s · J and L seek 10s · M mute · F full screen
          </p>
        )}
      </main>

      <footer className="pb-12">
        <a
          href="https://bettershot.site"
          target="_blank"
          rel="noreferrer"
          className={cn(
            "group mx-auto flex w-fit items-center gap-2 rounded-full border border-ink/[0.1] bg-white px-3 py-2 text-xs text-ink/55 outline-none",
            fluid,
            "hover:border-ink/[0.18] hover:text-ink focus-visible:ring-2 focus-visible:ring-brand/60",
          )}
        >
          <Image src="/logo.png" alt="" width={16} height={16} className="rounded-sm" />
          {isVideo ? "Recorded" : "Captured"} with{" "}
          <span className="font-semibold text-ink/85">Better Shot</span>
          <ArrowUpRightIcon
            size={12}
            weight="bold"
            className={cn(
              "text-ink/55",
              fluid,
              "group-hover:-translate-y-px group-hover:translate-x-px",
            )}
          />
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
        "inline-flex items-center gap-2 rounded-lg border border-ink/[0.1] px-3 py-2 text-xs font-medium outline-none",
        fluid,
        "hover:border-ink/[0.18] focus-visible:ring-2 focus-visible:ring-brand/60 active:scale-[0.98]",
        copied ? "text-emerald-600" : "text-ink/60 hover:text-ink",
      )}
    >
      <span className="grid h-4 w-4 place-content-center">
        <CheckIcon
          size={14}
          weight="bold"
          className={cn("col-start-1 row-start-1", fluid, copied ? "scale-100 opacity-100" : "scale-50 opacity-0")}
        />
        <LinkIcon
          size={14}
          weight="bold"
          className={cn("col-start-1 row-start-1", fluid, copied ? "scale-50 opacity-0" : "scale-100 opacity-100")}
        />
      </span>
      <span className="hidden w-12 text-left sm:inline">{copied ? "Copied" : "Copy link"}</span>
    </button>
  )
}
