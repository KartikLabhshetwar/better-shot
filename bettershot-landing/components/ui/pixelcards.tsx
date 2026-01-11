"use client"

import { cn } from "@/lib/utils"
import { useEffect, useRef } from "react"

interface PixelCardProps {
  label: string
  canvasProps: {
    gap: number
    speed: number
    colors: string
  }
  number: number
  icon: string
  desc: string
  color: string
}

export function PixelCard({ label, canvasProps, number, icon, desc, color }: PixelCardProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext("2d")
    if (!ctx) return

    // Simple animated pixel effect
    let animationId: number
    let time = 0

    const animate = () => {
      time += 0.01
      ctx.clearRect(0, 0, canvas.width, canvas.height)

      const colors = canvasProps.colors.split(", ")

      for (let x = 0; x < canvas.width; x += canvasProps.gap) {
        for (let y = 0; y < canvas.height; y += canvasProps.gap) {
          const opacity = Math.sin(time + x * 0.01 + y * 0.01) * 0.5 + 0.5
          const colorIndex = Math.floor(Math.random() * colors.length)
          ctx.fillStyle =
            colors[colorIndex] +
            Math.floor(opacity * 255)
              .toString(16)
              .padStart(2, "0")
          ctx.fillRect(x, y, 2, 2)
        }
      }

      animationId = requestAnimationFrame(animate)
    }

    animate()

    return () => {
      if (animationId) {
        cancelAnimationFrame(animationId)
      }
    }
  }, [canvasProps])

  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-lg border bg-card p-6",
        color === "rose" && "border-rose-200 dark:border-rose-800",
      )}
    >
      <canvas ref={canvasRef} width={280} height={200} className="absolute inset-0 opacity-20" />
      <div className="relative z-10">
        <div className="mb-4 text-2xl font-bold">{icon}</div>
        <div className="text-3xl font-bold text-rose-600">{number}</div>
        <div className="text-sm text-muted-foreground">{desc}</div>
        <div className="mt-2 text-xs text-muted-foreground">{label}</div>
      </div>
    </div>
  )
}
