"use client"
import { useState, useEffect } from "react"
import { Star } from "lucide-react"
import Hero from "@/components/home/hero"
import Link from "next/link"
import Features from "@/components/features"
import { TestimonialsSection } from "@/components/testimonials"
import { NewReleasePromo } from "@/components/new-release-promo"
import { FAQSection } from "@/components/faq-section"
import { StickyFooter } from "@/components/sticky-footer"
import { trackDownload } from "@/lib/analytics"
import { cn } from "@/lib/utils"
import { Tooltip, TooltipTrigger, TooltipContent } from "@/components/ui/tooltip"

export default function Home() {
  const [isScrolled, setIsScrolled] = useState(false)
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false)
  const [starCount, setStarCount] = useState(0)
  const [targetStars, setTargetStars] = useState(0)

  useEffect(() => {
    const root = window.document.documentElement
    root.classList.remove("light", "system")
    root.classList.add("dark")
  }, [])

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 100)
    }

    window.addEventListener("scroll", handleScroll)
    return () => window.removeEventListener("scroll", handleScroll)
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

  const handleMobileNavClick = (elementId: string) => {
    setIsMobileMenuOpen(false)
    setTimeout(() => {
      const element = document.getElementById(elementId)
      if (element) {
        const headerOffset = 120 // Account for sticky header height + margin
        const elementPosition = element.getBoundingClientRect().top + window.pageYOffset
        const offsetPosition = elementPosition - headerOffset

        window.scrollTo({
          top: offsetPosition,
          behavior: "smooth",
        })
      }
    }, 100)
  }

  return (
    <div className="min-h-screen w-full relative bg-black">
      {/* Pearl Mist Background with Top Glow */}
      <div
        className="absolute inset-0 z-0"
        style={{
          background: "radial-gradient(ellipse 50% 35% at 50% 0%, rgba(226, 232, 240, 0.12), transparent 60%), #000000",
        }}
      />

      {/* Desktop Header */}
      <header
        className={`sticky top-4 z-[9999] mx-auto hidden w-full flex-row items-center justify-between self-start rounded-full bg-background/80 md:flex backdrop-blur-sm border border-border/50 shadow-lg transition-all duration-300 ${
          isScrolled ? "max-w-3xl px-2" : "max-w-5xl px-4"
        } py-2`}
        style={{
          willChange: "transform",
          transform: "translateZ(0)",
          backfaceVisibility: "hidden",
          perspective: "1000px",
        }}
      >
        <a
          className={`z-50 flex items-center justify-center gap-2 transition-all duration-300 ${
            isScrolled ? "ml-4" : ""
          }`}
          href="/"
        >
          <img
            src="/icon.png"
            alt="Better Shot"
            className="w-8 h-8"
          />
        </a>

        <div className="absolute inset-0 hidden flex-1 flex-row items-center justify-center space-x-2 text-sm font-medium text-muted-foreground transition duration-200 hover:text-foreground md:flex md:space-x-2 pointer-events-none">
          <a
            className="relative px-4 py-2 text-muted-foreground hover:text-foreground transition-colors cursor-pointer pointer-events-auto"
            onClick={(e) => {
              e.preventDefault()
              const element = document.getElementById("features")
              if (element) {
                const headerOffset = 120 // Account for sticky header height + margin
                const elementPosition = element.getBoundingClientRect().top + window.pageYOffset
                const offsetPosition = elementPosition - headerOffset

                window.scrollTo({
                  top: offsetPosition,
                  behavior: "smooth",
                })
              }
            }}
          >
            <span className="relative z-20">Features</span>
          </a>
          <a
            className="relative px-4 py-2 text-muted-foreground hover:text-foreground transition-colors cursor-pointer pointer-events-auto"
            onClick={(e) => {
              e.preventDefault()
              const element = document.getElementById("faq")
              if (element) {
                const headerOffset = 120 // Account for sticky header height + margin
                const elementPosition = element.getBoundingClientRect().top + window.pageYOffset
                const offsetPosition = elementPosition - headerOffset

                window.scrollTo({
                  top: offsetPosition,
                  behavior: "smooth",
                })
              }
            }}
          >
            <span className="relative z-20">FAQ</span>
          </a>
        </div>

        <div className="flex items-center gap-4 relative z-10">
          <Tooltip>
            <TooltipTrigger asChild>
              <a
                href="https://github.com/KartikLabhshetwar/better-shot"
                target="_blank"
                rel="noopener noreferrer"
                className={cn(
                  "inline-flex items-center gap-2 px-3 py-2 rounded-md",
                  "bg-[#2a2a2a] border border-[#3a3a3a]",
                  "text-[#e5e5e5] hover:text-white",
                  "transition-colors cursor-pointer",
                  "text-sm font-medium"
                )}
              >
                <Star className="h-4 w-4 fill-yellow-400 text-yellow-400" />
                {starCount > 0 ? (
                  <span className="tabular-nums text-[#e5e5e5]">{starCount.toLocaleString()}</span>
                ) : (
                  <span className="text-[#e5e5e5]">Star</span>
                )}
              </a>
            </TooltipTrigger>
            <TooltipContent>
              <p>Star us on GitHub</p>
            </TooltipContent>
          </Tooltip>
          <a
            href="https://github.com/KartikLabhshetwar/better-shot/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            onClick={() => trackDownload("navbar")}
            className="rounded-md font-bold relative cursor-pointer hover:-translate-y-0.5 transition duration-200 inline-block text-center bg-gradient-to-b from-primary to-primary/80 text-primary-foreground shadow-[0px_2px_0px_0px_rgba(255,255,255,0.3)_inset] px-4 py-2 text-sm"
          >
            Download
          </a>
        </div>
      </header>

      {/* Mobile Header */}
      <header className="sticky top-4 z-[9999] mx-4 flex w-auto flex-row items-center justify-between rounded-full bg-background/80 backdrop-blur-sm border border-border/50 shadow-lg md:hidden px-4 py-3">
        <a
          className="flex items-center justify-center gap-2"
          href="/"
        >
          <img
            src="/icon.png"
            alt="Better Shot"
            className="w-8 h-8"
          />
        </a>

        <button
          onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
          className="flex items-center justify-center w-10 h-10 rounded-full bg-background/50 border border-border/50 transition-colors hover:bg-background/80"
          aria-label="Toggle menu"
        >
          <div className="flex flex-col items-center justify-center w-5 h-5 space-y-1">
            <span
              className={`block w-4 h-0.5 bg-foreground transition-all duration-300 ${isMobileMenuOpen ? "rotate-45 translate-y-1.5" : ""}`}
            ></span>
            <span
              className={`block w-4 h-0.5 bg-foreground transition-all duration-300 ${isMobileMenuOpen ? "opacity-0" : ""}`}
            ></span>
            <span
              className={`block w-4 h-0.5 bg-foreground transition-all duration-300 ${isMobileMenuOpen ? "-rotate-45 -translate-y-1.5" : ""}`}
            ></span>
          </div>
        </button>
      </header>

      {/* Mobile Menu Overlay */}
      {isMobileMenuOpen && (
        <div className="fixed inset-0 z-[9998] bg-black/50 backdrop-blur-sm md:hidden">
          <div className="absolute top-20 left-4 right-4 bg-background/95 backdrop-blur-md border border-border/50 rounded-2xl shadow-2xl p-6 z-[9999]">
            <nav className="flex flex-col space-y-4">
              <button
                onClick={() => handleMobileNavClick("features")}
                className="text-left px-4 py-3 text-lg font-medium text-muted-foreground hover:text-foreground transition-colors rounded-lg hover:bg-background/50"
              >
                Features
              </button>
              <button
                onClick={() => handleMobileNavClick("faq")}
                className="text-left px-4 py-3 text-lg font-medium text-muted-foreground hover:text-foreground transition-colors rounded-lg hover:bg-background/50"
              >
                FAQ
              </button>
              <div className="border-t border-border/50 pt-4 mt-4 flex flex-col space-y-3">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Link
                      href="https://github.com/KartikLabhshetwar/better-shot"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg bg-[#2a2a2a] border border-[#3a3a3a] text-[#e5e5e5] hover:text-white transition-colors text-base font-medium"
                    >
                      <Star className="h-5 w-5 fill-yellow-400 text-yellow-400" />
                      {starCount > 0 ? (
                        <span className="tabular-nums text-[#e5e5e5]">{starCount.toLocaleString()}</span>
                      ) : (
                        <span className="text-[#e5e5e5]">Star us on GitHub</span>
                      )}
                    </Link>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>Star us on GitHub</p>
                  </TooltipContent>
                </Tooltip>
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/releases/latest"
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={() => trackDownload("mobile-menu")}
                  className="px-4 py-3 text-lg font-bold text-center bg-gradient-to-b from-primary to-primary/80 text-primary-foreground rounded-lg shadow-lg hover:-translate-y-0.5 transition-all duration-200"
                >
                  Download
                </a>
              </div>
            </nav>
          </div>
        </div>
      )}

      {/* Hero Section */}
      <Hero />

      {/* Features Section */}
      <div id="features">
        <Features />
      </div>

      {/* Testimonials Section - Hidden for now */}
      {/* <div id="testimonials">
        <TestimonialsSection />
      </div> */}

      <NewReleasePromo />

      {/* FAQ Section */}
      <div id="faq">
        <FAQSection />
      </div>

      {/* Sticky Footer */}
      <StickyFooter />
    </div>
  )
}
