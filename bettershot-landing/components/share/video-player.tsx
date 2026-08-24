"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import {
  Loader2,
  Maximize,
  Minimize,
  Pause,
  PictureInPicture2,
  Play,
  RotateCcw,
  Volume1,
  Volume2,
  VolumeX,
} from "lucide-react"
import { formatDuration } from "@/lib/share"
import { cn } from "@/lib/utils"
import { Scrubber } from "./scrubber"
import { PLAYBACK_RATES, usePlayer } from "./use-player"

interface VideoPlayerProps {
  src: string
  poster: string | null
  title: string
  aspectRatio: number
}

const SEEK_NUDGE_SECONDS = 5

export function VideoPlayer({ src, poster, title, aspectRatio }: VideoPlayerProps) {
  const shellRef = useRef<HTMLDivElement | null>(null)
  const player = usePlayer(shellRef)
  const { state, videoRef } = player
  const [rateMenuOpen, setRateMenuOpen] = useState(false)
  const [nudge, setNudge] = useState<{ direction: -1 | 1; key: number } | null>(null)
  const [started, setStarted] = useState(false)
  const [pipSupported, setPipSupported] = useState(false)

  useEffect(() => {
    setPipSupported(Boolean(document.pictureInPictureEnabled))
  }, [])

  useEffect(() => {
    if (state.playing) setStarted(true)
  }, [state.playing])

  const nudgeSeek = useCallback(
    (direction: -1 | 1) => {
      player.skip(direction * SEEK_NUDGE_SECONDS)
      setNudge({ direction, key: Date.now() })
    },
    [player]
  )

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable)) {
        return
      }

      switch (event.key) {
        case " ":
        case "k":
          event.preventDefault()
          player.toggle()
          break
        case "ArrowLeft":
          event.preventDefault()
          nudgeSeek(-1)
          break
        case "ArrowRight":
          event.preventDefault()
          nudgeSeek(1)
          break
        case "j":
          event.preventDefault()
          player.skip(-10)
          break
        case "l":
          event.preventDefault()
          player.skip(10)
          break
        case "ArrowUp":
          event.preventDefault()
          player.setVolume(state.volume + 0.1)
          break
        case "ArrowDown":
          event.preventDefault()
          player.setVolume(state.volume - 0.1)
          break
        case "m":
          event.preventDefault()
          player.toggleMute()
          break
        case "f":
          event.preventDefault()
          player.toggleFullscreen()
          break
        case "Home":
          event.preventDefault()
          player.seek(0)
          break
        case "End":
          event.preventDefault()
          player.seek(state.duration)
          break
        default:
          if (/^[0-9]$/.test(event.key) && state.duration > 0) {
            event.preventDefault()
            player.seek((Number(event.key) / 10) * state.duration)
          }
      }
      player.revealControls()
    }

    window.addEventListener("keydown", onKeyDown)
    return () => window.removeEventListener("keydown", onKeyDown)
  }, [nudgeSeek, player, state.duration, state.volume])

  useEffect(() => {
    if (!nudge) return
    const timer = setTimeout(() => setNudge(null), 450)
    return () => clearTimeout(timer)
  }, [nudge])

  useEffect(() => {
    if (!rateMenuOpen) return
    const close = () => setRateMenuOpen(false)
    window.addEventListener("pointerdown", close)
    return () => window.removeEventListener("pointerdown", close)
  }, [rateMenuOpen])

  const chromeHidden = !player.controlsVisible && state.playing

  return (
    <div className="relative w-full">
      {poster && (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 -z-10 scale-110 opacity-40 blur-3xl saturate-150 motion-reduce:hidden"
          style={{
            backgroundImage: `url(${poster})`,
            backgroundSize: "cover",
            backgroundPosition: "center",
          }}
        />
      )}

      <div
        ref={shellRef}
        className={cn(
          "group/player relative overflow-hidden rounded-2xl bg-black shadow-2xl ring-1 ring-white/10",
          chromeHidden && "cursor-none"
        )}
        style={{ aspectRatio }}
        onPointerMove={player.revealControls}
        onPointerLeave={() => state.playing && player.revealControls()}
      >
        <video
          ref={videoRef}
          src={src}
          poster={poster ?? undefined}
          title={title}
          playsInline
          preload="metadata"
          className="size-full object-contain"
          onClick={player.toggle}
          onDoubleClick={player.toggleFullscreen}
        />

        {state.failed && (
          <div className="absolute inset-0 grid place-content-center gap-2 bg-black/80 p-6 text-center">
            <p className="text-sm font-medium text-white">This recording could not be loaded</p>
            <p className="text-pretty text-xs text-white/60">
              The file may have been moved, deleted, or the link has expired.
            </p>
          </div>
        )}

        {!state.failed && state.waiting && started && (
          <div className="pointer-events-none absolute inset-0 grid place-content-center">
            <Loader2 className="size-9 animate-spin text-white/80" />
          </div>
        )}

        {!state.failed && !started && (
          <button
            type="button"
            aria-label="Play"
            onClick={player.play}
            className="absolute inset-0 grid place-content-center bg-black/20 transition-colors duration-150 hover:bg-black/30"
          >
            <span className="grid size-20 place-content-center rounded-full bg-white/15 text-white ring-1 ring-white/25 backdrop-blur-md transition-transform duration-150 ease-out will-change-transform hover:scale-105 active:scale-95 motion-reduce:transition-none motion-reduce:hover:scale-100">
              <Play className="ml-1 size-8 fill-current" />
            </span>
          </button>
        )}

        {nudge && (
          <div
            key={nudge.key}
            className={cn(
              "pointer-events-none absolute top-1/2 grid size-16 -translate-y-1/2 place-content-center rounded-full bg-black/50 text-white backdrop-blur-sm",
              "animate-out fade-out zoom-out-75 duration-500 ease-out motion-reduce:animate-none",
              nudge.direction === -1 ? "left-8" : "right-8"
            )}
          >
            <RotateCcw className={cn("size-6", nudge.direction === 1 && "-scale-x-100")} />
            <span className="mt-0.5 text-center text-[10px] font-semibold tabular-nums">
              {SEEK_NUDGE_SECONDS}s
            </span>
          </div>
        )}

        <div
          className={cn(
            "absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/85 via-black/45 to-transparent px-3 pb-2.5 pt-12",
            "transition-opacity duration-200 ease-out motion-reduce:transition-none",
            chromeHidden ? "pointer-events-none opacity-0" : "opacity-100"
          )}
        >
          <Scrubber
            currentTime={state.currentTime}
            duration={state.duration}
            buffered={state.buffered}
            onSeek={player.seek}
            onScrubStart={player.beginScrub}
            onScrubEnd={player.endScrub}
            disabled={state.failed}
          />

          <div className="mt-1 flex items-center gap-1 text-white">
            <ControlButton
              label={state.playing ? "Pause" : "Play"}
              onClick={player.toggle}
              disabled={state.failed}
            >
              {state.playing ? (
                <Pause className="size-5 fill-current" />
              ) : (
                <Play className="size-5 fill-current" />
              )}
            </ControlButton>

            <VolumeControl
              volume={state.volume}
              muted={state.muted}
              onToggle={player.toggleMute}
              onChange={player.setVolume}
            />

            <span className="ml-1 select-none text-xs font-medium tabular-nums text-white/85">
              {formatDuration(state.currentTime)}
              <span className="mx-1 text-white/40">/</span>
              {formatDuration(state.duration)}
            </span>

            <div className="flex-1" />

            <div className="relative">
              <button
                type="button"
                aria-label="Playback speed"
                aria-expanded={rateMenuOpen}
                onPointerDown={(event) => event.stopPropagation()}
                onClick={() => setRateMenuOpen((open) => !open)}
                className="grid h-8 min-w-9 place-content-center rounded-lg px-1.5 text-xs font-semibold tabular-nums text-white/85 transition-colors duration-100 hover:bg-white/15 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70"
              >
                {state.rate}×
              </button>

              {rateMenuOpen && (
                <div
                  onPointerDown={(event) => event.stopPropagation()}
                  className="absolute bottom-full right-0 mb-2 min-w-24 overflow-hidden rounded-xl border border-white/10 bg-black/85 p-1 shadow-xl backdrop-blur-xl animate-in fade-in slide-in-from-bottom-1 duration-150 motion-reduce:animate-none"
                >
                  {PLAYBACK_RATES.map((rate) => (
                    <button
                      key={rate}
                      type="button"
                      onClick={() => {
                        player.setRate(rate)
                        setRateMenuOpen(false)
                      }}
                      className={cn(
                        "flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-xs tabular-nums transition-colors duration-100",
                        state.rate === rate
                          ? "bg-white/15 font-semibold text-white"
                          : "text-white/75 hover:bg-white/10 hover:text-white"
                      )}
                    >
                      {rate === 1 ? "Normal" : `${rate}×`}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {pipSupported && (
              <ControlButton label="Picture in picture" onClick={player.togglePip}>
                <PictureInPicture2 className="size-[18px]" />
              </ControlButton>
            )}

            <ControlButton
              label={state.fullscreen ? "Exit full screen" : "Full screen"}
              onClick={player.toggleFullscreen}
            >
              {state.fullscreen ? <Minimize className="size-5" /> : <Maximize className="size-5" />}
            </ControlButton>
          </div>
        </div>
      </div>
    </div>
  )
}

function ControlButton({
  label,
  onClick,
  disabled,
  children,
}: {
  label: string
  onClick: () => void
  disabled?: boolean
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className="grid size-8 place-content-center rounded-lg text-white/85 transition-colors duration-100 hover:bg-white/15 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70 disabled:opacity-40"
    >
      {children}
    </button>
  )
}

function VolumeControl({
  volume,
  muted,
  onToggle,
  onChange,
}: {
  volume: number
  muted: boolean
  onToggle: () => void
  onChange: (volume: number) => void
}) {
  const level = muted ? 0 : volume
  const Icon = level === 0 ? VolumeX : level < 0.5 ? Volume1 : Volume2

  return (
    <div className="group/volume flex items-center">
      <ControlButton label={muted ? "Unmute" : "Mute"} onClick={onToggle}>
        <Icon className="size-5" />
      </ControlButton>
      <div className="w-0 overflow-hidden transition-[width] duration-200 ease-out group-hover/volume:w-20 group-focus-within/volume:w-20 motion-reduce:transition-none">
        <input
          type="range"
          min={0}
          max={1}
          step={0.02}
          value={level}
          aria-label="Volume"
          onChange={(event) => onChange(Number(event.target.value))}
          className="ml-1 h-1 w-[72px] cursor-pointer appearance-none rounded-full bg-white/30 accent-white [&::-webkit-slider-thumb]:size-3 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-white"
          style={{
            background: `linear-gradient(to right, white ${level * 100}%, rgba(255,255,255,0.3) ${level * 100}%)`,
          }}
        />
      </div>
    </div>
  )
}
