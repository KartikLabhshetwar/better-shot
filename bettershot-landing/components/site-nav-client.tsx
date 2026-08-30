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
        className="fixed top-0 z-50 w-full border-b border-zinc-200 bg-white/80 backdrop-blur-xl"
      >
        <div className="mx-auto flex h-14 max-w-[1100px] items-center gap-6 px-6">
          <Link
            href="/"
            aria-current={pathname === "/" ? "page" : undefined}
            className="mr-auto flex shrink-0 items-center gap-2.5 outline-none"
          >
            <Image src="/logo.png" alt="Better Shot" width={24} height={24} className="rounded-md" />
            <span className="text-[18px] font-semibold tracking-tight text-zinc-900">Better Shot</span>
          </Link>

          <div className="hidden items-center gap-6 sm:flex">
            {links.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                aria-current={isCurrent(link.href) ? "page" : undefined}
                className={cn(
                  "text-[13px] font-medium outline-none transition-colors duration-150",
                  isCurrent(link.href) ? "text-zinc-900" : "text-zinc-500 hover:text-zinc-900",
                )}
              >
                {link.label}
              </Link>
            ))}
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 text-[13px] font-medium text-zinc-500 outline-none transition-colors duration-150 hover:text-zinc-900"
            >
              <GithubLogoIcon size={15} weight="bold" />
              <StarCount />
            </a>
          </div>

          <DownloadDropdown
            release={release}
            source="navbar"
            size="sm"
            label="Download"
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
                "absolute left-1/2 top-1/2 h-0.5 w-5 -translate-x-1/2 rounded-full bg-zinc-900 transition-transform duration-300",
                open ? "translate-y-0 rotate-45" : "-translate-y-1",
              )}
            />
            <span
              className={cn(
                "absolute left-1/2 top-1/2 h-0.5 w-5 -translate-x-1/2 rounded-full bg-zinc-900 transition-transform duration-300",
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
          "fixed inset-0 z-40 flex flex-col justify-center gap-4 bg-white px-6 transition-opacity duration-300 sm:hidden",
          open ? "opacity-100" : "pointer-events-none opacity-0",
        )}
      >
        {links.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            aria-current={isCurrent(link.href) ? "page" : undefined}
            className={cn(
              "border-t border-zinc-200 pt-4 text-[28px] font-semibold tracking-tight outline-none",
              isCurrent(link.href) ? "text-brand" : "text-zinc-900",
            )}
          >
            {link.label}
          </Link>
        ))}
        <a
          href="https://github.com/KartikLabhshetwar/better-shot"
          target="_blank"
          rel="noopener noreferrer"
          className="mt-4 inline-flex w-max items-center gap-2 text-[15px] font-medium text-zinc-500 outline-none"
        >
          <GithubLogoIcon size={18} weight="bold" />
          <StarCount />
        </a>
      </div>
    </>
  )
}
