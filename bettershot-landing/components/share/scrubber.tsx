"use client"

import { useCallback, useRef, useState } from "react"
import { cn } from "@/lib/utils"
import { formatDuration } from "@/lib/share"

interface ScrubberProps {
  currentTime: number
  duration: number
  buffered: number
  onSeek: (time: number) => void
  onScrubStart: () => void
  onScrubEnd: () => void
  disabled?: boolean
}

export function Scrubber({
  currentTime,
  duration,
  buffered,
  onSeek,
  onScrubStart,
  onScrubEnd,
  disabled = false,
}: ScrubberProps) {
  const trackRef = useRef<HTMLDivElement | null>(null)
  const [hoverRatio, setHoverRatio] = useState<number | null>(null)
  const [active, setActive] = useState(false)

  const safeDuration = duration > 0 ? duration : 0
  const playedRatio = safeDuration > 0 ? Math.min(1, currentTime / safeDuration) : 0
  const bufferedRatio = safeDuration > 0 ? Math.min(1, buffered / safeDuration) : 0

  const ratioAt = useCallback((clientX: number) => {
    const track = trackRef.current
    if (!track) return 0
    const rect = track.getBoundingClientRect()
    if (rect.width === 0) return 0
    return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
  }, [])

  const handlePointerDown = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (disabled || safeDuration === 0) return
      event.currentTarget.setPointerCapture(event.pointerId)
      setActive(true)
      onScrubStart()
      onSeek(ratioAt(event.clientX) * safeDuration)
    },
    [disabled, onScrubStart, onSeek, ratioAt, safeDuration]
  )

  const handlePointerMove = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (disabled || safeDuration === 0) return
      const ratio = ratioAt(event.clientX)
      setHoverRatio(ratio)
      if (active) onSeek(ratio * safeDuration)
    },
    [active, disabled, onSeek, ratioAt, safeDuration]
  )

  const handlePointerUp = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (!active) return
      event.currentTarget.releasePointerCapture(event.pointerId)
      setActive(false)
      onScrubEnd()
    },
    [active, onScrubEnd]
  )

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (disabled || safeDuration === 0) return
      const step = event.shiftKey ? 10 : 5
      if (event.key === "ArrowLeft") {
        event.preventDefault()
        onSeek(currentTime - step)
      } else if (event.key === "ArrowRight") {
        event.preventDefault()
        onSeek(currentTime + step)
      } else if (event.key === "Home") {
        event.preventDefault()
        onSeek(0)
      } else if (event.key === "End") {
        event.preventDefault()
        onSeek(safeDuration)
      }
    },
    [currentTime, disabled, onSeek, safeDuration]
  )

  const expanded = active || hoverRatio !== null

  return (
    <div
      ref={trackRef}
      role="slider"
      tabIndex={disabled ? -1 : 0}
      aria-label="Seek"
      aria-valuemin={0}
      aria-valuemax={Math.round(safeDuration)}
      aria-valuenow={Math.round(currentTime)}
      aria-valuetext={`${formatDuration(currentTime)} of ${formatDuration(safeDuration)}`}
      className={cn(
        "group relative flex h-5 w-full touch-none items-center outline-none",
        disabled ? "cursor-default opacity-40" : "cursor-pointer"
      )}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
      onPointerLeave={() => !active && setHoverRatio(null)}
      onKeyDown={handleKeyDown}
    >
      <div
        className={cn(
          "relative h-[3px] w-full overflow-hidden rounded-full bg-white/25 transition-transform duration-150 ease-out",
          "group-focus-visible:ring-2 group-focus-visible:ring-white/70 group-focus-visible:ring-offset-2 group-focus-visible:ring-offset-black/60",
          expanded ? "scale-y-[2]" : "scale-y-100"
        )}
      >
        <div
          className="absolute inset-0 origin-left rounded-full bg-white/30"
          style={{ transform: `scaleX(${bufferedRatio})` }}
        />
        <div
          className={cn(
            "absolute inset-0 origin-left rounded-full bg-white",
            active ? "" : "transition-transform duration-100 ease-linear"
          )}
          style={{ transform: `scaleX(${playedRatio})` }}
        />
      </div>

      <div
        className="pointer-events-none absolute top-1/2"
        style={{ left: `${playedRatio * 100}%`, transform: "translate(-50%, -50%)" }}
      >
        <div
          className={cn(
            "size-3.5 rounded-full bg-white shadow-[0_1px_6px_rgba(0,0,0,0.45)]",
            "transition-[opacity,scale] duration-150 ease-out",
            expanded ? "scale-100 opacity-100" : "scale-50 opacity-0"
          )}
        />
      </div>

      {hoverRatio !== null && safeDuration > 0 && (
        <div
          className="pointer-events-none absolute bottom-full mb-2 -translate-x-1/2 rounded-md bg-black/80 px-1.5 py-0.5 text-[11px] font-medium tabular-nums text-white backdrop-blur-sm"
          style={{ left: `${hoverRatio * 100}%` }}
        >
          {formatDuration(hoverRatio * safeDuration)}
        </div>
      )}
    </div>
  )
}
