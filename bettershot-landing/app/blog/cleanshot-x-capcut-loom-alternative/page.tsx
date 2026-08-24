import type { Metadata } from "next"
import Link from "next/link"
import { ArrowLeft, Check, X } from "lucide-react"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { formatPostDate, getPost } from "@/lib/blog"

const post = getPost("cleanshot-x-capcut-loom-alternative")!
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
      about: [
        { "@type": "SoftwareApplication", name: "CleanShot X", operatingSystem: "macOS" },
        { "@type": "SoftwareApplication", name: "Loom" },
        { "@type": "SoftwareApplication", name: "CapCut" },
      ],
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
    <div className="min-h-screen w-full bg-canvas text-ink selection:bg-brand/20">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <SiteNav />

      <main className="pt-14">
        <article className="max-w-[720px] mx-auto px-5 sm:px-6 pt-16 pb-20">
          <Link
            href="/blog"
            className="inline-flex items-center gap-1.5 text-[12.5px] text-ink/35 hover:text-ink/70 transition-colors mb-10"
          >
            <ArrowLeft className="h-3.5 w-3.5" />
            All posts
          </Link>

          <div className="flex items-center gap-3 mb-5">
            <span className="inline-flex items-center h-[20px] px-2 rounded-md bg-brand/12 text-[10.5px] font-semibold text-brand tracking-wide uppercase">
              {post.tag}
            </span>
            <time className="text-[12px] text-ink/30 font-mono" dateTime={post.date}>
              {formatPostDate(post.date)}
            </time>
            <span className="text-[12px] text-ink/25">{post.readingTime}</span>
          </div>

          <h1 className="text-[32px] sm:text-[42px] font-bold tracking-[-0.035em] text-ink leading-[1.12] mb-5 text-balance">
            One free macOS app instead of CleanShot X, CapCut, and Loom
          </h1>

          <p className="text-[17px] sm:text-[18px] leading-[1.7] text-ink/50 mb-12 text-pretty">
            If you take screenshots for work, record walkthroughs for teammates, and trim those
            recordings before sending them, you are probably paying three companies for one job.
            Here is what each of those tools actually does, and where a free, open-source macOS app
            covers the same ground.
          </p>

          <div className="rounded-2xl border border-ink/[0.08] bg-white p-6 sm:p-7 mb-12">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-brand mb-4">
              The short answer
            </p>
            <ul className="space-y-3">
              <TldrItem>
                <strong className="font-semibold text-ink/80">Replacing CleanShot X:</strong> yes for
                almost everyone. Region, window, and fullscreen capture, annotations, OCR, pinning,
                and a beautifier are all there, free.
              </TldrItem>
              <TldrItem>
                <strong className="font-semibold text-ink/80">Replacing Loom:</strong> yes if you own
                a Cloudflare R2 bucket and do not need viewer analytics or comment threads.
              </TldrItem>
              <TldrItem>
                <strong className="font-semibold text-ink/80">Replacing CapCut:</strong> yes for
                screen recordings. No for multi-track social video with music, captions, and
                transitions.
              </TldrItem>
            </ul>
          </div>

          <H2 id="the-stack">The stack most Mac users end up with</H2>
          <P>
            It happens gradually. macOS ships with <Code>⌘⇧4</Code>, which is fine until you need an
            arrow on the screenshot. So you buy <Strong>CleanShot X</Strong>. Then a teammate asks
            for a walkthrough instead of a paragraph, so you sign up for <Strong>Loom</Strong>. Then
            a recording runs long and needs a cut in the middle, so you open{" "}
            <Strong>CapCut</Strong>. Three apps, three accounts, and two recurring charges to explain
            what is on your screen.
          </P>
          <P>
            Each of those tools is good at what it was built for. The question is whether you need
            all three, and whether the work has to leave your machine at all.
          </P>

          <H2 id="what-each-tool-does">What each tool is actually for</H2>
          <P>
            <Strong>CleanShot X</Strong> is a screenshot tool with an excellent capture flow:
            scrolling capture, annotation, pinned overlays, and a quick-access overlay after every
            shot. As of August 2026 it is $29 one-time for a license with a year of updates, with
            CleanShot Cloud at $8/month if you want hosted links.
          </P>
          <P>
            <Strong>Loom</Strong> is an async video messaging product. The recording is the small
            part; the value is hosting, instant links, transcripts, viewer analytics, and comments.
            The free Starter plan caps you at 25 videos per member and five minutes per recording.
            Business runs $18 per seat per month.
          </P>
          <P>
            <Strong>CapCut</Strong> is a general video editor built for social content: multi-track
            timelines, music, captions, transitions, and an AI toolkit. CapCut Pro is $19.99/month,
            and pricing varies by region and device.
          </P>
          <P>
            <Strong>Better Shot</Strong> is a native macOS app that covers the overlap between them:
            capture, annotate, record with cursor auto-zoom, trim, beautify, export, and optionally
            share from storage you own. It is free, BSD 3-Clause licensed, and does not have an
            account system.
          </P>

          <H2 id="cleanshot-x-alternative">As a CleanShot X alternative</H2>
          <P>
            This is the closest overlap, and the easiest switch. Better Shot binds the same muscle
            memory: <Code>⌘⇧4</Code> for a region, <Code>⌘⇧3</Code> for the screen,{" "}
            <Code>⌘⇧5</Code> for a window. After every capture a floating preview appears, and you
            can drag it straight into Figma, Slack, or Finder without saving a file first.
          </P>
          <List
            items={[
              "Annotation tools with single-key shortcuts: arrows, rectangles, circles, freehand, text with font control, numbered badges, blur, and spotlight",
              "OCR text extraction with ⌘⇧O, built on Apple's Vision framework",
              "A system-wide color picker on ⌘⇧C",
              "Pin a screenshot as an always-on-top window while you work from it",
              "Beautify: padding, corner radius, shadow, plus solid colors, gradients, macOS wallpapers, or your own image as a background",
              "Capture history, with a configurable retention limit",
            ]}
          />
          <P>
            The notable gap is <Strong>scrolling capture</Strong>. CleanShot X stitches a long page
            into one image; Better Shot does not do that yet. If scrolling capture is central to your
            work, that alone may keep you on CleanShot X.
          </P>

          <H2 id="loom-alternative">As a Loom alternative for Mac</H2>
          <P>
            Recording is where Better Shot changed the most in v4. You pick a display, a window, or
            an area from a floating source picker, toggle microphone and system audio, set a start
            delay, and record. The bar you set up in is the bar you stop in.
          </P>
          <P>
            The feature that makes recordings watchable is <Strong>cursor auto-zoom</Strong>. Pointer
            position is sampled at 30 Hz during capture, clicks become zoom cues, and those cues are
            smoothed through a spring-damped viewport timeline and baked into the export. A 4K screen
            stays readable inside a small video player, without you manually keyframing anything.
            Every cue can still be retimed, rescaled, or deleted before export.
          </P>
          <List
            items={[
              "Face cam bubble you can drag anywhere, captured as part of the recording rather than composited after",
              "Microphone recorded as its own audio track, separate from system audio (requires macOS 15)",
              "Single-window recording that excludes whatever is stacked on top of it",
              "24, 30, or 60 fps, multi-display aware, with pause, resume, and restart",
              "Fragmented MP4 writing, so a crash mid-recording leaves a playable file instead of a corrupt one",
            ]}
          />
          <P>
            Sharing works differently, and that difference is the whole point. Loom hosts your video
            and hands you a link. Better Shot uploads the edited recording directly from the app to{" "}
            <Strong>your own Cloudflare R2 bucket</Strong> over a signed request, then copies the
            public link. No proxy, no vendor in the middle, no per-seat pricing, no five-minute cap,
            and no video quota. Your R2 keys live in the macOS Keychain.
          </P>
          <P>
            What you give up: viewer analytics, comment threads, automatic transcripts, and the
            social layer around a Loom link. If those are how your team works, Loom earns its price.
          </P>

          <H2 id="capcut-alternative">As a CapCut alternative for screen recordings</H2>
          <P>
            Most people open CapCut on a screen recording for four reasons: cut the dead air at the
            start, split out a mistake in the middle, speed up a slow section, and make the result
            look presentable. All four are in Better Shot&apos;s video editor.
          </P>
          <List
            items={[
              "Multi-clip timeline: split at the playhead, drag either edge of a clip to trim, select and scrub a clip, delete what you do not want",
              "Per-clip speed from 0.25x to 4x, applied to video and audio together",
              "Undo and redo with ⌘Z and ⌘⇧Z",
              "Crop with corner and edge handles and a rule-of-thirds grid, applied at export",
              "Backgrounds, padding, corner radius, and shadow on video, the same pipeline as screenshots",
              "MP4 export with no watermark, at any plan tier, because there are no plan tiers",
            ]}
          />
          <P>
            What CapCut still does better: multi-track editing, music and sound effects, auto
            captions, transitions, keyframed effects, and its AI toolkit. Better Shot is a screen
            recording editor, not a general-purpose video editor. If you are producing content for an
            audience rather than a colleague, keep CapCut.
          </P>

          <H2 id="honest-limits">Where the paid tools still win</H2>
          <P>
            A comparison that only lists wins is marketing. The honest version:
          </P>
          <div className="rounded-2xl border border-ink/[0.08] bg-white overflow-hidden my-7">
            {[
              {
                tool: "CleanShot X",
                reason: "Scrolling capture, and a longer track record of polish across edge cases.",
              },
              {
                tool: "Loom",
                reason:
                  "Hosting you do not have to configure, viewer analytics, transcripts, and comments on the video.",
              },
              {
                tool: "CapCut",
                reason:
                  "Multi-track editing, music, captions, transitions, and everything aimed at social video.",
              },
            ].map((row, i) => (
              <div
                key={row.tool}
                className={`flex flex-col sm:flex-row gap-1 sm:gap-6 px-6 py-4 ${
                  i === 0 ? "" : "border-t border-ink/[0.06]"
                }`}
              >
                <span className="text-[13.5px] font-semibold text-ink/75 sm:w-[120px] shrink-0">
                  {row.tool}
                </span>
                <span className="text-[13.5px] leading-[1.7] text-ink/45">{row.reason}</span>
              </div>
            ))}
          </div>
          <P>
            Better Shot also requires macOS 14 or later, and microphone capture requires macOS 15,
            because that is where ScreenCaptureKit added it. There is no Windows or Linux build.
          </P>

          <H2 id="cost">What the stack costs over three years</H2>
          <div className="overflow-x-auto -mx-5 sm:mx-0 px-5 sm:px-0 my-7">
            <table className="w-full min-w-[520px] border-separate border-spacing-0 bg-white rounded-2xl border border-ink/[0.08] overflow-hidden">
              <thead>
                <tr>
                  {["Tool", "Price", "3 years, 1 seat"].map((heading, i) => (
                    <th
                      key={heading}
                      className={`text-[11px] font-semibold uppercase tracking-wider text-ink/30 px-5 py-3.5 border-b border-ink/[0.07] ${
                        i === 0 ? "text-left" : "text-right"
                      }`}
                    >
                      {heading}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {[
                  ["CleanShot X + Cloud Pro", "$29 once + $8/mo", "$317"],
                  ["Loom Business", "$18/seat/mo", "$648"],
                  ["CapCut Pro", "$19.99/mo", "$720"],
                  ["All three", "Sum of the above", "$1,685"],
                  ["Better Shot", "Free", "$0"],
                ].map(([tool, price, total], i, all) => {
                  const isLast = i === all.length - 1
                  return (
                    <tr key={tool} className={isLast ? "bg-brand/[0.06]" : ""}>
                      <td
                        className={`text-[13.5px] px-5 py-3.5 ${
                          isLast ? "font-semibold text-ink" : "text-ink/65"
                        } ${i === all.length - 1 ? "" : "border-b border-ink/[0.05]"}`}
                      >
                        {tool}
                      </td>
                      <td
                        className={`text-[13px] text-right px-5 py-3.5 text-ink/45 ${
                          isLast ? "" : "border-b border-ink/[0.05]"
                        }`}
                      >
                        {price}
                      </td>
                      <td
                        className={`text-[13.5px] text-right px-5 py-3.5 font-mono tabular-nums ${
                          isLast ? "font-semibold text-ink" : "text-ink/60"
                        } ${isLast ? "" : "border-b border-ink/[0.05]"}`}
                      >
                        {total}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <P>
            Prices are list prices published in August 2026, billed monthly, for a single seat. Annual
            billing lowers each of them. R2 storage for share links is billed by usage and is
            typically cents per month for screen recordings.
          </P>

          <H2 id="privacy">The part that is not about money</H2>
          <P>
            Screenshots and screen recordings are unusually sensitive. They contain client
            dashboards, internal tools, half-written messages, unreleased features, and whatever else
            was open behind the window you meant to capture. Uploading all of that to a vendor just
            to generate a link is a habit worth questioning.
          </P>
          <P>
            Better Shot is local-first by construction: capture, edit, and export never touch the
            network. There is no account, no telemetry, and no analytics in the app. Share links are
            opt-in and land in a bucket you control, which means you can also delete them properly.
            You can verify all of that, because the{" "}
            <A href="https://github.com/KartikLabhshetwar/better-shot">source is public</A>.
          </P>

          <H2 id="switching">Switching takes about five minutes</H2>
          <OrderedList
            items={[
              "Install with brew install --cask bettershot, or download the DMG for Apple Silicon or Intel.",
              "Grant screen recording permission the first time macOS asks. That is the only prompt until you enable the mic or camera.",
              "Remap the shortcuts in Settings if you want your old bindings. The defaults already match the macOS ones you know.",
              "Set your default background, padding, and shadow once, and turn on auto-apply so every capture comes out styled.",
              "Optional: add a Cloudflare R2 bucket in Settings > Sharing if you want share links.",
            ]}
          />
          <P>
            If you are coming from CleanShot X, keep it installed for a week and use whichever opens
            first. Most people stop reaching for the paid one within a few days, except for scrolling
            capture.
          </P>

          <H2 id="faq">Common questions</H2>
          <div className="space-y-6 my-7">
            <Faq q="Is there a catch to it being free?">
              No. It is BSD 3-Clause licensed open source, maintained in public, with no paid tier
              planned. The cost you carry is that support is GitHub issues, not a support desk.
            </Faq>
            <Faq q="Does it put a watermark on exports?">
              No. There is no watermark at any resolution or length, because there are no tiers to
              upsell you to.
            </Faq>
            <Faq q="Can I use it for client work?">
              Yes. The BSD 3-Clause license permits commercial use, modification, and redistribution.
            </Faq>
            <Faq q="Do I need Cloudflare R2 to use it?">
              No. R2 is only needed for share links. Without it, everything else works and you share
              files the way you already do.
            </Faq>
          </div>

          <div className="rounded-2xl border border-ink/[0.08] bg-white p-7 sm:p-8 mt-14">
            <h2 className="text-[22px] sm:text-[26px] font-bold tracking-[-0.03em] text-ink mb-3">
              Try it before your next renewal
            </h2>
            <p className="text-[15px] leading-[1.7] text-ink/45 mb-7 max-w-[440px]">
              Free, open source, macOS 14+. No account, no card, no trial countdown. Compare it side
              by side with what you pay for now.
            </p>
            <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
              <DownloadDropdown release={release} source="cta" className="w-full sm:w-auto" />
              <Link
                href="/#compare"
                className="inline-flex items-center justify-center px-5 h-12 text-[14px] font-medium text-ink/55 hover:text-ink border border-ink/[0.1] hover:border-ink/[0.18] rounded-xl transition-all"
              >
                See the feature matrix
              </Link>
            </div>
          </div>

          <div className="mt-12 pt-6 border-t border-ink/[0.06]">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-ink/30 mb-3">
              Sources
            </p>
            <ul className="space-y-1.5">
              {[
                ["CleanShot X pricing", "https://cleanshot.com/pricing"],
                ["Loom pricing", "https://www.loom.com/pricing"],
                ["CapCut pricing", "https://www.capcut.com/"],
                [
                  "Better Shot changelog",
                  "https://bettershot.site/changelog",
                ],
              ].map(([label, href]) => (
                <li key={href}>
                  <a
                    href={href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[12.5px] text-ink/40 hover:text-ink/70 underline decoration-ink/15 underline-offset-2 transition-colors"
                  >
                    {label}
                  </a>
                </li>
              ))}
            </ul>
            <p className="text-[11.5px] text-ink/25 mt-4 leading-[1.6]">
              Competitor pricing and plan limits are as published in August 2026 and change often.
              Check each vendor&apos;s page for current numbers. CleanShot X, Loom, and CapCut are
              trademarks of their respective owners and are not affiliated with Better Shot.
            </p>
          </div>
        </article>
      </main>

      <SiteFooter />
    </div>
  )
}

/* ─── Article typography ─── */

function H2({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2
      id={id}
      className="text-[24px] sm:text-[28px] font-bold tracking-[-0.03em] text-ink leading-[1.25] mt-14 mb-5 scroll-mt-20"
    >
      {children}
    </h2>
  )
}

function P({ children }: { children: React.ReactNode }) {
  return <p className="text-[16px] leading-[1.8] text-ink/50 mb-5">{children}</p>
}

function Strong({ children }: { children: React.ReactNode }) {
  return <strong className="font-semibold text-ink/80">{children}</strong>
}

function Code({ children }: { children: React.ReactNode }) {
  return (
    <code className="font-mono text-[0.9em] text-ink/70 bg-ink/[0.05] rounded px-1.5 py-[2px]">
      {children}
    </code>
  )
}

function A({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="text-ink/75 underline decoration-ink/25 underline-offset-2 hover:decoration-ink/60 transition-colors"
    >
      {children}
    </a>
  )
}

function List({ items }: { items: string[] }) {
  return (
    <ul className="space-y-2.5 mb-6">
      {items.map((item) => (
        <li key={item} className="flex items-start gap-3">
          <Check className="h-4 w-4 mt-[3px] shrink-0 text-brand" />
          <span className="text-[15.5px] leading-[1.7] text-ink/50">{item}</span>
        </li>
      ))}
    </ul>
  )
}

function OrderedList({ items }: { items: string[] }) {
  return (
    <ol className="space-y-3 mb-6">
      {items.map((item, i) => (
        <li key={item} className="flex items-start gap-3.5">
          <span className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full bg-ink/[0.05] text-[11px] font-semibold text-ink/50 mt-[3px]">
            {i + 1}
          </span>
          <span className="text-[15.5px] leading-[1.7] text-ink/50">{item}</span>
        </li>
      ))}
    </ol>
  )
}

function TldrItem({ children }: { children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-3">
      <span className="mt-[7px] h-1.5 w-1.5 rounded-full bg-brand shrink-0" />
      <span className="text-[14.5px] leading-[1.7] text-ink/50">{children}</span>
    </li>
  )
}

function Faq({ q, children }: { q: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-[16px] font-semibold text-ink/85 mb-1.5">{q}</h3>
      <p className="text-[15px] leading-[1.75] text-ink/50">{children}</p>
    </div>
  )
}
