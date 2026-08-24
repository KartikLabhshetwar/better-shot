import Image from "next/image"
import Link from "next/link"
import { DownloadDropdown } from "@/components/download-dropdown"
import { StarCount } from "@/components/star-count"
import { getLatestRelease } from "@/lib/downloads"

const links = [
  { href: "/blog", label: "Blog" },
  { href: "/changelog", label: "Changelog" },
]

export async function SiteNav() {
  const release = await getLatestRelease()

  return (
    <nav className="fixed top-0 inset-x-0 z-50 h-14 backdrop-blur-xl bg-canvas/80 border-b border-ink/[0.05]">
      <div className="max-w-[1080px] mx-auto h-full px-5 sm:px-6 flex items-center justify-between gap-4">
        <Link href="/" className="flex items-center gap-2.5 shrink-0">
          <Image src="/logo.png" alt="Better Shot" width={22} height={22} className="rounded-[5px]" />
          <span className="text-[13px] font-semibold tracking-[-0.01em] text-ink/75">Better Shot</span>
        </Link>

        <div className="flex items-center gap-3.5 sm:gap-6">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-[12.5px] text-ink/45 hover:text-ink/80 transition-colors"
            >
              {link.label}
            </Link>
          ))}
          <a
            href="https://github.com/KartikLabhshetwar/better-shot"
            target="_blank"
            rel="noopener noreferrer"
            className="text-[12.5px] text-ink/45 hover:text-ink/80 transition-colors hidden sm:block"
          >
            <StarCount />
          </a>
          <DownloadDropdown release={release} source="navbar" size="sm" label="Download" />
        </div>
      </div>
    </nav>
  )
}
