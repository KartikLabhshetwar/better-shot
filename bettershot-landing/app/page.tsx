"use client"

import { useState, useEffect } from "react"
import { Star } from "lucide-react"
import Link from "next/link"
import { DownloadDropdown } from "@/components/download-dropdown"

export default function Home() {
  const [starCount, setStarCount] = useState(0)
  const [targetStars, setTargetStars] = useState(0)

  useEffect(() => {
    const root = window.document.documentElement
    root.classList.remove("light", "system")
    root.classList.add("dark")
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
    fetchStarCount()
  }, [])

  useEffect(() => {
    if (targetStars === 0) return
    const duration = 800
    const steps = 40
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

  return (
    <div className="min-h-screen w-full flex flex-col bg-[#0a0a0a]">
      {/* Header */}
      <header className="fixed top-0 left-0 right-0 z-50 border-b border-white/[0.04]">
        <div className="backdrop-blur-md bg-[#0a0a0a]/80">
          <div className="max-w-[960px] mx-auto px-6 h-14 flex items-center justify-between">
            <a href="/" className="flex items-center gap-2">
              <img src="/icon.png" alt="Better Shot" className="w-5 h-5" />
              <span className="text-[14px] font-medium text-white/80 tracking-[-0.01em]">Better Shot</span>
            </a>
            <div className="flex items-center gap-3">
              <a
                href="https://github.com/KartikLabhshetwar/better-shot"
                target="_blank"
                rel="noopener noreferrer"
                className="hidden sm:inline-flex items-center gap-1.5 text-[13px] text-white/40 hover:text-white/70 transition-colors"
              >
                <Star className="h-3.5 w-3.5" />
                {starCount > 0 && <span className="tabular-nums">{starCount.toLocaleString()}</span>}
              </a>
              <DownloadDropdown source="navbar" size="sm" showLabel={false} />
            </div>
          </div>
        </div>
      </header>

      {/* Hero */}
      <main className="flex-1 flex flex-col items-center justify-center px-6 pt-14">
        <div className="max-w-[600px] w-full text-center py-32 sm:py-44">
          <p className="text-[13px] tracking-[0.08em] uppercase text-white/25 mb-6">
            Free & Open Source
          </p>

          <h1 className="text-[clamp(36px,6vw,64px)] leading-[1.05] font-semibold tracking-[-0.04em] text-white mb-6">
            Screenshot tool
            <br />
            <span className="text-white/30">for macOS</span>
          </h1>

          <p className="text-[16px] leading-[1.6] text-white/35 max-w-[400px] mx-auto mb-10">
            Capture, annotate, and share. A single shortcut.
            No account, no subscription.
          </p>

          <div className="flex items-center justify-center gap-3">
            <DownloadDropdown source="hero" />
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center px-5 py-2.5 text-[14px] font-medium text-white/40 hover:text-white/70 border border-white/[0.08] hover:border-white/[0.14] rounded-lg transition-all"
            >
              GitHub
            </a>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-white/[0.04]">
        <div className="max-w-[960px] mx-auto px-6 py-10">
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
            <p className="text-[12px] text-white/20">
              &copy; {new Date().getFullYear()} Better Shot
            </p>
            <nav className="flex items-center gap-6">
              <a
                href="https://github.com/KartikLabhshetwar/better-shot"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[12px] text-white/20 hover:text-white/50 transition-colors"
              >
                GitHub
              </a>
              <a
                href="https://x.com/code_kartik"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[12px] text-white/20 hover:text-white/50 transition-colors"
              >
                Twitter
              </a>
              <a
                href="https://discord.gg/zThjstVs"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[12px] text-white/20 hover:text-white/50 transition-colors"
              >
                Discord
              </a>
              <Link
                href="/privacy"
                className="text-[12px] text-white/20 hover:text-white/50 transition-colors"
              >
                Privacy
              </Link>
            </nav>
          </div>
        </div>
      </footer>
    </div>
  )
}
