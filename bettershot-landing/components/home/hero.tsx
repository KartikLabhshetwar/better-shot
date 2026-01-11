"use client"

import { motion } from "framer-motion"
import { useState, useEffect } from "react"
import { Badge } from "@/components/ui/badge"
import { Download, ChevronDown } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

export default function Hero() {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

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
                "hover:text-foreground transition-colors"
              )}
            >
              Star us on GitHub
            </a>
          </motion.div>
        </div>
      </div>
    </section>
  )
}
