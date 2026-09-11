"use client"

import { useEffect, useState } from "react"
import Image from "next/image"
import Link from "next/link"
import { usePathname } from "next/navigation"
import * as Dialog from "@radix-ui/react-dialog"
import { Menu, X } from "lucide-react"
import { GitHubIcon } from "@/components/github-icon"
import { DownloadDropdown } from "@/components/download-dropdown"
import { StarCount } from "@/components/star-count"
import type { ReleaseInfo } from "@/lib/downloads"
import { cn } from "@/lib/utils"

const links = [
  { href: "/video-recording", label: "Video recording" },
  { href: "/screenshots", label: "Screenshots" },
  { href: "/download", label: "Download" },
  { href: "/changelog", label: "Changelog" },
  { href: "/blog", label: "Blog" },
]

export function SiteNavClient({ release }: { release: ReleaseInfo }) {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  useEffect(() => setOpen(false), [pathname])
  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 1024px)")
    const closeOnDesktop = () => { if (desktop.matches) setOpen(false) }
    desktop.addEventListener("change", closeOnDesktop)
    return () => desktop.removeEventListener("change", closeOnDesktop)
  }, [])
  const isCurrent = (href: string) => pathname === href || pathname.startsWith(`${href}/`)

  return <nav aria-label="Main" className="fixed top-0 z-50 w-full border-b border-zinc-200 bg-white/90 backdrop-blur-xl">
    <div className="mx-auto flex h-14 max-w-[1100px] items-center gap-6 px-6">
      <Link href="/" aria-current={pathname === "/" ? "page" : undefined} className="mr-auto flex shrink-0 items-center gap-2.5">
        <Image src="/logo.png" alt="" width={24} height={24} className="rounded-md" />
        <span className="text-[18px] font-semibold tracking-tight text-zinc-900">Better Shot</span>
      </Link>
      <div className="hidden items-center gap-6 lg:flex">
        {links.map(link => <Link key={link.href} href={link.href} aria-current={isCurrent(link.href) ? "page" : undefined}
          className={cn("whitespace-nowrap text-[13px] font-medium hover:text-brand", isCurrent(link.href) ? "text-brand" : "text-zinc-500")}>{link.label}</Link>)}
        <a href="https://github.com/KartikLabhshetwar/better-shot" target="_blank" rel="noopener noreferrer" aria-label="BetterShot on GitHub" className="inline-flex shrink-0 items-center gap-1.5 text-[13px] text-zinc-500 hover:text-zinc-900"><GitHubIcon className="size-4" /><StarCount /></a>
      </div>
      <DownloadDropdown release={release} source="navbar" size="sm" label="Download" className="hidden lg:inline-flex" />
      <Dialog.Root open={open} onOpenChange={setOpen}>
        <Dialog.Trigger className="-mr-2 flex size-11 items-center justify-center lg:hidden" aria-label="Open menu"><Menu size={23} aria-hidden /></Dialog.Trigger>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-50 bg-white" />
          <Dialog.Content aria-describedby={undefined} className="fixed inset-0 z-50 flex h-dvh flex-col gap-4 overflow-y-auto bg-white px-6 pt-24 pb-[max(2rem,env(safe-area-inset-bottom))]">
            <Dialog.Title className="sr-only">BetterShot navigation</Dialog.Title>
            <Dialog.Close aria-label="Close menu" className="absolute right-4 top-2 flex size-11 items-center justify-center"><X size={23} aria-hidden /></Dialog.Close>
            {links.map(link => <Dialog.Close asChild key={link.href}><Link href={link.href} aria-current={isCurrent(link.href) ? "page" : undefined}
              className={cn("border-t border-zinc-200 py-3 text-[28px] font-medium", isCurrent(link.href) ? "text-brand" : "text-zinc-900")}>{link.label}</Link></Dialog.Close>)}
            <div className="mt-4"><DownloadDropdown release={release} source="mobile-menu" size="default" /></div>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </div>
  </nav>
}
