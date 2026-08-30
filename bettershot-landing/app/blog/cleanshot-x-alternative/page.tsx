import type { Metadata } from "next"
import Link from "next/link"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { formatPostDate, getPost } from "@/lib/blog"

const post = getPost("cleanshot-x-alternative")!
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

const thClass = "border-b border-zinc-200 px-3 py-2.5 text-left text-[12px] font-semibold uppercase tracking-widest text-zinc-400"
const tdClass = "border-b border-zinc-100 px-3 py-2.5 text-[14px]"

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
              Better Shot vs CleanShot X: why switch to free
            </h1>
            <p className="mt-6 text-[13px] uppercase tracking-widest text-zinc-400">
              <time dateTime={post.date}>{formatPostDate(post.date)}</time> &middot; {post.readingTime}
            </p>
          </header>

          <div className="h-px bg-zinc-200" />

          <div>
            <article className="mx-auto max-w-[680px] pb-20 pt-12">
              <p className="mb-8 text-[19px] leading-[32px] text-zinc-600">
                CleanShot X is the screenshot tool most Mac power users reach for first. For $29 you
                get scrolling capture, annotations, a quick-access overlay, and one of the most
                polished capture flows on the platform. But $29 is the starting point, not the whole
                price, and a free alternative now covers most of the same ground.
              </p>

              <div className="mb-10 rounded-2xl border border-zinc-200 p-6">
                <p className="mb-4 text-[13px] font-semibold uppercase tracking-widest text-brand-700">
                  The short answer
                </p>
                <ul>
                  <TldrItem>
                    <Strong>Screenshots:</Strong> Better Shot matches CleanShot X on region, window, and
                    fullscreen capture with floating preview, pin on top, OCR, and color picker.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Annotations:</Strong> arrows, shapes, text, numbered badges, blur, and
                    spotlight are all there. CleanShot X has a few more specialized tools.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Beautify:</Strong> padding, shadow, corner radius, gradient backgrounds.
                    Both apps do this; Better Shot does it for free.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Bonus:</Strong> Better Shot also does screen recording with cursor auto-zoom,
                    a timeline editor, and on-device captions. CleanShot X does not.
                  </TldrItem>
                </ul>
              </div>

              <H2 id="what-cleanshot-x-does">What CleanShot X does well</H2>
              <P>
                CleanShot X is a dedicated screenshot and screen recording tool for macOS. It launched
                in 2019 and has built a reputation for speed, polish, and a capture flow that stays out
                of your way. The core license is $29 one-time with a year of updates. CleanShot Cloud,
                their hosting service for share links, adds $8 per month.
              </P>
              <P>
                Its standout features: scrolling capture that stitches long pages into a single image,
                a quick-access overlay after every shot, desktop icon hiding, annotation tools with a
                clean toolbar, and a well-designed preferences pane that lets you configure almost
                everything.
              </P>

              <H2 id="what-better-shot-does">What Better Shot does</H2>
              <P>
                Better Shot is a free, open source macOS app that covers screenshots, screen recording,
                video editing, and optional self-hosted sharing. It is BSD 3 Clause licensed, has no
                account system, no trial, and no paid tier. You can read every line of the{" "}
                <A href="https://github.com/KartikLabhshetwar/better-shot">source code</A>.
              </P>
              <P>
                For screenshots specifically, it matches the core CleanShot X workflow: capture a
                region, window, or full screen with a keyboard shortcut, see a floating preview, then
                edit, copy, pin, drag, or dismiss. On top of that, it adds a full screen recording
                suite with cursor auto-zoom, a multi-clip timeline editor, on-device captions, and
                share links on your own Cloudflare R2 bucket.
              </P>

              <H2 id="feature-comparison">Feature-by-feature comparison</H2>
              <div className="my-8 overflow-x-auto rounded-2xl border border-zinc-200">
                <table className="w-full min-w-[520px] border-collapse text-[14px]">
                  <thead>
                    <tr className="bg-zinc-50">
                      <th className={thClass}>Feature</th>
                      <th className={thClass}>CleanShot X</th>
                      <th className={thClass}>Better Shot</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      ["Region capture", "Yes", "Yes"],
                      ["Window capture", "Yes", "Yes"],
                      ["Fullscreen capture", "Yes", "Yes"],
                      ["Scrolling capture", "Yes", "No"],
                      ["Floating preview", "Yes", "Yes"],
                      ["Pin screenshot on top", "Yes", "Yes"],
                      ["OCR text extraction", "Yes", "Yes"],
                      ["Color picker", "Yes", "Yes (HEX, RGB, HSL)"],
                      ["Annotations (arrows, shapes, text)", "Yes", "Yes"],
                      ["Numbered badges", "No", "Yes"],
                      ["Blur and pixelate", "Yes", "Yes"],
                      ["Backgrounds and beautify", "Yes", "Yes"],
                      ["Screen recording", "Basic", "Full (cursor zoom, face cam)"],
                      ["Video timeline editor", "No", "Yes (multi-clip)"],
                      ["On-device captions", "No", "Yes"],
                      ["Share links (self-hosted)", "Cloud ($8/mo)", "R2 bucket (your storage)"],
                      ["Price", "$29 + Cloud", "Free"],
                      ["Open source", "No", "Yes (BSD 3)"],
                    ].map(([feature, cleanshot, bettershot]) => (
                      <tr key={feature} className="transition-colors hover:bg-zinc-50">
                        <td className={`${tdClass} font-medium text-zinc-900`}>{feature}</td>
                        <td className={`${tdClass} text-zinc-600`}>{cleanshot}</td>
                        <td className={`${tdClass} text-zinc-600`}>{bettershot}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <H2 id="screenshots">Screenshots: the core workflow</H2>
              <P>
                Both apps use the same muscle memory. <Code>Cmd+Shift+4</Code> for a region,{" "}
                <Code>Cmd+Shift+3</Code> for the screen, <Code>Cmd+Shift+5</Code> for a window.
                After every capture a floating preview appears in the corner. From that preview you
                can open the editor, copy the image, pin it above your work, or drag the file
                directly into another app.
              </P>
              <P>
                The capture quality is identical: both use the native macOS APIs, both capture at
                Retina resolution, and both let you save to the clipboard, desktop, or a custom
                folder.
              </P>
              <P>
                Better Shot also includes <Strong>OCR text extraction</Strong> with a dedicated
                shortcut (<Code>Cmd+Shift+O</Code>), built on Apple&apos;s Vision framework. And a
                system-wide <Strong>color picker</Strong> on <Code>Cmd+Shift+C</Code> that copies
                HEX, RGB, or HSL.
              </P>

              <H2 id="annotations">Annotation tools</H2>
              <P>
                Both apps let you draw on a screenshot before saving it. Better Shot has arrows,
                rectangles, circles, freehand drawing, text with font control, numbered step badges,
                blur, pixelate, and spotlight, each with a single-key shortcut.
              </P>
              <P>
                CleanShot X offers a similar set plus a few extras: a counter tool, a crop that
                preserves the shadow, and a wider range of arrow and line styles. If you spend most
                of your day annotating bug reports, CleanShot X has more specialized tools for that
                specific job.
              </P>
              <P>
                For the beautify workflow (padding, shadow, corner radius, background), both apps
                produce similar results. Better Shot supports solid colors, gradients, macOS
                wallpapers, or your own image as a background, with auto-apply so every capture comes
                out styled without opening the editor.
              </P>

              <H2 id="video-bonus">The feature CleanShot X does not have</H2>
              <P>
                This is where the comparison stops being apples to apples. Better Shot includes a
                full screen recording suite that CleanShot X does not match:
              </P>
              <List
                items={[
                  "Cursor auto-zoom: pointer sampled at 30 Hz, clicks become smooth zoom cues, a 4K screen stays readable in a small player",
                  "Face cam bubble composited live during recording",
                  "Microphone and system audio on separate tracks (macOS 15+)",
                  "Multi-clip timeline editor: split, trim, speed (0.25x to 4x), transitions, 3D tilt, color grading",
                  "On-device captions via Apple's speech framework, audio never leaves your Mac",
                  "Share from your own Cloudflare R2 bucket, no vendor hosting, no per-seat pricing",
                  "Fragmented MP4 writing: crash mid-recording, keep the file",
                ]}
              />
              <P>
                If you currently use CleanShot X for screenshots and Loom or another tool for screen
                recordings, Better Shot replaces both with one free app.
              </P>

              <H2 id="where-cleanshot-wins">Where CleanShot X still wins</H2>
              <P>
                A fair comparison names the gaps. Here is what CleanShot X does better:
              </P>
              <ul className="my-8">
                {[
                  {
                    area: "Scrolling capture",
                    detail:
                      "CleanShot X can stitch a long web page or document into a single image. Better Shot does not have this feature yet. If scrolling capture is central to your workflow, that alone may keep you on CleanShot X.",
                  },
                  {
                    area: "UI polish",
                    detail:
                      "CleanShot X has been shipping since 2019 and every pixel shows it. Preferences, toolbar layout, and edge-case handling are a step ahead in overall fit and finish.",
                  },
                  {
                    area: "CleanShot Cloud",
                    detail:
                      "If you want hosted share links without configuring anything, CleanShot Cloud works out of the box for $8/month. Better Shot requires setting up an R2 bucket yourself.",
                  },
                  {
                    area: "Annotation depth",
                    detail:
                      "A wider range of arrow styles, line widths, counter tools, and annotation presets. For heavy daily annotation work, CleanShot X has the edge.",
                  },
                ].map((row) => (
                  <li
                    key={row.area}
                    className="border-t border-zinc-200 py-3.5 sm:grid sm:grid-cols-[minmax(0,160px)_minmax(0,1fr)] sm:gap-x-8"
                  >
                    <span className="text-[15px] font-semibold leading-[24px]">{row.area}</span>
                    <span className="text-[15px] leading-[24px] text-zinc-600">{row.detail}</span>
                  </li>
                ))}
              </ul>

              <H2 id="cost">What it costs</H2>
              <div className="my-8 overflow-x-auto rounded-2xl border border-zinc-200">
                <table className="w-full min-w-[420px] border-collapse text-[14px]">
                  <thead>
                    <tr className="bg-zinc-50">
                      <th className={thClass}>Plan</th>
                      <th className={`${thClass} text-right`}>Price</th>
                      <th className={`${thClass} text-right`}>3 years</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      ["CleanShot X (license only)", "$29 one-time", "$29"],
                      ["CleanShot X + Cloud", "$29 + $8/mo", "$317"],
                      ["CleanShot X + Cloud (renewal)", "$29 + $19 updates/yr + $8/mo", "$355"],
                      ["Better Shot", "Free", "$0"],
                    ].map(([plan, price, total], i, all) => {
                      const isLast = i === all.length - 1
                      return (
                        <tr key={plan} className="transition-colors hover:bg-zinc-50">
                          <td className={`${tdClass} font-medium ${isLast ? "text-brand" : "text-zinc-900"}`}>
                            {plan}
                          </td>
                          <td className={`${tdClass} text-right text-zinc-600`}>{price}</td>
                          <td className={`${tdClass} text-right tabular-nums ${isLast ? "font-semibold text-brand" : "text-zinc-600"}`}>
                            {total}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
              <P>
                CleanShot X pricing is as published in August 2026. The $29 license includes one year
                of updates; after that, a renewal is $19/year for continued updates. Cloud is billed
                monthly. Better Shot&apos;s R2 storage for share links is billed by Cloudflare at
                usage rates, typically a few cents per month for screen recordings.
              </P>

              <H2 id="privacy">Your screenshots, your machine</H2>
              <P>
                Screenshots contain sensitive information: client dashboards, unreleased features,
                internal tools, half-written messages. Better Shot is local-first by construction:
                capture, edit, and export never touch the network unless you explicitly share. There
                is no account, no telemetry, and no analytics in the app. Share links land in a
                bucket you control, which means you can also delete them properly.
              </P>
              <P>
                CleanShot X is also a local app, but CleanShot Cloud routes your screenshots through
                their servers. If you use Cloud for sharing, your screenshots are on someone
                else&apos;s infrastructure.
              </P>

              <H2 id="switching">Switching from CleanShot X</H2>
              <OrderedList
                items={[
                  "Install with brew install --cask bettershot, or download the DMG for Apple Silicon or Intel from bettershot.site.",
                  "Grant screen recording permission when macOS asks. That is the only prompt until you enable the mic or camera.",
                  "Remap shortcuts in Settings if you want your old bindings. The defaults already match the macOS ones.",
                  "Set your default background, padding, and shadow once, and turn on auto-apply so every capture comes out styled.",
                  "Optional: add a Cloudflare R2 bucket in Settings > Sharing if you want share links.",
                ]}
              />
              <P>
                Keep CleanShot X installed for a week and use whichever opens first. Most people stop
                reaching for the paid one within a few days. The exception is scrolling capture: if
                you rely on it daily, you will notice the gap.
              </P>

              <H2 id="faq">Common questions</H2>
              <div className="my-8 divide-y divide-zinc-200 rounded-2xl border border-zinc-200">
                <Faq q="Is there a catch to it being free?">
                  No. It is BSD 3 Clause licensed open source, maintained in public, with no paid tier
                  planned. The trade-off is that support is GitHub issues, not a support desk.
                </Faq>
                <Faq q="Does it put a watermark on screenshots or exports?">
                  No. There is no watermark at any resolution or file size, because there are no tiers
                  to upsell you to.
                </Faq>
                <Faq q="Can I use it for client work?">
                  Yes. The BSD 3 Clause license permits commercial use, modification, and
                  redistribution.
                </Faq>
                <Faq q="Does it support scrolling capture?">
                  Not yet. If scrolling capture is essential, keep CleanShot X for that. Everything
                  else works in Better Shot.
                </Faq>
                <Faq q="Does it record screen too?">
                  Yes. Cursor auto-zoom, face cam, on-device captions, multi-clip timeline editing,
                  and share links on your own R2 bucket. This is the main reason people switch from
                  CleanShot X: they get screenshots and screen recording in one free app.
                </Faq>
                <Faq q="What macOS version do I need?">
                  macOS 14 (Sonoma) or later. Microphone capture during recordings requires macOS 15
                  because that is where ScreenCaptureKit added it.
                </Faq>
              </div>

              <div className="mt-14 rounded-2xl border border-zinc-200 p-8">
                <h2 className="text-[28px] leading-tight tracking-tight">
                  Try it before your next renewal
                </h2>
                <p className="mb-7 mt-4 max-w-[46ch] text-[16px] leading-[28px] text-zinc-600">
                  Free, open source, macOS 14+. No account, no card, no trial countdown. Compare it
                  side by side with what you pay for now.
                </p>
                <div className="flex flex-col items-stretch gap-3 sm:flex-row sm:items-center">
                  <DownloadDropdown release={release} source="cta" className="w-full sm:w-auto" />
                  <Link
                    href="/#compare"
                    className="inline-flex items-center justify-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-900 outline-none transition-colors duration-150 hover:border-zinc-400 hover:bg-zinc-50"
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
                    ["CleanShot X pricing", "https://cleanshot.com/pricing"],
                    ["Better Shot changelog", "https://bettershot.site/changelog"],
                    ["Better Shot source", "https://github.com/KartikLabhshetwar/better-shot"],
                  ].map(([label, href]) => (
                    <li key={href}>
                      <a
                        href={href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[13px] text-zinc-400 underline underline-offset-2 outline-none transition-colors duration-150 hover:text-zinc-600"
                      >
                        {label}
                      </a>
                    </li>
                  ))}
                </ul>
                <p className="mt-4 text-[13px] leading-[22px] text-zinc-400">
                  Competitor pricing and plan limits are as published in August 2026 and change
                  often. Check each vendor&apos;s page for current numbers. CleanShot X is a
                  trademark of its respective owner and is not affiliated with Better Shot.
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
    <h2 id={id} className="mb-5 mt-12 scroll-mt-20 text-[28px] leading-tight tracking-tight">
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
          <span className="font-semibold tabular-nums text-brand-700">
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
    <div className="px-6 py-5">
      <h3 className="mb-2 text-[16px] font-semibold text-zinc-900">{q}</h3>
      <p className="text-[15px] leading-[26px] text-zinc-600">{children}</p>
    </div>
  )
}
