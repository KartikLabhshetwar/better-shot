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
    <div className="flex min-h-screen w-full flex-col bg-white text-zinc-900">
      <SiteNav />

      <main id="main" className="flex-1">
        <div className="mx-auto max-w-[1100px] px-6">
          <section className="grid items-center gap-10 pb-[88px] pt-24 lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)] lg:gap-x-[clamp(24px,5vw,80px)]">
            <p className="-ml-[0.045em] text-[clamp(90px,14vw,200px)] font-semibold leading-[0.88] tracking-[-0.04em] tabular-nums text-brand">
              404
            </p>
            <div>
              <h1 className="max-w-[22ch] text-[clamp(30px,3.6vw,46px)] tracking-tight">
                This one got cropped out.
              </h1>
              <p className="mt-6 max-w-[48ch] text-[17px] leading-[28px] text-zinc-600">
                The page you asked for is not here. The rest of the site is.
              </p>
              <div className="mt-8 flex flex-wrap gap-3">
                <Link
                  href="/"
                  className="inline-flex items-center rounded-xl bg-brand px-5 py-3 text-[15px] font-semibold text-white outline-none transition-colors duration-150 hover:bg-brand-600 active:bg-brand-700"
                >
                  Back to the start
                </Link>
                <Link
                  href="/download"
                  className="inline-flex items-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-900 outline-none transition-colors duration-150 hover:border-zinc-400"
                >
                  Download Better Shot
                </Link>
              </div>
              <ul className="mt-10 max-w-[420px] divide-y divide-zinc-200 rounded-2xl border border-zinc-200">
                {links.map((link) => (
                  <li key={link.href} className="px-5 py-3.5">
                    {link.external ? (
                      <a
                        href={link.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[15px] text-zinc-600 outline-none transition-colors duration-150 hover:text-brand-700"
                      >
                        {link.label}
                      </a>
                    ) : (
                      <Link
                        href={link.href}
                        className="text-[15px] text-zinc-600 outline-none transition-colors duration-150 hover:text-brand-700"
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
