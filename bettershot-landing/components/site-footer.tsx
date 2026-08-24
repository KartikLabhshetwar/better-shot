import Image from "next/image"
import Link from "next/link"

const columns = [
  {
    title: "Product",
    links: [
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
        label: "vs CleanShot X, CapCut & Loom",
      },
      { href: "/llms.txt", label: "llms.txt" },
    ],
  },
  {
    title: "More",
    links: [
      { href: "https://github.com/KartikLabhshetwar/better-shot", label: "GitHub", external: true },
      {
        href: "https://github.com/KartikLabhshetwar/better-shot/issues",
        label: "Report an issue",
        external: true,
      },
      { href: "https://x.com/code_kartik", label: "Twitter", external: true },
      { href: "/privacy", label: "Privacy" },
    ],
  },
]

export function SiteFooter() {
  return (
    <footer className="border-t border-ink/[0.06] bg-ink/[0.015]">
      <div className="max-w-[1080px] mx-auto px-5 sm:px-6 py-14">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-10">
          <div className="col-span-2 md:col-span-1">
            <div className="flex items-center gap-2.5 mb-3">
              <Image src="/logo.png" alt="" width={20} height={20} className="rounded-[4px]" />
              <span className="text-[13px] font-semibold text-ink/70">Better Shot</span>
            </div>
            <p className="text-[12.5px] leading-[1.7] text-ink/40 max-w-[240px]">
              Free, open-source screenshot and screen recording app for macOS. Local-first, no
              account, no subscription.
            </p>
          </div>

          {columns.map((column) => (
            <div key={column.title}>
              <p className="text-[11px] font-semibold uppercase tracking-wider text-ink/30 mb-3.5">
                {column.title}
              </p>
              <ul className="space-y-2.5">
                {column.links.map((link) => (
                  <li key={link.href}>
                    {"external" in link && link.external ? (
                      <a
                        href={link.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[12.5px] text-ink/45 hover:text-ink/80 transition-colors"
                      >
                        {link.label}
                      </a>
                    ) : (
                      <Link
                        href={link.href}
                        className="text-[12.5px] text-ink/45 hover:text-ink/80 transition-colors"
                      >
                        {link.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 pt-6 border-t border-ink/[0.06] flex flex-col sm:flex-row items-center justify-between gap-3">
          <p className="text-[11.5px] text-ink/30">
            &copy; {new Date().getFullYear()} Better Shot. BSD 3-Clause licensed.
          </p>
          <p className="text-[11.5px] text-ink/30">
            Built by{" "}
            <a
              href="https://x.com/code_kartik"
              target="_blank"
              rel="noopener noreferrer"
              className="text-ink/45 hover:text-ink/80 transition-colors"
            >
              Kartik Labhshetwar
            </a>
          </p>
        </div>
      </div>
    </footer>
  )
}
