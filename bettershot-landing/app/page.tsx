"use client"

import { useState, useEffect } from "react"
import Image from "next/image"
import Link from "next/link"
import { DownloadDropdown } from "@/components/download-dropdown"

export default function Home() {
  const [starCount, setStarCount] = useState(0)
  const [targetStars, setTargetStars] = useState(0)

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
    <div className="min-h-screen w-full flex flex-col bg-[#faf9f7]">
      <header className="fixed top-0 left-0 right-0 z-50">
        <div className="backdrop-blur-lg bg-[#faf9f7]/80">
          <div className="max-w-[880px] mx-auto px-6 h-12 flex items-center justify-between">
            <a href="/" className="flex items-center gap-2 text-[13px] font-medium text-[#1a1a1a]/70 tracking-[-0.01em]">
              <Image src="/logo.png" alt="Better Shot" width={20} height={20} className="rounded-[4px]" />
              Better Shot
            </a>
            <div className="flex items-center gap-4">
              <a
                href="https://github.com/KartikLabhshetwar/better-shot"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[12px] text-[#1a1a1a]/30 hover:text-[#1a1a1a]/60 transition-colors"
              >
                GitHub{starCount > 0 ? ` (${starCount})` : ""}
              </a>
              <DownloadDropdown source="navbar" size="sm" showLabel={false} />
            </div>
          </div>
        </div>
      </header>

      <main className="flex-1 flex flex-col items-center justify-center px-6">
        <div className="max-w-[520px] w-full text-center">
          <div className="flex justify-center mb-8">
            <Image
              src="/logo.png"
              alt="Better Shot"
              width={72}
              height={72}
              className="rounded-[16px] shadow-[0_2px_8px_rgba(0,0,0,0.06)]"
              priority
            />
          </div>

          <h1 className="text-[clamp(40px,7vw,72px)] leading-[1.02] font-semibold tracking-[-0.045em] text-[#1a1a1a]">
            Better Shot
          </h1>

          <p className="text-[15px] leading-[1.7] text-[#1a1a1a]/40 mt-5 max-w-[340px] mx-auto">
            Free, open-source screenshot tool for macOS.
            Capture, annotate, share.
          </p>

          <div className="flex items-center justify-center gap-3 mt-10">
            <DownloadDropdown source="hero" />
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center px-4 py-2 text-[13px] font-medium text-[#1a1a1a]/35 hover:text-[#1a1a1a]/60 border border-[#1a1a1a]/[0.08] hover:border-[#1a1a1a]/[0.15] rounded-lg transition-all"
            >
              Source
            </a>
          </div>
        </div>
      </main>

      <footer>
        <div className="max-w-[880px] mx-auto px-6 py-8 flex items-center justify-between">
          <p className="text-[11px] text-[#1a1a1a]/15">
            &copy; {new Date().getFullYear()} Better Shot
          </p>
          <nav className="flex items-center gap-5">
            <a
              href="https://x.com/code_kartik"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[11px] text-[#1a1a1a]/15 hover:text-[#1a1a1a]/40 transition-colors"
            >
              Twitter
            </a>
            <Link
              href="/privacy"
              className="text-[11px] text-[#1a1a1a]/15 hover:text-[#1a1a1a]/40 transition-colors"
            >
              Privacy
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  )
}
