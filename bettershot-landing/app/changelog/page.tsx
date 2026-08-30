import type { Metadata } from "next"
import { getChangelog } from "@/lib/changelog"
import { MarkdownText } from "@/components/markdown-text"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"

export const metadata: Metadata = {
  title: "Changelog | Better Shot for macOS",
  description:
    "Every release of Better Shot, the free open source screenshot and screen recording app for macOS. New features, changes, and fixes, version by version.",
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

function splitItem(item: string) {
  const match = item.match(/^\*\*(.+?)\*\*\s*[:.]?\s*(.*)$/)
  if (!match) return { lead: "", text: item }
  return { lead: match[1], text: match[2] }
}

export default function ChangelogPage() {
  const changelog = getChangelog()

  return (
    <div className="min-h-screen w-full bg-white text-zinc-900">
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[1100px] px-6">
          <header className="pb-12 pt-28 sm:pt-32">
            <span className="text-[13px] font-medium uppercase tracking-widest text-zinc-400">
              Changelog
            </span>
            <h1 className="mt-4 text-[clamp(38px,5.4vw,60px)] font-extrabold tracking-tight">
              What&#8217;s new in Better Shot
            </h1>
            <p className="mt-6 max-w-[56ch] text-[17px] leading-[28px] text-zinc-600">
              Every feature, change, and fix, version by version. Updates install from inside the
              app, or run <code className="font-mono text-[15px]">brew upgrade --cask bettershot</code>.
            </p>
          </header>

          <div className="h-px bg-zinc-200" />

          <div className="grid items-start gap-x-[clamp(24px,5vw,80px)] lg:grid-cols-[180px_minmax(0,1fr)]">
            <nav
              aria-label="Releases"
              className="hidden gap-2.5 py-12 lg:sticky lg:top-20 lg:grid"
            >
              <p className="mb-1.5 text-[13px] font-medium uppercase tracking-widest text-zinc-400">
                Releases
              </p>
              {changelog.map((version) => (
                <a
                  key={version.version}
                  href={`#${anchor(version.version)}`}
                  className="text-[14px] tabular-nums text-zinc-900 outline-none transition-colors duration-150 hover:text-brand-700"
                >
                  v{version.version}
                </a>
              ))}
            </nav>

            <div className="lg:border-l lg:border-zinc-200 lg:pl-[clamp(20px,4vw,56px)]">
              {changelog.map((version, versionIndex) => (
                <section
                  key={version.version}
                  id={anchor(version.version)}
                  className="scroll-mt-20 border-b border-zinc-200 py-12"
                >
                  <div className="flex flex-wrap items-baseline gap-x-4 gap-y-3">
                    <h2 className="text-[34px] font-extrabold tracking-tight tabular-nums">v{version.version}</h2>
                    {versionIndex === 0 && (
                      <span className="inline-flex items-center rounded-full bg-brand-100 px-2.5 py-[3px] text-[11px] tracking-[0.02em] text-brand-800">
                        Latest
                      </span>
                    )}
                    <span className="text-[13px] uppercase tabular-nums text-zinc-400">
                      {version.date}
                    </span>
                    <a
                      href={`https://github.com/KartikLabhshetwar/better-shot/releases/tag/v${version.version}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-[13px] font-medium text-brand outline-none transition-colors duration-150 hover:text-brand-700"
                    >
                      Release notes
                    </a>
                  </div>

                  {version.summary && (
                    <p className="mt-5 max-w-[62ch] text-[17px] leading-[28px] text-zinc-600">
                      <MarkdownText>{version.summary}</MarkdownText>
                    </p>
                  )}

                  {version.sections.map((section) => (
                    <div key={section.label} className="mt-9">
                      <h3 className="mb-4 text-[13px] font-medium uppercase tracking-widest text-zinc-400">
                        {section.label}
                      </h3>
                      <ul>
                        {section.items.map((item, i) => {
                          const { lead, text } = splitItem(item)
                          return (
                            <li
                              key={i}
                              className="grid gap-x-8 gap-y-1.5 border-t border-zinc-200 py-3.5 sm:grid-cols-[minmax(0,240px)_minmax(0,1fr)]"
                            >
                              {lead && (
                                <span className="text-[15px] font-semibold leading-[24px]">
                                  {lead}
                                </span>
                              )}
                              <span
                                className={`text-[15px] leading-[24px] text-zinc-600 ${lead ? "" : "sm:col-span-2"}`}
                              >
                                <MarkdownText>{text}</MarkdownText>
                              </span>
                            </li>
                          )
                        })}
                      </ul>
                    </div>
                  ))}
                </section>
              ))}
            </div>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}
