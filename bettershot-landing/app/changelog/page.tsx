import type { Metadata } from "next"
import { getChangelog } from "@/lib/changelog"
import { MarkdownText } from "@/components/markdown-text"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"

export const metadata: Metadata = {
  title: "Changelog | Better Shot for macOS",
  description:
    "Every release of Better Shot, the free open source alternative to Loom and CleanShot X for macOS. New features, changes, and fixes, version by version.",
  alternates: { canonical: "/changelog" },
  openGraph: {
    title: "Changelog | Better Shot for macOS",
    description: "New features, changes, and fixes in every version of Better Shot.",
    url: "https://bettershot.site/changelog",
    type: "website",
  },
}

function anchor(version: string) {
  return `v${version.replace(/\./g, "-")}`
}

export default function ChangelogPage() {
  const changelog = getChangelog()

  return (
    <div className="min-h-screen w-full bg-white text-zinc-900">
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[680px] px-6">
          <header className="pb-10 pt-28 sm:pt-36">
            <h1 className="text-[clamp(2rem,5vw,3rem)] leading-[1.1] tracking-tight">
              Changelog
            </h1>
            <p className="mt-3 text-[17px] leading-relaxed text-zinc-400">
              We ship when it is ready.
            </p>
            <div className="mt-5">
              <a
                href="https://x.com/bettershotsite"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 rounded-lg border border-zinc-200 px-3 py-1.5 text-[13px] text-zinc-500 transition-colors hover:border-zinc-400 hover:text-zinc-900"
              >
                <svg viewBox="0 0 24 24" className="size-3.5 fill-current" aria-hidden>
                  <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                </svg>
                Follow for updates
              </a>
            </div>
          </header>

          <div className="space-y-0">
            {changelog.map((version) => {
              let labelShown = false
              return (
              <section
                key={version.version}
                id={anchor(version.version)}
                className="scroll-mt-20"
              >
                {version.sections.map((section) =>
                  section.items.map((item, itemIndex) => {
                    const match = item.match(/^\*\*(.+?)\*\*\s*[:.]?\s*(.*)$/)
                    const title = match ? match[1] : item
                    const detail = match ? match[2] : ""
                    const showLabel = !labelShown
                    if (showLabel) labelShown = true

                    return (
                      <div
                        key={`${version.version}-${section.label}-${itemIndex}`}
                        className="grid gap-x-10 border-t border-zinc-100 py-6 sm:grid-cols-[120px_minmax(0,1fr)]"
                      >
                        <div className="mb-2 sm:mb-0 sm:pt-0.5">
                          {showLabel && (
                            <>
                              <p className="text-[13px] font-medium tabular-nums text-zinc-900">
                                v{version.version}
                              </p>
                              <p className="text-[12px] tabular-nums text-zinc-400">
                                {version.date.toUpperCase()}
                              </p>
                            </>
                          )}
                        </div>
                        <div>
                          <h3 className="text-[15px] font-medium leading-[26px] text-zinc-900">
                            {title}
                          </h3>
                          {detail && (
                            <p className="mt-1.5 text-[15px] leading-[26px] text-zinc-500">
                              <MarkdownText>{detail}</MarkdownText>
                            </p>
                          )}
                        </div>
                      </div>
                    )
                  }),
                )}
              </section>
              )
            })}
          </div>

          <div className="border-t border-zinc-100 py-10">
            <p className="text-[14px] text-zinc-400">
              Full release notes on{" "}
              <a
                href="https://github.com/KartikLabhshetwar/better-shot/releases"
                target="_blank"
                rel="noopener noreferrer"
                className="text-brand-700 underline underline-offset-2 transition-colors hover:text-brand"
              >
                GitHub Releases
              </a>
              .
            </p>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}
