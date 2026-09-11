"use client"

import { useEffect, useState } from "react"
import Image from "next/image"
import Link from "next/link"
import { usePathname } from "next/navigation"
import * as Dialog from "@radix-ui/react-dialog"
import { Camera, ChevronDown, FileClock, Menu, Video, X } from "lucide-react"
import { GitHubIcon } from "@/components/github-icon"
import { DownloadDropdown } from "@/components/download-dropdown"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { StarCount } from "@/components/star-count"
import type { ReleaseInfo } from "@/lib/downloads"
import { cn } from "@/lib/utils"

const products = [
  { href: "/screenshots", label: "Screenshots", icon: Camera },
  { href: "/video-recording", label: "Video recording", icon: Video },
  { href: "/changelog", label: "Changelog", icon: FileClock },
]

function ProductMenu({ pathname, onNavigate, className }: { pathname: string; onNavigate?: () => void; className?: string }) {
  const current = products.some(product => pathname === product.href || pathname.startsWith(`${product.href}/`))
  return <DropdownMenu>
    <DropdownMenuTrigger className={cn("inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-medium hover:bg-zinc-100 data-[state=open]:bg-zinc-100", current ? "text-brand" : "text-zinc-600", className)}>
      Product <ChevronDown className="size-4 text-zinc-400" aria-hidden />
    </DropdownMenuTrigger>
    <DropdownMenuContent align="start" sideOffset={12} collisionPadding={16}
      className="w-72 max-w-[calc(100vw-2rem)] rounded-2xl border-zinc-200 bg-white p-2 shadow-xl data-[state=open]:animate-none data-[state=closed]:animate-none">
      {products.map(({ href, label, icon: Icon }, index) => <div key={href}>
        {index === 2 && <DropdownMenuSeparator className="mx-2 my-2 bg-zinc-200" />}
        <DropdownMenuItem asChild onSelect={onNavigate} className="cursor-pointer gap-4 rounded-xl p-3 text-base focus:bg-zinc-100">
          <Link href={href} aria-current={pathname === href ? "page" : undefined} className={cn(pathname === href ? "text-brand" : "text-zinc-900")}>
            <span className="flex size-11 items-center justify-center rounded-xl border border-zinc-200 bg-white shadow-sm">
              <Icon className="size-5 text-brand" aria-hidden />
            </span>
            {label}
          </Link>
        </DropdownMenuItem>
      </div>)}
    </DropdownMenuContent>
  </DropdownMenu>
}

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
        <ProductMenu pathname={pathname} />
        <Link href="/blog" aria-current={isCurrent("/blog") ? "page" : undefined}
          className={cn("text-sm font-medium hover:text-brand", isCurrent("/blog") ? "text-brand" : "text-zinc-500")}>Blog</Link>
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
            <ProductMenu pathname={pathname} onNavigate={() => setOpen(false)} className="w-full justify-between py-3 text-2xl" />
            <Dialog.Close asChild><Link href="/blog" aria-current={isCurrent("/blog") ? "page" : undefined}
              className={cn("rounded-xl px-3 py-3 text-2xl font-medium", isCurrent("/blog") ? "text-brand" : "text-zinc-900")}>Blog</Link></Dialog.Close>
            <div className="mt-4"><DownloadDropdown release={release} source="mobile-menu" size="default" /></div>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </div>
  </nav>
}
