"use client"

import { useEffect, useState } from "react"
import Image from "next/image"
import Link from "next/link"
import { usePathname } from "next/navigation"
import { GithubLogoIcon } from "@phosphor-icons/react/dist/ssr"
import { DownloadDropdown } from "@/components/download-dropdown"
import { StarCount } from "@/components/star-count"
import type { ReleaseInfo } from "@/lib/downloads"
import { cn } from "@/lib/utils"

const links = [
  { href: "/download", label: "Download" },
  { href: "/changelog", label: "Changelog" },
  { href: "/blog", label: "Blog" },
]

export function SiteNavClient({ release }: { release: ReleaseInfo }) {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)

  useEffect(() => setOpen(false), [pathname])

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : ""
    return () => {
      document.body.style.overflow = ""
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false)
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open])

  const isCurrent = (href: string) => pathname === href || pathname.startsWith(`${href}/`)

  return (
    <>
      <nav
        aria-label="Main"
        className="sticky top-0 z-50 border-b-2 border-rule bg-canvas"
      >
        <div className="mx-auto flex h-[62px] max-w-[1240px] items-center gap-7 px-6">
          <Link
            href="/"
            aria-current={pathname === "/" ? "page" : undefined}
            className="mr-auto flex shrink-0 items-center gap-2.5 outline-none"
          >
            <Image src="/logo.png" alt="Better Shot" width={24} height={24} />
            <span className="text-[18px] font-extrabold tracking-tight text-ink">Better Shot</span>
          </Link>

          <div className="hidden items-center gap-7 sm:flex">
            {links.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                aria-current={isCurrent(link.href) ? "page" : undefined}
                className={cn(
                  "text-[14px] font-semibold outline-none transition-colors duration-150",
                  isCurrent(link.href) ? "text-brand-700" : "text-ink/70 hover:text-ink",
                )}
              >
                {link.label}
              </Link>
            ))}
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 text-[14px] font-semibold text-ink/70 outline-none transition-colors duration-150 hover:text-ink"
            >
              <GithubLogoIcon size={16} weight="bold" />
              <StarCount />
            </a>
          </div>

          <DownloadDropdown
            release={release}
            source="navbar"
            size="sm"
            label="Download for macOS"
            className="hidden sm:inline-flex"
          />

          <button
            type="button"
            onClick={() => setOpen((value) => !value)}
            aria-expanded={open}
            aria-controls="mobile-menu"
            aria-label={open ? "Close menu" : "Open menu"}
            className="relative -mr-2 h-10 w-10 shrink-0 outline-none sm:hidden"
          >
            <span
              className={cn(
                "absolute left-1/2 top-1/2 h-0.5 w-5 -translate-x-1/2 bg-ink transition-transform duration-300",
                open ? "translate-y-0 rotate-45" : "-translate-y-1",
              )}
            />
            <span
              className={cn(
                "absolute left-1/2 top-1/2 h-0.5 w-5 -translate-x-1/2 bg-ink transition-transform duration-300",
                open ? "translate-y-0 -rotate-45" : "translate-y-1",
              )}
            />
          </button>
        </div>
      </nav>

      <div
        id="mobile-menu"
        inert={!open}
        aria-hidden={!open}
        className={cn(
          "fixed inset-0 z-40 flex flex-col justify-center gap-3 bg-canvas px-6 transition-opacity duration-300 sm:hidden",
          open ? "opacity-100" : "pointer-events-none opacity-0",
        )}
      >
        {links.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            aria-current={isCurrent(link.href) ? "page" : undefined}
            className={cn(
              "border-t-2 border-rule pt-3 text-[34px] font-extrabold tracking-tight outline-none",
              isCurrent(link.href) ? "text-brand-700" : "text-ink",
            )}
          >
            {link.label}
          </Link>
        ))}
        <a
          href="https://github.com/KartikLabhshetwar/better-shot"
          target="_blank"
          rel="noopener noreferrer"
          className="mt-4 inline-flex w-max items-center gap-2 text-[15px] font-semibold text-ink/70 outline-none"
        >
          <GithubLogoIcon size={20} weight="bold" />
          <StarCount />
        </a>
      </div>
    </>
  )
}
