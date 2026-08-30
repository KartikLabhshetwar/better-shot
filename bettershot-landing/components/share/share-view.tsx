"use client"

import { useCallback, useEffect, useState } from "react"
import Image from "next/image"
import { CheckIcon, DownloadSimpleIcon, LinkIcon } from "@phosphor-icons/react/dist/ssr"
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
  const author = manifest.authorName?.trim()
  const aspectRatio =
    manifest.width && manifest.height ? manifest.width / manifest.height : isVideo ? 16 / 9 : 4 / 3

  const meta = [
    manifest.createdAt ? formatRelativeTime(manifest.createdAt) : null,
    isVideo && manifest.durationSeconds ? formatDuration(manifest.durationSeconds) : null,
    manifest.width && manifest.height ? `${manifest.width} × ${manifest.height}` : null,
    manifest.byteSize ? formatBytes(manifest.byteSize) : null,
  ].filter(Boolean) as string[]

  return (
    <div className="flex min-h-dvh flex-col bg-white text-zinc-900 selection:bg-brand/20">
      <header className="sticky top-0 z-20 border-b border-zinc-200 bg-white/80 backdrop-blur-xl">
        <div className="mx-auto flex h-14 w-full max-w-[1100px] items-center justify-between gap-3 px-6">
          <a
            href="/"
            className={cn(
              "flex shrink-0 items-center gap-2 outline-none",
              fluid,
              "focus-visible:ring-2 focus-visible:ring-brand/60",
            )}
          >
            <Image src="/logo.png" alt="" width={24} height={24} className="rounded-md" />
            <span className="text-sm font-semibold tracking-tight text-zinc-900">Better Shot</span>
          </a>

          <div className="flex items-center gap-2">
            <CopyLinkButton />

            <a
              href={downloadUrl}
              className={cn(
                "inline-flex items-center gap-2 whitespace-nowrap rounded-xl bg-brand px-3 py-2 text-xs font-semibold text-white outline-none",
                fluid,
                "hover:bg-brand-600 focus-visible:ring-2 focus-visible:ring-brand/60 active:scale-[0.98]",
              )}
            >
              <DownloadSimpleIcon size={14} weight="bold" />
              <span className="hidden sm:inline">Download</span>
            </a>
          </div>
        </div>
      </header>

      <main id="main" className="mx-auto flex w-full max-w-[1100px] flex-1 flex-col px-6 pb-12 pt-8">
        <div className="my-auto">
          <div className="mb-5">
            <h1 className="break-words text-xl tracking-tight sm:text-2xl">{title}</h1>
            <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-zinc-400">
              {author && (
                <span className="flex items-center gap-2 text-zinc-600">
                  <span
                    aria-hidden
                    className="grid size-6 shrink-0 place-content-center rounded-full bg-brand text-[11px] font-bold uppercase text-white"
                  >
                    {author.charAt(0)}
                  </span>
                  <span className="font-semibold">{author}</span>
                </span>
              )}
              {meta.map((entry, index) => (
                <span key={entry} className="flex items-center gap-2">
                  {(index > 0 || author) && (
                    <span aria-hidden className="text-zinc-200">
                      &middot;
                    </span>
                  )}
                  {entry}
                </span>
              ))}
            </div>
          </div>

          <div
            className="mx-auto w-full max-w-full"
            style={{
              width: `max(320px, calc((100dvh - 340px) * ${aspectRatio}))`,
            }}
          >
            {isVideo ? (
              <VideoPlayer src={mediaUrl} poster={posterUrl} title={title} aspectRatio={aspectRatio} />
            ) : (
              <ImageViewer src={mediaUrl} title={title} aspectRatio={aspectRatio} />
            )}
          </div>

          {isVideo && (
            <p className="mt-3 hidden text-center text-xs text-zinc-400 sm:block">
              Space play and pause &middot; Arrow keys seek 5s &middot; J and L seek 10s &middot; M mute &middot; F full screen
            </p>
          )}
        </div>
      </main>

      <footer className="border-t border-zinc-200 bg-zinc-50">
        <div className="mx-auto flex w-full max-w-[1100px] flex-col items-start justify-between gap-4 px-6 py-8 sm:flex-row sm:items-center">
          <div className="flex items-center gap-3">
            <Image src="/logo.png" alt="" width={32} height={32} className="rounded-md" />
            <div>
              <p className="text-sm font-semibold text-zinc-900">
                {isVideo ? "Recorded" : "Captured"} with Better Shot
              </p>
              <p className="text-xs text-zinc-600">
                Free, open source screenshots and recordings for macOS. No account, no watermark.
              </p>
            </div>
          </div>
          <a
            href="https://bettershot.site/download"
            target="_blank"
            rel="noreferrer"
            className={cn(
              "inline-flex shrink-0 items-center whitespace-nowrap rounded-xl border border-zinc-200 px-4 py-2.5 text-xs font-semibold text-zinc-900 outline-none",
              "transition-colors duration-150 hover:border-zinc-400 focus-visible:ring-2 focus-visible:ring-brand/60",
            )}
          >
            Get Better Shot free
          </a>
        </div>
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
        "inline-flex items-center gap-2 whitespace-nowrap rounded-xl border border-zinc-200 px-3 py-2 text-xs font-medium outline-none",
        fluid,
        "hover:border-zinc-400 focus-visible:ring-2 focus-visible:ring-brand/60 active:scale-[0.98]",
        copied ? "text-emerald-600" : "text-zinc-600 hover:text-zinc-900",
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
      <span className="hidden w-14 text-left sm:inline">{copied ? "Copied" : "Copy link"}</span>
    </button>
  )
}
