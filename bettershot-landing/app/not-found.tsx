import Link from "next/link"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"

const links = [
  { href: "/changelog", label: "Changelog", external: false },
  { href: "/blog", label: "Blog", external: false },
  { href: "/#faq", label: "Questions about pricing and privacy", external: false },
  {
    href: "https://github.com/KartikLabhshetwar/better-shot/issues",
    label: "Report a broken link",
    external: true,
  },
]

export default function NotFound() {
  return (
    <div className="flex min-h-screen w-full flex-col bg-canvas text-ink">
      <SiteNav />

      <main id="main" className="flex-1">
        <div className="mx-auto max-w-[1240px] px-6">
          <section className="grid items-center gap-10 pb-[88px] pt-24 lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)] lg:gap-x-[clamp(24px,5vw,80px)]">
            <p className="-ml-[0.045em] text-[clamp(90px,14vw,200px)] font-extrabold leading-[0.88] tracking-[-0.04em] tabular-nums text-brand">
              404
            </p>
            <div>
              <h1 className="display-sm max-w-[22ch] text-[clamp(30px,3.6vw,46px)]">
                This one got cropped out.
              </h1>
              <p className="mt-6 max-w-[48ch] text-[17px] leading-[28px] text-ink/80">
                The page you asked for is not here. The rest of the site is.
              </p>
              <div className="mt-8 flex flex-wrap gap-3">
                <Link
                  href="/"
                  className="inline-flex items-center bg-brand px-5 py-3 text-[15px] font-semibold text-canvas outline-none transition-colors duration-150 hover:bg-brand-600 active:bg-brand-700"
                >
                  Back to the start
                </Link>
                <Link
                  href="/download"
                  className="inline-flex items-center border-2 border-rule px-5 py-3 text-[15px] font-semibold text-ink outline-none transition-colors duration-150 hover:border-ink"
                >
                  Download Better Shot
                </Link>
              </div>
              <ul className="mt-10 grid max-w-[420px] gap-0.5 bg-rule">
                {links.map((link) => (
                  <li key={link.href} className="bg-canvas py-3.5">
                    {link.external ? (
                      <a
                        href={link.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[15px] text-ink outline-none transition-colors duration-150 hover:text-brand-700"
                      >
                        {link.label}
                      </a>
                    ) : (
                      <Link
                        href={link.href}
                        className="text-[15px] text-ink outline-none transition-colors duration-150 hover:text-brand-700"
                      >
                        {link.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          </section>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}
