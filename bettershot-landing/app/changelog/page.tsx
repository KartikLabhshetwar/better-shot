import type { Metadata } from "next"
import { Download } from "lucide-react"
import { getChangelog } from "@/lib/changelog"
import { MarkdownText } from "@/components/markdown-text"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"

export const metadata: Metadata = {
  title: "Changelog | Better Shot for macOS",
  description:
    "Every release of Better Shot, the free open-source screenshot and screen recording app for macOS. New features, changes, and fixes, version by version.",
  alternates: { canonical: "/changelog" },
  openGraph: {
    title: "Changelog | Better Shot for macOS",
    description: "New features, changes, and fixes in every version of Better Shot.",
    url: "https://bettershot.site/changelog",
    type: "website",
  },
}

const sectionStyles: Record<string, string> = {
  Added: "text-emerald-700 bg-emerald-500/10",
  Changed: "text-amber-700 bg-amber-500/10",
  Fixed: "text-blue-700 bg-blue-500/10",
  Removed: "text-rose-700 bg-rose-500/10",
  Credits: "text-violet-700 bg-violet-500/10",
  "Known limitations": "text-ink/50 bg-ink/[0.06]",
}

function anchor(version: string) {
  return `v${version.replace(/\./g, "-")}`
}

export default function ChangelogPage() {
  const changelog = getChangelog()

  return (
    <div className="min-h-screen w-full bg-canvas text-ink selection:bg-brand/20">
      <SiteNav />

      <main className="pt-14">
        <section className="max-w-[860px] mx-auto px-5 sm:px-6 pt-20 pb-10">
          <p className="inline-flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-brand mb-4">
            <span className="h-1 w-1 rounded-full bg-brand" />
            Changelog
          </p>
          <h1 className="text-[34px] sm:text-[44px] font-bold tracking-[-0.035em] text-ink leading-[1.1] mb-4">
            What&apos;s new in Better Shot
          </h1>
          <p className="text-[16px] leading-[1.7] text-ink/45 max-w-[520px]">
            Every feature, change, and fix, version by version. Updates install from inside the app,
            or run <code className="font-mono text-[14px] text-ink/60">brew upgrade --cask bettershot</code>.
          </p>
        </section>

        <div className="max-w-[860px] mx-auto px-5 sm:px-6 pb-28">
          {changelog.map((version, versionIndex) => (
            <article
              key={version.version}
              id={anchor(version.version)}
              className="scroll-mt-20 border-t border-ink/[0.07] py-12 first:border-t-0 first:pt-0"
            >
              <div className="md:grid md:grid-cols-[168px_1fr] md:gap-10">
                <div className="md:sticky md:top-20 md:self-start mb-6 md:mb-0">
                  <div className="flex items-center gap-2.5 flex-wrap">
                    <a
                      href={`#${anchor(version.version)}`}
                      className="text-[20px] font-bold tracking-[-0.02em] text-ink hover:text-brand transition-colors"
                    >
                      v{version.version}
                    </a>
                    {versionIndex === 0 && (
                      <span className="inline-flex items-center h-[19px] px-2 rounded-full bg-brand/15 text-[10px] font-semibold text-brand tracking-wide">
                        Latest
                      </span>
                    )}
                  </div>
                  <time className="block text-[12px] text-ink/35 font-mono mt-1">
                    {version.date}
                  </time>
                  <a
                    href={`https://github.com/KartikLabhshetwar/better-shot/releases/tag/v${version.version}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1.5 text-[12px] text-ink/35 hover:text-ink/70 transition-colors mt-3"
                  >
                    <Download className="h-3 w-3" />
                    Release
                  </a>
                </div>

                <div className="min-w-0">
                  {version.summary && (
                    <p className="text-[15px] leading-[1.75] text-ink/55 mb-8 pb-8 border-b border-ink/[0.06]">
                      <MarkdownText>{version.summary}</MarkdownText>
                    </p>
                  )}

                  <div className="space-y-8">
                    {version.sections.map((section) => (
                      <div key={section.label}>
                        <span
                          className={`inline-flex items-center h-[22px] px-2.5 rounded-md text-[11px] font-semibold tracking-wide mb-4 ${
                            sectionStyles[section.label] ?? "text-ink/50 bg-ink/[0.06]"
                          }`}
                        >
                          {section.label}
                        </span>
                        <ul className="space-y-3">
                          {section.items.map((item, i) => (
                            <li key={i} className="flex items-start gap-3">
                              <span className="mt-[9px] h-1 w-1 rounded-full bg-ink/20 shrink-0" />
                              <span className="text-[14px] leading-[1.75] text-ink/50">
                                <MarkdownText>{item}</MarkdownText>
                              </span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </article>
          ))}
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}
