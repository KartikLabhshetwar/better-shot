import type { Metadata } from "next"
import Link from "next/link"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { formatPostDate, getPost } from "@/lib/blog"

const post = getPost("bettershot-0-5-2")!
const url = `https://bettershot.site/blog/${post.slug}`

export const metadata: Metadata = {
  title: `${post.title} | Better Shot`,
  description: post.description,
  keywords: post.keywords,
  alternates: { canonical: `/blog/${post.slug}` },
  openGraph: {
    type: "article",
    title: post.headline,
    description: post.description,
    url,
    siteName: "Better Shot",
    publishedTime: post.date,
    authors: ["Kartik Labhshetwar"],
    tags: post.keywords,
  },
  twitter: {
    card: "summary_large_image",
    title: post.headline,
    description: post.description,
    creator: "@code_kartik",
  },
}

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "BlogPosting",
      headline: post.headline,
      alternativeHeadline: post.title,
      description: post.description,
      keywords: post.keywords.join(", "),
      datePublished: post.date,
      dateModified: post.date,
      inLanguage: "en",
      mainEntityOfPage: { "@type": "WebPage", "@id": url },
      author: {
        "@type": "Person",
        name: "Kartik Labhshetwar",
        url: "https://x.com/code_kartik",
      },
      publisher: {
        "@type": "Organization",
        name: "Better Shot",
        url: "https://bettershot.site",
      },
    },
    {
      "@type": "BreadcrumbList",
      itemListElement: [
        { "@type": "ListItem", position: 1, name: "Home", item: "https://bettershot.site" },
        { "@type": "ListItem", position: 2, name: "Blog", item: "https://bettershot.site/blog" },
        { "@type": "ListItem", position: 3, name: post.headline, item: url },
      ],
    },
  ],
}

export default async function Article() {
  const release = await getLatestRelease()

  return (
    <div className="min-h-screen w-full bg-white text-zinc-900">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[1100px] px-6">
          <header className="mx-auto max-w-[680px] pb-10 pt-28 sm:pt-32">
            <span className="rounded-full bg-brand-100 px-3 py-1 text-[12px] font-medium text-brand-700">
              {post.tag}
            </span>
            <h1 className="mt-4 text-[clamp(34px,4.6vw,56px)] leading-[1.08] tracking-tight">
              {post.headline}
            </h1>
            <p className="mt-6 text-[13px] uppercase tracking-widest text-zinc-400">
              <time dateTime={post.date}>{formatPostDate(post.date)}</time> &middot; {post.readingTime}
            </p>
          </header>

          <div className="mx-auto max-w-[680px] border-t border-zinc-200" />

          <div>
            <article className="mx-auto max-w-[680px] pb-16 pt-12">
              <p className="mb-8 text-[19px] leading-[32px] text-zinc-600">
                BetterShot 0.5.2 ships today with a URL scheme for automation, 75 customizable
                keyboard shortcuts, three new capture features, and six community-contributed bug
                fixes. Every change in this release came from a GitHub issue or pull request.
              </p>

              <div className="mb-10 rounded-2xl border border-zinc-200 p-6">
                <p className="mb-4 text-[13px] font-semibold uppercase tracking-widest text-brand-700">
                  What&apos;s new
                </p>
                <ul>
                  <TldrItem>
                    <Strong>URL scheme:</Strong> trigger captures, recordings, OCR, and color picker
                    from Raycast, Shortcuts, Alfred, or shell scripts.
                  </TldrItem>
                  <TldrItem>
                    <Strong>75 shortcuts:</Strong> every action in the app is now bindable, searchable,
                    and conflict-checked.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Capture on release:</Strong> take the screenshot the moment you release the
                    mouse, matching the classic draw-and-release gesture.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Auto-save recordings:</Strong> finished recordings save to your folder
                    automatically. No more forgotten unsaved takes.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Six community fixes:</Strong> deck copy, save behavior, drawing cursor,
                    and more, all from contributor PRs.
                  </TldrItem>
                </ul>
              </div>

              <H2 id="url-scheme">URL scheme for automation</H2>
              <P>
                BetterShot now registers <Code>bettershot://</Code> URLs. You can trigger any
                capture action from outside the app without touching the menu bar or remembering a
                shortcut.
              </P>
              <List
                items={[
                  "bettershot://capture/region, bettershot://capture/fullscreen, bettershot://capture/window",
                  "bettershot://ocr, bettershot://color-picker",
                  "bettershot://record",
                  "bettershot://settings",
                ]}
              />
              <P>
                This means you can add a Raycast command, an Alfred workflow, or a Shortcuts
                action that opens a URL, and BetterShot handles the rest. Unknown or malformed URLs
                are silently ignored, and the recording guard prevents stacking on an active session.
              </P>

              <H2 id="shortcuts">75 customizable shortcuts</H2>
              <P>
                The shortcut system has been rebuilt. Every action in the app, across seven
                categories (general, screenshots, OCR and color, recording, capture deck, image
                tools, and video editing), is now listed in Settings &gt; Shortcuts with search,
                filtering, and per-scope conflict detection.
              </P>
              <P>
                Default bindings are preserved on upgrade. New actions start unassigned so they
                never collide with your existing setup. Editor shortcuts take priority over global
                ones when the editor is active, and text fields retain native typing behavior.
              </P>

              <H2 id="capture-on-release">Capture on mouse release</H2>
              <P>
                A new toggle in Settings &gt; Capture takes the screenshot as soon as you release
                the mouse button. This matches the draw-and-release gesture that many people expect
                from region capture. It is off by default; the adjustable rectangle remains the
                default behavior.
              </P>

              <H2 id="auto-save">Auto-save recordings</H2>
              <P>
                A new toggle in Settings &gt; Recording saves finished recordings to your configured
                save folder automatically. If you use the capture deck, Save on a recording card
                also writes to the folder using the flattened deliverable. No more closing the app
                and losing an unsaved take.
              </P>

              <H2 id="community-fixes">Community fixes</H2>
              <P>
                Six pull requests from the community landed in this release. Each one fixed a
                reported issue, included tests, and was reviewed before merge.
              </P>
              <div className="my-8 overflow-x-auto rounded-2xl border border-zinc-200">
                <table className="w-full min-w-[520px] border-collapse text-[14px]">
                  <thead>
                    <tr className="bg-zinc-50">
                      <th className="border-b border-zinc-200 px-3 py-2.5 text-left text-[12px] font-semibold uppercase tracking-widest text-zinc-400">Fix</th>
                      <th className="border-b border-zinc-200 px-3 py-2.5 text-left text-[12px] font-semibold uppercase tracking-widest text-zinc-400">Issue</th>
                      <th className="border-b border-zinc-200 px-3 py-2.5 text-left text-[12px] font-semibold uppercase tracking-widest text-zinc-400">PR</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      ["Drawing cursor matches active tool", "#129", "#130"],
                      ["Capture on mouse release", "#131", "#132"],
                      ["Deck Copy no longer saves to folder", "#134", "#138"],
                      ["URL scheme for automation", "#86", "#141"],
                      ["Save updates the exported file", "#127", "#142"],
                      ["Auto-save recordings", "#136", "#143"],
                    ].map(([fix, issue, pr]) => (
                      <tr key={fix} className="transition-colors hover:bg-zinc-50">
                        <td className="border-b border-zinc-100 px-3 py-2.5 font-medium">{fix}</td>
                        <td className="border-b border-zinc-100 px-3 py-2.5 text-zinc-600">
                          <a
                            href={`https://github.com/KartikLabhshetwar/better-shot/issues/${issue.slice(1)}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-brand-700 underline underline-offset-2 hover:text-brand"
                          >
                            {issue}
                          </a>
                        </td>
                        <td className="border-b border-zinc-100 px-3 py-2.5 text-zinc-600">
                          <a
                            href={`https://github.com/KartikLabhshetwar/better-shot/pull/${pr.slice(1)}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-brand-700 underline underline-offset-2 hover:text-brand"
                          >
                            {pr}
                          </a>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <P>
                Thanks to{" "}
                <a
                  href="https://github.com/zergzorg"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-700 underline underline-offset-2 hover:text-brand"
                >
                  @zergzorg
                </a>{" "}
                for all six contributions.
              </P>

              <H2 id="other-changes">Other changes in 0.5.2</H2>
              <List
                items={[
                  "Overlay settings with Standard, Sharing, and Minimal presets and a visual layout editor",
                  "Cloud sharing directly from the capture deck with progress and retry",
                  "Launch at Login, Show in Dock, and Show in Menu Bar startup controls",
                  "DMG installer with Retina background, clover volume icon, and aligned drag-to-Applications layout",
                  "Three-step onboarding: Welcome, Permissions, First Capture",
                  "Button contrast and editor shortcut handling fixes in both appearances",
                ]}
              />

              <H2 id="upgrading">Upgrading</H2>
              <P>
                If you already have BetterShot, check for updates from the app or run{" "}
                <Code>brew upgrade --cask bettershot</Code>. New users can install with{" "}
                <Code>brew install --cask bettershot</Code> or grab the DMG from{" "}
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/releases"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-700 underline underline-offset-2 hover:text-brand"
                >
                  GitHub Releases
                </a>
                .
              </P>
              <P>
                Existing shortcuts and preferences are preserved on upgrade. The new shortcut
                actions start unassigned so nothing changes until you bind them.
              </P>

              <div className="mt-14 rounded-2xl border border-zinc-200 p-8">
                <h2 className="text-[28px] leading-[34px] tracking-tight">
                  Try BetterShot 0.5.2
                </h2>
                <p className="mb-7 mt-4 max-w-[46ch] text-[16px] leading-[28px] text-zinc-600">
                  Free, open source, macOS 26.0+. No account, no subscription.
                </p>
                <div className="flex flex-col items-stretch gap-3 sm:flex-row sm:items-center">
                  <DownloadDropdown release={release} source="cta" className="w-full sm:w-auto" />
                  <Link
                    href="/changelog"
                    className="inline-flex items-center justify-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-700 outline-none transition-colors duration-150 hover:border-zinc-400 hover:bg-zinc-50"
                  >
                    Full changelog
                  </Link>
                </div>
              </div>

            </article>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}

function H2({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="mb-5 mt-12 scroll-mt-20 text-[28px] leading-[34px] tracking-tight">
      {children}
    </h2>
  )
}

function P({ children }: { children: React.ReactNode }) {
  return <p className="mb-5 text-[17px] leading-[30px] text-zinc-600">{children}</p>
}

function Strong({ children }: { children: React.ReactNode }) {
  return <strong className="font-semibold text-zinc-900">{children}</strong>
}

function Code({ children }: { children: React.ReactNode }) {
  return <code className="rounded bg-zinc-100 px-1.5 py-0.5 font-mono text-[0.92em] text-zinc-700">{children}</code>
}

function List({ items }: { items: string[] }) {
  return (
    <ul className="mb-5">
      {items.map((item) => (
        <li
          key={item}
          className="border-t border-zinc-200 py-3 text-[16px] leading-[28px] text-zinc-600"
        >
          {item}
        </li>
      ))}
    </ul>
  )
}

function TldrItem({ children }: { children: React.ReactNode }) {
  return (
    <li className="border-t border-zinc-200 py-3 text-[15px] leading-[24px] text-zinc-600 first:border-t-0 first:pt-0">
      {children}
    </li>
  )
}
