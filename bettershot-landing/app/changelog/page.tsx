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
    <div className="min-h-screen w-full bg-canvas text-ink">
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[1240px] px-6">
          <header className="pb-12 pt-[72px]">
            <span className="micro block text-[13px] font-extrabold uppercase text-brand-700">
              Changelog
            </span>
            <h1 className="display mt-3.5 -ml-[0.058em] text-[clamp(38px,5.4vw,72px)]">
              What&#8217;s new in Better Shot
            </h1>
            <p className="mt-6 max-w-[56ch] text-[17px] leading-[28px] text-ink/80">
              Every feature, change, and fix, version by version. Updates install from inside the
              app, or run <code className="font-mono text-[15px]">brew upgrade --cask bettershot</code>.
            </p>
          </header>

          <hr className="rule" />

          <div className="grid items-start gap-x-[clamp(24px,5vw,80px)] lg:grid-cols-[180px_minmax(0,1fr)]">
            <nav
              aria-label="Releases"
              className="hidden gap-2.5 py-12 lg:sticky lg:top-20 lg:grid"
            >
              <p className="micro mb-1.5 text-[13px] font-extrabold uppercase text-ink/70">
                Releases
              </p>
              {changelog.map((version) => (
                <a
                  key={version.version}
                  href={`#${anchor(version.version)}`}
                  className="text-[14px] tabular-nums text-ink outline-none transition-colors duration-150 hover:text-brand-700"
                >
                  v{version.version}
                </a>
              ))}
            </nav>

            <div className="lg:border-l-2 lg:border-rule lg:pl-[clamp(20px,4vw,56px)]">
              {changelog.map((version, versionIndex) => (
                <section
                  key={version.version}
                  id={anchor(version.version)}
                  className="scroll-mt-20 border-b-2 border-rule py-12"
                >
                  <div className="flex flex-wrap items-baseline gap-x-4 gap-y-3">
                    <h2 className="display-sm text-[34px] tabular-nums">v{version.version}</h2>
                    {versionIndex === 0 && (
                      <span className="inline-flex items-center bg-brand-100 px-2.5 py-[3px] text-[11px] tracking-[0.02em] text-brand-800">
                        Latest
                      </span>
                    )}
                    <span className="micro text-[13px] uppercase tabular-nums text-ink/70">
                      {version.date}
                    </span>
                    <a
                      href={`https://github.com/KartikLabhshetwar/better-shot/releases/tag/v${version.version}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="micro text-[13px] uppercase text-brand-700 outline-none transition-colors duration-150 hover:text-brand"
                    >
                      Release notes
                    </a>
                  </div>

                  {version.summary && (
                    <p className="mt-5 max-w-[62ch] text-[17px] leading-[28px] text-ink/80">
                      <MarkdownText>{version.summary}</MarkdownText>
                    </p>
                  )}

                  {version.sections.map((section) => (
                    <div key={section.label} className="mt-9">
                      <h3 className="micro mb-4 text-[13px] font-extrabold uppercase tracking-[0.1em] text-brand-700">
                        {section.label}
                      </h3>
                      <ul>
                        {section.items.map((item, i) => {
                          const { lead, text } = splitItem(item)
                          return (
                            <li
                              key={i}
                              className="grid gap-x-8 gap-y-1.5 border-t border-rule py-3.5 sm:grid-cols-[minmax(0,240px)_minmax(0,1fr)]"
                            >
                              {lead && (
                                <span className="text-[15px] font-semibold leading-[24px]">
                                  {lead}
                                </span>
                              )}
                              <span
                                className={`text-[15px] leading-[24px] text-ink/80 ${lead ? "" : "sm:col-span-2"}`}
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
