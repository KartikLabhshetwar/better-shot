import Image from "next/image"
import Link from "next/link"

const columns = [
  {
    title: "Product",
    links: [
      { href: "/download", label: "Download" },
      { href: "/#features", label: "Features" },
      { href: "/#compare", label: "Compare" },
      { href: "/#faq", label: "FAQ" },
      { href: "/changelog", label: "Changelog" },
    ],
  },
  {
    title: "Learn",
    links: [
      { href: "/blog", label: "Blog" },
      {
        href: "/blog/cleanshot-x-capcut-loom-alternative",
        label: "vs CleanShot X, CapCut, Loom",
      },
      {
        href: "https://github.com/KartikLabhshetwar/better-shot",
        label: "GitHub",
        external: true,
      },
      { href: "/llms.txt", label: "llms.txt" },
    ],
  },
  {
    title: "Legal",
    links: [
      { href: "/privacy", label: "Privacy" },
      { href: "/terms", label: "Terms" },
      {
        href: "https://github.com/KartikLabhshetwar/better-shot/blob/main/LICENSE",
        label: "BSD 3 Clause license",
        external: true,
      },
      {
        href: "https://github.com/KartikLabhshetwar/better-shot/issues",
        label: "Report an issue",
        external: true,
      },
    ],
  },
]

const linkClass = "text-[14px] text-ink/70 outline-none transition-colors duration-150 hover:text-ink"

export function SiteFooter() {
  return (
    <footer className="bg-canvas">
      <div className="mx-auto max-w-[1240px] px-6">
        <hr className="rule" />
        <div className="grid grid-cols-2 gap-10 py-14 md:grid-cols-[minmax(0,2fr)_repeat(3,minmax(0,1fr))]">
          <div className="col-span-2 md:col-span-1">
            <div className="mb-4 flex items-center gap-2.5">
              <Image src="/logo.png" alt="" width={24} height={24} />
              <span className="text-[18px] font-extrabold tracking-tight text-ink">Better Shot</span>
            </div>
            <p className="max-w-[280px] text-[14px] leading-[24px] text-ink/70">
              Free, open source screen capture for macOS. Local first, no account, no subscription.
            </p>
            <p className="mt-8 text-[13px] leading-[22px] text-ink/55">
              &copy; {new Date().getFullYear()} Better Shot. BSD 3 Clause licensed. Built by{" "}
              <a
                href="https://x.com/code_kartik"
                target="_blank"
                rel="noopener noreferrer"
                className="text-ink/70 underline underline-offset-2 outline-none transition-colors duration-150 hover:text-ink"
              >
                Kartik Labhshetwar
              </a>
            </p>
          </div>

          {columns.map((column) => (
            <nav key={column.title} aria-label={column.title}>
              <p className="micro mb-5 text-[13px] font-extrabold uppercase text-ink">
                {column.title}
              </p>
              <ul className="space-y-3">
                {column.links.map((link) => (
                  <li key={link.href}>
                    {"external" in link && link.external ? (
                      <a
                        href={link.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className={linkClass}
                      >
                        {link.label}
                      </a>
                    ) : (
                      <Link href={link.href} className={linkClass}>
                        {link.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
      </div>
    </footer>
  )
}
