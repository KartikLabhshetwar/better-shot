import type { Metadata } from "next"
import Link from "next/link"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { formatPostDate, getPost } from "@/lib/blog"

const post = getPost("loom-alternative")!
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
        { "@type": "SoftwareApplication", name: "Loom" },
        { "@type": "SoftwareApplication", name: "Better Shot", operatingSystem: "macOS" },
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

const toc = [
  { id: "what-loom-does", label: "What Loom does well" },
  { id: "where-loom-falls-short", label: "Where it falls short" },
  { id: "better-shot-recording", label: "Recording in Better Shot" },
  { id: "cursor-auto-zoom", label: "Cursor auto-zoom" },
  { id: "editing", label: "A real timeline editor" },
  { id: "captions", label: "On-device captions" },
  { id: "sharing", label: "Share links you own" },
  { id: "performance", label: "Native macOS performance" },
  { id: "comparison", label: "Side-by-side comparison" },
  { id: "cost", label: "Pricing" },
  { id: "switching", label: "Switching from Loom" },
  { id: "faq", label: "Common questions" },
]

const th = "border-b border-zinc-200 px-3 py-2.5 text-left text-[12px] font-semibold uppercase tracking-widest text-zinc-400"
const td = "border-b border-zinc-100 px-3 py-2.5"

export default async function Article() {
  const release = await getLatestRelease()

  return (
    <div className="min-h-screen w-full bg-white text-zinc-900">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <SiteNav />

      <main id="main">
        <div className="mx-auto max-w-[1100px] px-6">
          <header className="max-w-[860px] pb-10 pt-28 sm:pt-32">
            <p className="mb-3.5 text-[13px] font-medium uppercase tracking-widest text-brand-700">
              <Link href="/blog" className="outline-none transition-colors duration-150 hover:text-brand">
                Blog
              </Link>{" "}
              / {post.tag}
            </p>
            <h1 className="text-[clamp(34px,4.6vw,56px)] font-extrabold leading-[1.08] tracking-tight">
              {post.headline}
            </h1>
            <p className="mt-6 text-[13px] uppercase tracking-widest text-zinc-400">
              <time dateTime={post.date}>{formatPostDate(post.date)}</time> &middot; {post.readingTime}
            </p>
          </header>

          <div className="border-t border-zinc-200" />

          <div className="grid items-start gap-x-[clamp(24px,5vw,80px)] lg:grid-cols-[minmax(0,680px)_minmax(0,1fr)]">
            <article className="max-w-[680px] pb-16 pt-12 lg:border-r lg:border-zinc-200 lg:pr-[clamp(24px,4vw,64px)]">
              <p className="mb-8 text-[19px] leading-[32px] text-zinc-600">
                Loom made async video a habit. But $18 per seat per month, a five-minute cap on the
                free plan, and every recording routed through someone else&apos;s servers is a lot to
                accept for something that started as a screen recording. Here is what a free, open
                source macOS alternative looks like in 2026.
              </p>

              <div className="mb-10 rounded-2xl border border-zinc-200 p-6">
                <p className="mb-4 text-[13px] font-semibold uppercase tracking-widest text-brand-700">
                  The short answer
                </p>
                <ul>
                  <TldrItem>
                    <Strong>Recording:</Strong> cursor auto-zoom at 30 Hz, face cam, mic and system
                    audio on separate tracks, crash-safe fragmented MP4. As good or better for
                    walkthroughs.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Editing:</Strong> a real timeline with split, trim, speed, and overlays,
                    not just a trim slider.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Sharing:</Strong> uploads to your own Cloudflare R2 bucket. You own the
                    link, the storage, and the delete button.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Price:</Strong> $0 forever. BSD 3 Clause open source. No account, no
                    watermark.
                  </TldrItem>
                </ul>
              </div>

              <H2 id="what-loom-does">What Loom does well</H2>
              <P>
                Loom turned screen recording into a communication pattern. Hit record, talk through
                the problem, share a link, and move on. The value was never the recording itself; it
                was the instant link, the transcript, the viewer analytics, and the comments below
                the video. For teams that live in Loom links the way others live in Slack threads,
                the social layer around each recording is real.
              </P>
              <P>
                On the capture side, Loom records your screen and camera, generates a transcript,
                and hosts the video on its own CDN. Setup is minimal: install, record, share.
              </P>

              <H2 id="where-loom-falls-short">Where Loom falls short</H2>
              <P>
                The free Starter plan caps recordings at five minutes per video and 25 videos per
                member. That limit hits mid-demo, which is worse than not having a free tier at all.
                Business costs $18 per seat per month ($12.50 billed yearly), and every seat is
                billed whether they record that month or not.
              </P>
              <List
                items={[
                  "Every recording uploads to Loom's servers. You cannot self-host, redirect to your own storage, or delete a video from the CDN edge with certainty.",
                  "Editing is a trim slider. You can cut the start and end, but you cannot split a clip, speed a section, or add a caption.",
                  "The desktop app is Electron. CPU usage, battery drain, and memory consumption reflect that.",
                  "Recordings are tied to your Loom account. If the company cancels the plan, the links die.",
                ]}
              />
              <blockquote className="my-9 max-w-[34ch] border-l-2 border-brand pl-6 text-[clamp(24px,2.6vw,30px)] font-extrabold leading-[1.24] tracking-tight">
                A limit you hit mid-demo is not a free tier. It is a sales call.
              </blockquote>

              <H2 id="better-shot-recording">Recording in Better Shot</H2>
              <P>
                Better Shot is a native macOS app (Swift, AppKit) that handles capture, recording,
                editing, and sharing in one window. You pick a display, a window, or an area from a
                floating source picker, toggle mic and system audio, set a start delay, and record.
              </P>
              <List
                items={[
                  "Display, window, or region capture with a floating source picker",
                  "Face cam bubble you drag anywhere on screen, composited live during capture",
                  "Microphone and system audio on separate tracks (mic requires macOS 15)",
                  "24, 30, or 60 fps, multi-display aware",
                  "Pause and resume, restart without leaving the control bar",
                  "Fragmented MP4: every frame is committed as it arrives, so a crash mid-recording leaves a playable file",
                ]}
              />

              <H2 id="cursor-auto-zoom">Cursor auto-zoom</H2>
              <P>
                This is the feature that makes Better Shot recordings look different from Loom. The
                pointer is sampled at 30 Hz during capture. Every click becomes a smooth zoom cue,
                and those cues are processed through a spring-damped viewport timeline before being
                baked into the export. A 4K display stays readable inside a 480p video player
                without you keyframing anything.
              </P>
              <P>
                The zoom cues are visible on the timeline after recording. You can retime, rescale,
                or delete any of them before export. The result is a walkthrough that follows your
                mouse the way a cameraman follows the action, automatically.
              </P>

              <H2 id="editing">A real timeline editor</H2>
              <P>
                Loom gives you a trim slider. Better Shot gives you a multi-clip timeline. The
                difference matters the moment a recording has a mistake in the middle, a slow section
                that needs speeding up, or a stretch of dead air at the start.
              </P>
              <List
                items={[
                  "Split at the playhead, drag an edge to trim, delete what you do not want",
                  "Per-clip speed from 0.25x to 4x, applied to video and audio together",
                  "Crop with corner and edge handles and a rule-of-thirds grid",
                  "3D tilt, color grading, and background padding on the video card",
                  "Transitions between clips",
                  "Undo and redo with the shortcuts you expect",
                ]}
              />

              <H2 id="captions">On-device captions</H2>
              <P>
                Captions in Better Shot are a timeline lane, not a post-processing step. They run on
                Apple&apos;s speech recognition framework, entirely on device. Your audio never touches
                a server. The captions appear on the timeline alongside your zoom cues, keystrokes,
                and masks, and you can retime or edit any of them before export.
              </P>
              <P>
                Loom generates transcripts server-side after upload. Better Shot generates them
                locally before you share. The tradeoff: Loom&apos;s server-side transcription handles
                more languages; Better Shot&apos;s on-device approach handles the languages Apple
                supports and keeps the audio private.
              </P>

              <H2 id="sharing">Share links you own</H2>
              <P>
                This is the fundamental difference between Loom and Better Shot. Loom hosts your
                recording on its servers and hands you a loom.com link. Better Shot uploads the
                edited recording directly from the app to <Strong>your own Cloudflare R2
                bucket</Strong> over a signed request (SigV4), then copies the public link.
              </P>
              <List
                items={[
                  "No proxy, no vendor in the middle, no per-seat pricing on the link",
                  "No five-minute cap, no video quota, no viewer limit",
                  "Your R2 keys live in the macOS Keychain, never on a remote server",
                  "Delete a video by deleting the object from R2. Gone from the edge, verifiably.",
                  "R2 storage costs are typically cents per month for screen recordings",
                ]}
              />
              <P>
                The tradeoff: you need to set up a Cloudflare R2 bucket and enter the keys in Better
                Shot&apos;s settings. That takes about five minutes. If you want hosted sharing with zero
                setup, Loom is still the faster path.
              </P>

              <H2 id="performance">Native macOS performance</H2>
              <P>
                Loom&apos;s desktop app is built on Electron. Better Shot is built with Swift and AppKit.
                The difference shows up in three places: CPU usage during recording, battery drain,
                and memory consumption. A native app that does not bundle a browser to render its UI
                starts lighter and stays lighter through a long recording session.
              </P>
              <P>
                Better Shot writes fragmented MP4, which means every frame is committed to disk as it
                arrives. If the app crashes, if the machine loses power, or if you force-quit
                mid-recording, the file is playable up to the last written frame. Loom does not offer
                this guarantee.
              </P>

              <H2 id="comparison">Side-by-side comparison</H2>
              <div className="my-8 overflow-x-auto rounded-2xl border border-zinc-200">
                <table className="w-full min-w-[520px] border-collapse text-[14px]">
                  <thead>
                    <tr className="bg-zinc-50">
                      <th className={th}>Feature</th>
                      <th className={th}>Loom Business</th>
                      <th className={th}>Better Shot</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      ["Price", "$18/seat/mo", "Free forever"],
                      ["Open source", "No", "BSD 3 Clause"],
                      ["Cursor auto-zoom", "No", "30 Hz, spring-damped"],
                      ["Face cam", "Yes", "Yes, composited live"],
                      ["Editing", "Trim slider", "Multi-clip timeline"],
                      ["Captions", "Server-side transcript", "On-device, timeline lane"],
                      ["Speed control", "Playback only", "0.25x to 4x in editor"],
                      ["Hosting", "Loom servers", "Your own R2 bucket"],
                      ["Viewer analytics", "Yes", "No"],
                      ["Comments on video", "Yes", "No"],
                      ["Recording limit", "5 min (free), unlimited (paid)", "Unlimited"],
                      ["Watermark", "On free tier", "Never"],
                      ["Crash recovery", "No", "Fragmented MP4"],
                      ["Platform", "Mac, Windows, Chrome", "macOS 14+"],
                      ["Runtime", "Electron", "Native (Swift, AppKit)"],
                    ].map(([feature, loom, bettershot]) => (
                      <tr key={feature} className="transition-colors hover:bg-zinc-50">
                        <td className={`${td} font-medium`}>{feature}</td>
                        <td className={`${td} text-zinc-500`}>{loom}</td>
                        <td className={`${td} text-zinc-500`}>{bettershot}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <H2 id="cost">What Loom costs over three years</H2>
              <div className="my-8 overflow-x-auto rounded-2xl border border-zinc-200">
                <table className="w-full min-w-[420px] border-collapse text-[14px]">
                  <thead>
                    <tr className="bg-zinc-50">
                      <th className={th}>Tool</th>
                      <th className={`${th} text-right`}>Monthly</th>
                      <th className={`${th} text-right`}>3 years, 1 seat</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      ["Loom Business (monthly)", "$18/mo", "$648"],
                      ["Loom Business (yearly)", "$12.50/mo", "$450"],
                      ["Better Shot", "Free", "$0"],
                    ].map(([tool, monthly, total], i, all) => {
                      const isLast = i === all.length - 1
                      return (
                        <tr key={tool} className="transition-colors hover:bg-zinc-50">
                          <td className={`${td} font-medium ${isLast ? "text-brand" : ""}`}>{tool}</td>
                          <td className={`${td} text-right text-zinc-500`}>{monthly}</td>
                          <td className={`${td} text-right tabular-nums ${isLast ? "font-semibold text-brand" : "text-zinc-500"}`}>
                            {total}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
              <P>
                Prices are as published in August 2026. R2 storage for share links is billed by
                Cloudflare at usage rates and is typically cents per month for screen recordings.
              </P>

              <H2 id="switching">Switching from Loom</H2>
              <OrderedList
                items={[
                  "Install with brew install --cask bettershot, or download the DMG for Apple Silicon or Intel from bettershot.site.",
                  "Grant screen recording permission the first time macOS asks.",
                  "Record a walkthrough you would normally send as a Loom. Use cursor auto-zoom; the clicks become zoom cues automatically.",
                  "Open the recording in the editor. Split, trim, add captions, speed up the slow parts.",
                  "Optional: add a Cloudflare R2 bucket in Settings > Sharing, then hit Share to upload and copy the link.",
                ]}
              />
              <P>
                Existing Loom recordings stay on Loom. Better Shot does not import from Loom, and
                Loom does not offer bulk export. Going forward, new recordings live on your machine
                and (optionally) your R2 bucket.
              </P>

              <H2 id="faq">Common questions</H2>
              <div className="my-8 divide-y divide-zinc-200 rounded-2xl border border-zinc-200">
                <Faq q="Is Better Shot really free?">
                  Yes. BSD 3 Clause licensed open source with no paid tier planned. The cost you carry
                  is that support is GitHub issues, not a support desk.
                </Faq>
                <Faq q="Do I need a Cloudflare R2 bucket?">
                  Only for share links. Without R2, everything else works: capture, record, edit,
                  export. You share files the way you already do.
                </Faq>
                <Faq q="Does it work on Apple Silicon and Intel?">
                  Yes. Separate DMGs for Apple Silicon and Intel. Also available via Homebrew.
                </Faq>
                <Faq q="What about viewer analytics and comments?">
                  Better Shot does not have them. If your team depends on who-watched-what data and
                  threaded comments on every video, Loom earns its price for that use case.
                </Faq>
                <Faq q="Can I use it for client work?">
                  Yes. The BSD 3 Clause license permits commercial use, modification, and
                  redistribution.
                </Faq>
                <Faq q="Does it put a watermark on recordings?">
                  No. There is no watermark at any resolution or length.
                </Faq>
              </div>

              <div className="mt-14 rounded-2xl border border-zinc-200 p-8">
                <h2 className="text-[28px] font-extrabold leading-[34px] tracking-tight">
                  Try it before your Loom renews
                </h2>
                <p className="mb-7 mt-4 max-w-[46ch] text-[16px] leading-[28px] text-zinc-500">
                  Free, open source, macOS 14+. No account, no card, no trial countdown. Record
                  something and compare it side by side.
                </p>
                <div className="flex flex-col items-stretch gap-3 sm:flex-row sm:items-center">
                  <DownloadDropdown release={release} source="cta" className="w-full sm:w-auto" />
                  <Link
                    href="/#compare"
                    className="inline-flex items-center justify-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-700 outline-none transition-colors duration-150 hover:border-zinc-400 hover:bg-zinc-50"
                  >
                    See the feature matrix
                  </Link>
                </div>
              </div>

              <div className="mt-12 border-t border-zinc-200 pt-6">
                <p className="mb-3 text-[13px] font-semibold uppercase tracking-widest text-zinc-400">
                  Sources
                </p>
                <ul className="space-y-2">
                  {[
                    ["Loom pricing", "https://www.loom.com/pricing"],
                    ["Cloudflare R2 pricing", "https://developers.cloudflare.com/r2/pricing/"],
                    ["Better Shot changelog", "https://bettershot.site/changelog"],
                  ].map(([label, href]) => (
                    <li key={href}>
                      <a
                        href={href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[13px] text-zinc-400 underline underline-offset-2 outline-none transition-colors duration-150 hover:text-zinc-700"
                      >
                        {label}
                      </a>
                    </li>
                  ))}
                </ul>
                <p className="mt-4 text-[13px] leading-[22px] text-zinc-400">
                  Competitor pricing and plan limits are as published in August 2026 and change
                  often. Check each vendor&apos;s page for current numbers. Loom is a trademark of
                  Loom, Inc. and is not affiliated with Better Shot.
                </p>
              </div>
            </article>

            <nav aria-label="On this page" className="hidden gap-2.5 py-12 lg:sticky lg:top-20 lg:grid lg:max-w-[220px]">
              <p className="mb-1.5 text-[13px] font-semibold uppercase tracking-widest text-zinc-400">
                On this page
              </p>
              {toc.map((entry) => (
                <a
                  key={entry.id}
                  href={`#${entry.id}`}
                  className="text-[14px] leading-[22px] text-zinc-600 outline-none transition-colors duration-150 hover:text-brand-700"
                >
                  {entry.label}
                </a>
              ))}
            </nav>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}

function H2({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="mb-5 mt-12 scroll-mt-20 text-[28px] font-extrabold leading-[34px] tracking-tight">
      {children}
    </h2>
  )
}

function P({ children }: { children: React.ReactNode }) {
  return <p className="mb-5 text-[17px] leading-[30px] text-zinc-500">{children}</p>
}

function Strong({ children }: { children: React.ReactNode }) {
  return <strong className="font-semibold text-zinc-900">{children}</strong>
}

function Code({ children }: { children: React.ReactNode }) {
  return <code className="rounded bg-zinc-100 px-1.5 py-0.5 font-mono text-[0.92em] text-zinc-700">{children}</code>
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
          className="border-t border-zinc-200 py-3 text-[16px] leading-[28px] text-zinc-500"
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
          className="grid gap-x-6 border-t border-zinc-200 py-3 text-[16px] leading-[28px] text-zinc-500 sm:grid-cols-[32px_minmax(0,1fr)]"
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
    <li className="border-t border-zinc-200 py-3 text-[15px] leading-[24px] text-zinc-500 first:border-t-0 first:pt-0">
      {children}
    </li>
  )
}

function Faq({ q, children }: { q: string; children: React.ReactNode }) {
  return (
    <div className="px-6 py-5">
      <h3 className="mb-2 text-[16px] font-semibold text-zinc-900">{q}</h3>
      <p className="text-[15px] leading-[26px] text-zinc-500">{children}</p>
    </div>
  )
}
