"use client"

import { motion } from "framer-motion"
import { useState, useEffect } from "react"
import { Badge } from "@/components/ui/badge"
import { Download, ChevronDown, Play } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { trackDownload } from "@/lib/analytics"
import { HeroVideoDialog } from "@/components/ui/hero-video-dialog"

export default function Hero() {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  if (!mounted) {
    return null
  }

  const handleDownload = () => {
    trackDownload("hero")
    window.open("https://github.com/KartikLabhshetwar/better-shot/releases/latest", "_blank")
  }

  return (
    <section className="relative overflow-hidden min-h-dvh flex items-start">
      <div
        className="absolute inset-0 z-0"
        style={{
          background: "radial-gradient(ellipse 50% 35% at 50% 0%, rgba(226, 232, 240, 0.12), transparent 60%), #000000",
        }}
      />
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 relative z-10 w-full pt-28 sm:pt-36 lg:pt-55">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12 items-start">
          <div className="flex flex-col">
            <div className="mb-6">
            <a
          href="https://peerlist.io/code_kartik/project/better-shot--free-screenshot-tool-for-macos"
          target="_blank"
          rel="noreferrer"
          className="inline-block"
        >
          <img
            src="https://peerlist.io/api/v1/projects/embed/PRJHLKL6L8JN6LDL8CEAJQOLAOMDMK?showUpvote=true&theme=dark"
            alt="Better Shot - Free Screenshot Tool for macOS"
            style={{ width: "auto", height: "72px" }}
          />
        </a>
            </div>
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
                  "text-2xl sm:text-3xl md:text-4xl lg:text-5xl font-bold tracking-tight",
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
              <HeroVideoDialog
                videoSrc="https://www.youtube.com/embed/Pi5Ag_ZRsEo"
                thumbnailSrc="https://img.youtube.com/vi/Pi5Ag_ZRsEo/maxresdefault.jpg"
                thumbnailAlt="Better Shot Demo Video"
                animationStyle="from-center"
                trigger={
                  <Button
                    size="lg"
                    variant="outline"
                    className={cn(
                      "rounded-lg border-2",
                      "hover:bg-background/50 transition-all px-6 py-3 text-base font-medium"
                    )}
                  >
                    <Play className="mr-2 h-5 w-5" />
                    View Demo
                  </Button>
                }
              />
            </motion.div>
          </div>

          <motion.div
            initial={{ opacity: 0, x: 50 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.5, delay: 0.3 }}
            className="flex items-start justify-center lg:justify-end"
          >
           
            <img
              src="/hero.png"
              alt="Better Shot Screenshot"
              className="w-full max-w-2xl h-auto object-contain"
              draggable={false}
            />
          </motion.div>
        </div>
      </div>
    </section>
  )
}
