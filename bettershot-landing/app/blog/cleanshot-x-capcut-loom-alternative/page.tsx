import type { Metadata } from "next"
import Link from "next/link"
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


const th = "text-[13px] font-medium uppercase tracking-widest border-b border-zinc-200 px-2 py-2 text-left text-[11px] font-semibold text-zinc-400"
const td = "border-b border-zinc-200 px-2 py-2"

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
            <h1 className="mt-5 text-[clamp(34px,4.6vw,56px)] font-extrabold leading-[1.08] tracking-tight">
              One free macOS app instead of CleanShot X, CapCut, and Loom
            </h1>
            <p className="mt-5 text-[15px] text-zinc-400">
              <time dateTime={post.date}>{formatPostDate(post.date)}</time> &middot; {post.readingTime}
            </p>
          </header>

          <div className="mx-auto max-w-[680px] h-px bg-zinc-200" />

          <div>
            <article className="mx-auto max-w-[680px] pb-16 pt-12">
              <p className="mb-8 text-[19px] leading-[32px] text-zinc-900">
                If you take screenshots for work, record walkthroughs for teammates, and trim those
                recordings before sending them, you are probably paying three companies for one job.
                Here is what each of those tools actually does, and where a free, open source macOS
                app covers the same ground.
              </p>

              <div className="mb-10 rounded-2xl border border-zinc-200 p-6">
                <p className="mb-4 text-[13px] font-medium uppercase tracking-widest text-brand-700">
                  The short answer
                </p>
                <ul>
                  <TldrItem>
                    <Strong>Replacing CleanShot X:</Strong> yes for almost everyone. Region, window,
                    and fullscreen capture, annotations, OCR, pinning, and a beautifier are all
                    there, free.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Replacing Loom:</Strong> yes if you own a Cloudflare R2 bucket and do not
                    need viewer analytics or comment threads.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Replacing CapCut:</Strong> yes for screen recordings. No for multi track
                    social video with music, captions, and transitions.
                  </TldrItem>
                </ul>
              </div>

              <H2 id="the-stack">The stack most Mac users end up with</H2>
              <P>
                It happens gradually. macOS ships with <Code>⌘⇧4</Code>, which is fine until you need
                an arrow on the screenshot. So you buy <Strong>CleanShot X</Strong>. Then a teammate
                asks for a walkthrough instead of a paragraph, so you sign up for{" "}
                <Strong>Loom</Strong>. Then a recording runs long and needs a cut in the middle, so
                you open <Strong>CapCut</Strong>. Three apps, three accounts, and two recurring
                charges to explain what is on your screen.
              </P>
              <P>
                Each of those tools is good at what it was built for. The question is whether you
                need all three, and whether the work has to leave your machine at all.
              </P>

              <H2 id="what-each-tool-does">What each tool is actually for</H2>
              <P>
                <Strong>CleanShot X</Strong> is a screenshot tool with an excellent capture flow:
                scrolling capture, annotation, pinned overlays, and a quick access overlay after
                every shot. As of August 2026 it is $29 one time for a license with a year of
                updates, with CleanShot Cloud at $8/month if you want hosted links.
              </P>
              <P>
                <Strong>Loom</Strong> is an async video messaging product. The recording is the small
                part; the value is hosting, instant links, transcripts, viewer analytics, and
                comments. The free Starter plan caps you at 25 videos per member and five minutes per
                recording. Business runs $18 per seat per month.
              </P>
              <blockquote className="my-9 max-w-[34ch] border-l-2 border-brand pl-6 text-[clamp(24px,2.6vw,32px)] font-extrabold leading-[1.24] tracking-tight">
                A limit you hit mid-demo is not a free tier. It is a sales call.
              </blockquote>
              <P>
                <Strong>CapCut</Strong> is a general video editor built for social content: multi
                track timelines, music, captions, transitions, and an AI toolkit. CapCut Pro is
                $19.99/month, and pricing varies by region and device.
              </P>
              <P>
                <Strong>Better Shot</Strong> is a native macOS app that covers the overlap between
                them: capture, annotate, record with cursor auto zoom, trim, beautify, export, and
                optionally share from storage you own. It is free, BSD 3 Clause licensed, and does
                not have an account system.
              </P>

              <H2 id="cleanshot-x-alternative">As a CleanShot X alternative</H2>
              <P>
                This is the closest overlap, and the easiest switch. Better Shot binds the same
                muscle memory: <Code>⌘⇧4</Code> for a region, <Code>⌘⇧3</Code> for the screen,{" "}
                <Code>⌘⇧5</Code> for a window. After every capture a floating preview appears, and
                you can drag it straight into Figma, Slack, or Finder without saving a file first.
              </P>
              <List
                items={[
                  "Annotation tools with single-key shortcuts: arrows, rectangles, circles, freehand, text with font control, numbered badges, blur, and spotlight",
                  "OCR text extraction with ⌘⇧O, built on Apple's Vision framework",
                  "A system wide color picker on ⌘⇧C",
                  "Pin a screenshot as an always on top window while you work from it",
                  "Beautify: padding, corner radius, shadow, plus solid colors, gradients, macOS wallpapers, or your own image as a background",
                  "Capture history, with a configurable retention limit",
                ]}
              />
              <P>
                The notable gap is <Strong>scrolling capture</Strong>. CleanShot X stitches a long
                page into one image; Better Shot does not do that yet. If scrolling capture is
                central to your work, that alone may keep you on CleanShot X.
              </P>

              <H2 id="loom-alternative">As a Loom alternative for Mac</H2>
              <P>
                Recording is where Better Shot changed the most in v4. You pick a display, a window,
                or an area from a floating source picker, toggle microphone and system audio, set a
                start delay, and record. The bar you set up in is the bar you stop in.
              </P>
              <P>
                The feature that makes recordings watchable is <Strong>cursor auto zoom</Strong>.
                Pointer position is sampled at 30 Hz during capture, clicks become zoom cues, and
                those cues are smoothed through a spring-damped viewport timeline and baked into the
                export. A 4K screen stays readable inside a small video player, without you manually
                keyframing anything. Every cue can still be retimed, rescaled, or deleted before
                export.
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
                Sharing works differently, and that difference is the whole point. Loom hosts your
                video and hands you a link. Better Shot uploads the edited recording directly from
                the app to <Strong>your own Cloudflare R2 bucket</Strong> over a signed request, then
                copies the public link. No proxy, no vendor in the middle, no per-seat pricing, no
                five-minute cap, and no video quota. Your R2 keys live in the macOS Keychain.
              </P>
              <P>
                What you give up: viewer analytics, comment threads, automatic transcripts, and the
                social layer around a Loom link. If those are how your team works, Loom earns its
                price.
              </P>

              <H2 id="capcut-alternative">As a CapCut alternative for screen recordings</H2>
              <P>
                Most people open CapCut on a screen recording for four reasons: cut the dead air at
                the start, split out a mistake in the middle, speed up a slow section, and make the
                result look presentable. All four are in Better Shot&apos;s video editor.
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
                What CapCut still does better: multi track editing, music and sound effects, auto
                captions, transitions, keyframed effects, and its AI toolkit. Better Shot is a screen
                recording editor, not a general-purpose video editor. If you are producing content
                for an audience rather than a colleague, keep CapCut.
              </P>

              <H2 id="honest-limits">Where the paid tools still win</H2>
              <P>A comparison that only lists wins is marketing. The honest version:</P>
              <ul className="my-8">
                {[
                  {
                    tool: "CleanShot X",
                    reason:
                      "Scrolling capture, and a longer track record of polish across edge cases.",
                  },
                  {
                    tool: "Loom",
                    reason:
                      "Hosting you do not have to configure, viewer analytics, transcripts, and comments on the video.",
                  },
                  {
                    tool: "CapCut",
                    reason:
                      "Multi track editing, music, captions, transitions, and everything aimed at social video.",
                  },
                ].map((row) => (
                  <li
                    key={row.tool}
                    className="grid gap-x-8 gap-y-1.5 border-t border-zinc-200 py-3.5 sm:grid-cols-[minmax(0,140px)_minmax(0,1fr)]"
                  >
                    <span className="text-[15px] font-semibold leading-[24px]">{row.tool}</span>
                    <span className="text-[15px] leading-[24px] text-zinc-600">{row.reason}</span>
                  </li>
                ))}
              </ul>
              <P>
                Better Shot also requires macOS 14 or later, and microphone capture requires macOS
                15, because that is where ScreenCaptureKit added it. There is no Windows or Linux
                build.
              </P>

              <H2 id="cost">What the stack costs over three years</H2>
              <div className="my-8 overflow-x-auto">
                <table className="w-full min-w-[520px] border-collapse text-[14px]">
                  <thead>
                    <tr>
                      <th className={th}>Tool</th>
                      <th className={`${th} text-right`}>Price</th>
                      <th className={`${th} text-right`}>3 years, 1 seat</th>
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
                        <tr key={tool}>
                          <td className={`${td} font-medium ${isLast ? "text-brand" : ""}`}>
                            {tool}
                          </td>
                          <td className={`${td} text-right text-zinc-400`}>{price}</td>
                          <td
                            className={`${td} text-right tabular-nums ${
                              isLast ? "font-semibold text-brand" : "text-zinc-400"
                            }`}
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
                Prices are list prices published in August 2026, billed monthly, for a single seat.
                Annual billing lowers each of them. R2 storage for share links is billed by usage and
                is typically cents per month for screen recordings.
              </P>

              <H2 id="privacy">The part that is not about money</H2>
              <P>
                Screenshots and screen recordings are unusually sensitive. They contain client
                dashboards, internal tools, half written messages, unreleased features, and whatever
                else was open behind the window you meant to capture. Uploading all of that to a
                vendor just to generate a link is a habit worth questioning.
              </P>
              <P>
                Better Shot is local first by construction: capture, edit, and export never touch the
                network. There is no account, no telemetry, and no analytics in the app. Share links
                are optional and land in a bucket you control, which means you can also delete them
                properly. You can verify all of that, because the{" "}
                <A href="https://github.com/KartikLabhshetwar/better-shot">source is public</A>.
              </P>

              <H2 id="switching">Switching takes about five minutes</H2>
              <OrderedList
                items={[
                  "Install with brew install --cask bettershot, or download the DMG for Apple Silicon or Intel.",
                  "Grant screen recording permission the first time macOS asks. That is the only prompt until you enable the mic or camera.",
                  "Remap the shortcuts in Settings if you want your old bindings. The defaults already match the macOS ones you know.",
                  "Set your default background, padding, and shadow once, and turn on auto apply so every capture comes out styled.",
                  "Optional: add a Cloudflare R2 bucket in Settings > Sharing if you want share links.",
                ]}
              />
              <P>
                If you are coming from CleanShot X, keep it installed for a week and use whichever
                opens first. Most people stop reaching for the paid one within a few days, except for
                scrolling capture.
              </P>

              <H2 id="faq">Common questions</H2>
              <div className="my-8 rounded-2xl border border-zinc-200 divide-y divide-zinc-200 overflow-hidden">
                <Faq q="Is there a catch to it being free?">
                  No. It is BSD 3 Clause licensed open source, maintained in public, with no paid
                  tier planned. The cost you carry is that support is GitHub issues, not a support
                  desk.
                </Faq>
                <Faq q="Does it put a watermark on exports?">
                  No. There is no watermark at any resolution or length, because there are no tiers
                  to upsell you to.
                </Faq>
                <Faq q="Can I use it for client work?">
                  Yes. The BSD 3 Clause license permits commercial use, modification, and
                  redistribution.
                </Faq>
                <Faq q="Do I need Cloudflare R2 to use it?">
                  No. R2 is only needed for share links. Without it, everything else works and you
                  share files the way you already do.
                </Faq>
              </div>

              <div className="mt-14 rounded-2xl border border-zinc-200 p-8">
                <h2 className="text-[28px] font-extrabold leading-[34px] tracking-tight">
                  Try it before your next renewal
                </h2>
                <p className="mb-7 mt-4 max-w-[46ch] text-[16px] leading-[28px] text-zinc-600 ">
                  Free, open source, macOS 14+. No account, no card, no trial countdown. Compare it
                  side by side with what you pay for now.
                </p>
                <div className="flex flex-col items-stretch gap-3 sm:flex-row sm:items-center">
                  <DownloadDropdown release={release} source="cta" className="w-full sm:w-auto" />
                  <Link
                    href="/#compare"
                    className="inline-flex items-center justify-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-900 outline-none transition-colors duration-150 hover:border-zinc-400"
                  >
                    See the feature matrix
                  </Link>
                </div>
              </div>

              <div className="mt-12 border-t border-zinc-200 pt-6">
                <p className="mb-3 text-[13px] font-medium uppercase tracking-widest text-zinc-400">Sources</p>
                <ul className="space-y-2">
                  {[
                    ["CleanShot X pricing", "https://cleanshot.com/pricing"],
                    ["Loom pricing", "https://www.loom.com/pricing"],
                    ["CapCut pricing", "https://www.capcut.com/"],
                    ["Better Shot changelog", "https://bettershot.site/changelog"],
                  ].map(([label, href]) => (
                    <li key={href}>
                      <a
                        href={href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[13px] text-zinc-400 underline underline-offset-2 outline-none transition-colors duration-150 hover:text-zinc-900"
                      >
                        {label}
                      </a>
                    </li>
                  ))}
                </ul>
                <p className="mt-4 text-[13px] leading-[22px] text-zinc-400">
                  Competitor pricing and plan limits are as published in August 2026 and change
                  often. Check each vendor&apos;s page for current numbers. CleanShot X, Loom, and
                  CapCut are trademarks of their respective owners and are not affiliated with Better
                  Shot.
                </p>
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
    <h2 id={id} className="mb-5 mt-12 scroll-mt-20 text-[28px] font-extrabold leading-[34px]">
      {children}
    </h2>
  )
}

function P({ children }: { children: React.ReactNode }) {
  return <p className="mb-5 text-[16px] leading-[28px] text-zinc-600">{children}</p>
}

function Strong({ children }: { children: React.ReactNode }) {
  return <strong className="font-semibold text-zinc-900">{children}</strong>
}

function Code({ children }: { children: React.ReactNode }) {
  return <code className="rounded bg-zinc-100 px-1.5 py-0.5 font-mono text-[0.92em] text-zinc-900">{children}</code>
}

function A({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="text-brand-700 underline underline-offset-2 outline-none transition-colors duration-150 hover:text-brand"
    >
      {children}
    </a>
  )
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

function OrderedList({ items }: { items: string[] }) {
  return (
    <ol className="mb-5">
      {items.map((item, i) => (
        <li
          key={item}
          className="grid gap-x-6 border-t border-zinc-200 py-3 text-[16px] leading-[28px] text-zinc-600 sm:grid-cols-[32px_minmax(0,1fr)]"
        >
          <span className="font-extrabold tabular-nums text-brand-700">
            {String(i + 1).padStart(2, "0")}
          </span>
          <span>{item}</span>
        </li>
      ))}
    </ol>
  )
}

function TldrItem({ children }: { children: React.ReactNode }) {
  return (
    <li className="border-t border-zinc-200 py-3 text-[15px] leading-[24px] text-zinc-600 first:border-t-0 first:pt-0">
      {children}
    </li>
  )
}

function Faq({ q, children }: { q: string; children: React.ReactNode }) {
  return (
    <div className="py-5 px-6">
      <h3 className="mb-2 text-[16px] font-semibold">{q}</h3>
      <p className="text-[15px] leading-[26px] text-zinc-600">{children}</p>
    </div>
  )
}
