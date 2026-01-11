"use client"

import { motion } from "framer-motion"
import { useState, useEffect } from "react"
import { Badge } from "@/components/ui/badge"
import { Download, ChevronDown, Star } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

export default function Hero() {
  const [mounted, setMounted] = useState(false)
  const [starCount, setStarCount] = useState(0)
  const [targetStars, setTargetStars] = useState(0)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    const fetchStarCount = async () => {
      try {
        const response = await fetch("https://api.github.com/repos/KartikLabhshetwar/better-shot")
        if (response.ok) {
          const data = await response.json()
          setTargetStars(data.stargazers_count || 0)
        }
      } catch (error) {
        console.error("Failed to fetch star count:", error)
      }
    }

    if (mounted) {
      fetchStarCount()
    }
  }, [mounted])

  useEffect(() => {
    if (targetStars === 0) return

    const duration = 2000
    const steps = 60
    const increment = targetStars / steps
    const stepDuration = duration / steps

    let current = 0
    const timer = setInterval(() => {
      current += increment
      if (current >= targetStars) {
        setStarCount(targetStars)
        clearInterval(timer)
      } else {
        setStarCount(Math.floor(current))
      }
    }, stepDuration)

    return () => clearInterval(timer)
  }, [targetStars])

  if (!mounted) {
    return null
  }

  const handleDownload = () => {
    window.open("https://github.com/KartikLabhshetwar/better-shot/releases/latest", "_blank")
  }

  return (
    <section className="relative overflow-hidden min-h-dvh flex items-center justify-center">
      <div
        className="absolute inset-0 z-0"
        style={{
          background: "radial-gradient(ellipse 50% 35% at 50% 0%, rgba(226, 232, 240, 0.12), transparent 60%), #000000",
        }}
      />
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="max-w-4xl">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="mb-6"
          >
            <Badge
              variant="outline"
              className={cn(
                "inline-flex items-center rounded-lg border-0 px-4 py-2 text-sm font-semibold",
                "bg-[#2a2a2a] text-[#e5e5e5] border-[#3a3a3a]"
              )}
            >
              FREE & OPEN SOURCE
            </Badge>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.1 }}
            className="mb-8"
          >
            <h1
              className={cn(
                "text-4xl sm:text-5xl md:text-6xl lg:text-7xl font-bold tracking-tight",
                "text-foreground"
              )}
            >
              Capture beautiful screenshots effortlessly
            </h1>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.2 }}
            className="flex items-center gap-4 flex-wrap"
          >
            <Button
              onClick={handleDownload}
              size="lg"
              className={cn(
                "rounded-lg bg-gradient-to-b from-primary to-primary/80 text-primary-foreground",
                "shadow-[0px_2px_0px_0px_rgba(255,255,255,0.3)_inset]",
                "hover:shadow-[0px_4px_0px_0px_rgba(255,255,255,0.3)_inset]",
                "transition-all px-6 py-3 text-base font-medium"
              )}
            >
              <ChevronDown className="mr-2 h-5 w-5" />
              Download for macOS
            </Button>
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className={cn(
                "text-sm text-muted-foreground",
                "hover:text-foreground transition-colors",
                "flex items-center gap-2"
              )}
            >
              <Star className="h-4 w-4 fill-current" />
              <span>Star us on GitHub</span>
              {starCount > 0 && (
                <span className="tabular-nums">{starCount.toLocaleString()}</span>
              )}
            </a>
          </motion.div>
        </div>
      </div>
    </section>
  )
}
