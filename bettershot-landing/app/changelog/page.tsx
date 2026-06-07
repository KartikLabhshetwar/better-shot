import Image from "next/image"
import Link from "next/link"
import { getChangelog } from "@/lib/changelog"

export const metadata = {
  title: "Changelog — Better Shot",
  description: "What's new in Better Shot. Release notes for every version.",
}

export default function ChangelogPage() {
  const changelog = getChangelog()

  return (
    <div className="min-h-screen w-full bg-[#fafaf9] text-[#111] selection:bg-[#e78a53]/20">
      <nav className="fixed top-0 inset-x-0 z-50 h-14 backdrop-blur-xl bg-[#fafaf9]/80">
        <div className="max-w-[960px] mx-auto h-full px-6 flex items-center justify-between">
          <Link href="/" className="flex items-center gap-2.5">
            <Image src="/logo.png" alt="" width={22} height={22} className="rounded-[5px]" />
            <span className="text-[13px] font-medium tracking-[-0.01em] text-[#111]/50">
              Better Shot
            </span>
          </Link>
        </div>
      </nav>

      <main className="pt-14">
        <section className="max-w-[640px] mx-auto px-6 pt-24 pb-28">
          <h1 className="text-[28px] font-semibold tracking-[-0.02em] text-[#111] mb-2">
            Changelog
          </h1>
          <p className="text-[14px] text-[#111]/30 mb-14">
            What&apos;s new in every release of Better Shot.
          </p>

          <div className="space-y-10">
            {changelog.map((ver) => (
              <div key={ver.version}>
                <div className="flex items-baseline justify-between mb-4 pb-3 border-b border-[#111]/[0.06]">
                  <span className="text-[13px] font-semibold text-[#111]/60 tracking-[-0.01em]">
                    v{ver.version}
                  </span>
                  <span className="text-[11px] text-[#111]/25 font-mono">{ver.date}</span>
                </div>
                <div className="space-y-5">
                  {ver.sections.map((section) => (
                    <div key={section.label}>
                      <p className="text-[11px] font-medium text-[#111]/30 uppercase tracking-wide mb-2">
                        {section.label}
                      </p>
                      <ul className="space-y-1.5">
                        {section.items.map((item, i) => (
                          <li key={i} className="flex items-start gap-2.5">
                            <span className="mt-[7px] h-1 w-1 rounded-full bg-[#111]/15 shrink-0" />
                            <span className="text-[13px] leading-[1.6] text-[#111]/35">{item}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </section>
      </main>

      <footer className="border-t border-[#111]/[0.04]">
        <div className="max-w-[960px] mx-auto px-6 py-6 flex items-center justify-between">
          <p className="text-[11px] text-[#111]/15">
            &copy; {new Date().getFullYear()} Better Shot
          </p>
          <nav className="flex items-center gap-5">
            <Link
              href="/"
              className="text-[11px] text-[#111]/15 hover:text-[#111]/40 transition-colors"
            >
              Home
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  )
}
