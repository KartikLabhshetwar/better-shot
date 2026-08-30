"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { Maximize, Minus, Plus } from "lucide-react"
import { cn } from "@/lib/utils"

interface ImageViewerProps {
  src: string
  title: string
  aspectRatio: number
}

const MIN_SCALE = 1
const MAX_SCALE = 6
const ZOOM_STEP = 1.6

interface Transform {
  scale: number
  x: number
  y: number
}

const IDENTITY: Transform = { scale: 1, x: 0, y: 0 }

export function ImageViewer({ src, title, aspectRatio }: ImageViewerProps) {
  const stageRef = useRef<HTMLDivElement | null>(null)
  const [transform, setTransform] = useState<Transform>(IDENTITY)
  const [dragging, setDragging] = useState(false)
  const [failed, setFailed] = useState(false)
  const dragOrigin = useRef({ x: 0, y: 0, transformX: 0, transformY: 0 })

  const clamp = useCallback((next: Transform): Transform => {
    const stage = stageRef.current
    if (!stage) return next
    const scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, next.scale))
    const { width, height } = stage.getBoundingClientRect()
    const maxX = (width * (scale - 1)) / 2
    const maxY = (height * (scale - 1)) / 2
    return {
      scale,
      x: Math.min(maxX, Math.max(-maxX, next.x)),
      y: Math.min(maxY, Math.max(-maxY, next.y)),
    }
  }, [])

  const zoomAround = useCallback(
    (factor: number, clientX?: number, clientY?: number) => {
      const stage = stageRef.current
      if (!stage) return
      setTransform((prev) => {
        const scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, prev.scale * factor))
        if (scale === MIN_SCALE) return IDENTITY
        const rect = stage.getBoundingClientRect()
        const pointerX = (clientX ?? rect.left + rect.width / 2) - rect.left - rect.width / 2
        const pointerY = (clientY ?? rect.top + rect.height / 2) - rect.top - rect.height / 2
        const ratio = scale / prev.scale
        return clamp({
          scale,
          x: pointerX - (pointerX - prev.x) * ratio,
          y: pointerY - (pointerY - prev.y) * ratio,
        })
      })
    },
    [clamp]
  )

  const handlePointerDown = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (transform.scale === 1) return
      event.currentTarget.setPointerCapture(event.pointerId)
      dragOrigin.current = {
        x: event.clientX,
        y: event.clientY,
        transformX: transform.x,
        transformY: transform.y,
      }
      setDragging(true)
    },
    [transform]
  )

  const handlePointerMove = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (!dragging) return
      const origin = dragOrigin.current
      setTransform((prev) =>
        clamp({
          scale: prev.scale,
          x: origin.transformX + (event.clientX - origin.x),
          y: origin.transformY + (event.clientY - origin.y),
        })
      )
    },
    [clamp, dragging]
  )

  const handlePointerUp = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    event.currentTarget.releasePointerCapture(event.pointerId)
    setDragging(false)
  }, [])

  useEffect(() => {
    const stage = stageRef.current
    if (!stage) return
    const onWheel = (event: WheelEvent) => {
      if (!event.ctrlKey && !event.metaKey) return
      event.preventDefault()
      zoomAround(event.deltaY < 0 ? 1.12 : 1 / 1.12, event.clientX, event.clientY)
    }
    stage.addEventListener("wheel", onWheel, { passive: false })
    return () => stage.removeEventListener("wheel", onWheel)
  }, [zoomAround])

  const zoomed = transform.scale > 1

  return (
    <div className="relative w-full">
      <div
        ref={stageRef}
        className={cn(
          "relative overflow-hidden rounded-2xl bg-ink/[0.03] shadow-lg ring-1 ring-ink/10",
          zoomed ? (dragging ? "cursor-grabbing" : "cursor-grab") : "cursor-zoom-in"
        )}
        style={{ aspectRatio }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerUp}
        onDoubleClick={(event) =>
          zoomed ? setTransform(IDENTITY) : zoomAround(2.5, event.clientX, event.clientY)
        }
      >
        {failed ? (
          <div className="absolute inset-0 grid place-content-center gap-2 p-6 text-center">
            <p className="text-sm font-medium text-zinc-900">This screenshot could not be loaded</p>
            <p className="text-xs text-zinc-400">The file may have been moved or deleted.</p>
          </div>
        ) : (
          <img
            src={src}
            alt={title}
            draggable={false}
            onError={() => setFailed(true)}
            className="size-full select-none object-contain will-change-transform"
            style={{
              transform: `translate3d(${transform.x}px, ${transform.y}px, 0) scale(${transform.scale})`,
              transition: dragging ? "none" : "transform 260ms cubic-bezier(0.22, 1, 0.36, 1)",
            }}
          />
        )}

        {!failed && (
          <div className="absolute bottom-3 left-1/2 flex -translate-x-1/2 items-center gap-0.5 rounded-full border border-zinc-200 bg-white/85 p-1 text-zinc-900 opacity-0 shadow-lg backdrop-blur-xl transition-opacity duration-200 focus-within:opacity-100 hover:opacity-100 motion-reduce:transition-none">
            <ZoomButton label="Zoom out" onClick={() => zoomAround(1 / ZOOM_STEP)} disabled={!zoomed}>
              <Minus className="size-4" />
            </ZoomButton>
            <button
              type="button"
              onClick={() => setTransform(IDENTITY)}
              className="min-w-14 rounded-full px-2 py-1 text-xs font-semibold tabular-nums tracking-[0.01em] text-zinc-500 transition-colors duration-100 hover:bg-zinc-100 hover:text-zinc-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/40"
            >
              {Math.round(transform.scale * 100)}%
            </button>
            <ZoomButton
              label="Zoom in"
              onClick={() => zoomAround(ZOOM_STEP)}
              disabled={transform.scale >= MAX_SCALE}
            >
              <Plus className="size-4" />
            </ZoomButton>
            <ZoomButton label="Fit to screen" onClick={() => setTransform(IDENTITY)} disabled={!zoomed}>
              <Maximize className="size-4" />
            </ZoomButton>
          </div>
        )}
      </div>
    </div>
  )
}

function ZoomButton({
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
      className="grid size-8 place-content-center rounded-full text-zinc-500 transition-[background-color,transform] duration-100 ease-out hover:bg-zinc-100 hover:text-zinc-900 active:scale-[0.92] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/40 disabled:opacity-30 motion-reduce:transition-none motion-reduce:active:scale-100"
    >
      {children}
    </button>
  )
}
