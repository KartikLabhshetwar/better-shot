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
                If the last version of BetterShot felt like a screen recorder that happened to take
                screenshots, this one is a proper screenshot and recording app. New editors, a capture
                deck, a media gallery, 75 shortcuts, a URL scheme, five cursor styles, and a
                three-step onboarding that gets out of the way. The 0.5 series is the biggest update
                since the native rewrite, and every piece of it ships today.
              </p>

              <div className="mb-10 rounded-2xl border border-zinc-200 p-6">
                <p className="mb-4 text-[13px] font-semibold uppercase tracking-widest text-brand-700">
                  The short version
                </p>
                <ul>
                  <TldrItem>
                    <Strong>Editors rebuilt:</Strong> a focused image editor with one toolbar, a
                    video editor with tabbed inspectors, compact frosted chrome, and shared
                    backgrounds. Closer to CleanShot X than anything free.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Capture deck:</Strong> up to five screenshots in a floating stack with
                    copy, save, pin, edit, cloud share, and drag-out. Stage captures until you are
                    ready.
                  </TldrItem>
                  <TldrItem>
                    <Strong>75 shortcuts and URL scheme:</Strong> every action is bindable. Trigger
                    anything from Raycast, Alfred, Shortcuts, or a shell script.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Media Gallery:</Strong> browse, search, filter, edit, and delete
                    captures and recordings. Manage cloud links without leaving the app.
                  </TldrItem>
                  <TldrItem>
                    <Strong>Community:</Strong> six PRs merged from contributors. Capture on release,
                    auto-save recordings, deck copy fix, save behavior fix, cursor fix, and the
                    URL scheme itself.
                  </TldrItem>
                </ul>
              </div>

              <H2 id="editors">The editors, rebuilt</H2>
              <P>
                The old image editor had tools scattered between a toolbar and a sidebar, background
                settings in two places, and controls that looked nothing like the video editor next
                to them. That is gone. Both editors now share the same design language: a left
                inspector with compact frosted chrome, label-in-track sliders, and a consistent
                blue selection accent. The image editor has one toolbar. The video editor has five
                tabs: Background, Cursor, Camera, Effects, and Zoom &amp; Clips.
              </P>
              <P>
                If you have used CleanShot X, this will feel familiar. The inspector is on the left.
                Controls are compact. There is no wall of disclosure triangles. The difference is
                that BetterShot gives you a full video editor in the same window, and both editors
                share the same backgrounds, gradients, and default look.
              </P>
              <List
                items={[
                  "One toolbar for annotation tools, color, and style. No duplicates in the sidebar.",
                  "Background owns canvas settings: padding, corner radius, shadow, and ten soft gradients (Blush, Peach, Mint, Powder Blue, Butter, Lilac, Sage, Coral, Aqua, Mauve).",
                  "General > Default Look supplies shared defaults for new images and videos. Saved projects keep their own settings.",
                  "Video inspector tabs are expanded by default. No outer disclosure chevrons.",
                  "Label-in-track sliders everywhere: JPEG quality, preview margin, timeline zoom, all with exact value entry.",
                  "Frosted chrome, subtle borders, compact spacing, and readable disabled states in both light and dark.",
                ]}
              />
              <blockquote className="my-9 max-w-[34ch] border-l-2 border-brand pl-6 text-[clamp(24px,2.6vw,30px)] leading-[1.24] tracking-tight">
                The best screenshot app is the one you never think about.
              </blockquote>

              <H2 id="capture-deck">Capture deck</H2>
              <P>
                This is the feature that makes daily use feel different. Take a screenshot, and
                it appears in a floating stack at the corner of your screen. Take another, it
                stacks on top. Up to five captures sit there, each with its own dismiss timer and
                a set of actions: Copy, Save, Pin, Edit, cloud share, and drag-out.
              </P>
              <P>
                When &quot;Keep screenshots in the deck until saved&quot; is on, captures stay in the
                deck until you explicitly save or promote them. Copy puts the image on your
                clipboard without writing to disk. Dismissing an unsaved card deletes it.
                This is the staging workflow people loved in CleanShot X, and it works the same way
                here.
              </P>
              <List
                items={[
                  "Small, Medium, or Large card sizes with adjustable edge margin (0 to 48 pt).",
                  "Cloud share directly from a deck card with progress, retry, and automatic link copying.",
                  "Six overlay positions, configurable in Settings > Overlay with Standard, Sharing, and Minimal presets.",
                  "Copy writes to clipboard only. Save, Pin, Edit, and drag-out promote the capture.",
                  "Save All commits the entire deck. Clear All dismisses it.",
                ]}
              />

              <H2 id="cursor-styles">Five cursor styles</H2>
              <P>
                The pointer is no longer burned into the recording. BetterShot captures the cursor
                path, click positions, and cursor shape as separate data, then draws it back in the
                editor. You can restyle the cursor after the fact.
              </P>
              <List
                items={[
                  "Recorded: the exact cursor you had during capture.",
                  "Dark, Light, Dot: generated from vector paths with transparent backgrounds and contrast outlines.",
                  "Hand: native macOS pointingHand artwork, highest-resolution representation preserved.",
                  "Natural or Smooth motion, adjustable size, press and ripple effects, idle hiding.",
                  "Cursor choices persist with the project and match between preview, export, and shared video.",
                ]}
              />

              <H2 id="shortcuts">75 customizable shortcuts</H2>
              <P>
                The shortcut system was rebuilt from scratch. Every action in the app, across seven
                categories, is listed in Settings &gt; Shortcuts. Search by name, filter by
                category, record a new binding, check for conflicts, or reset to defaults. The
                seven categories: general, screenshots, OCR and color, recording, capture deck,
                image tools, and video editing.
              </P>
              <P>
                Default bindings are preserved on upgrade. New actions start unassigned. Editor
                shortcuts take priority over global ones when the editor is focused. Text fields
                retain native typing, copy/paste, and undo.
              </P>

              <H2 id="url-scheme">URL scheme for automation</H2>
              <P>
                BetterShot registers <Code>bettershot://</Code> URLs. Trigger any capture action
                without touching the menu bar.
              </P>
              <div className="my-8 overflow-x-auto rounded-2xl border border-zinc-200">
                <table className="w-full min-w-[420px] border-collapse text-[14px]">
                  <thead>
                    <tr className="bg-zinc-50">
                      <th className={th}>URL</th>
                      <th className={th}>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      ["bettershot://capture/region", "Region screenshot"],
                      ["bettershot://capture/fullscreen", "Fullscreen screenshot"],
                      ["bettershot://capture/window", "Window screenshot"],
                      ["bettershot://ocr", "OCR text extraction"],
                      ["bettershot://color-picker", "Hex color picker"],
                      ["bettershot://record", "Start recording"],
                      ["bettershot://settings", "Open Settings"],
                    ].map(([scheme, action]) => (
                      <tr key={scheme} className="transition-colors hover:bg-zinc-50">
                        <td className={`${td} font-mono text-[13px] text-brand-700`}>{scheme}</td>
                        <td className={`${td} text-zinc-600`}>{action}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <P>
                Add a Raycast command, an Alfred workflow, a Shortcuts action, or a shell alias.
                Unknown or malformed URLs are silently ignored, and the recording guard prevents
                stacking on an active session.
              </P>

              <H2 id="media-gallery">Media Gallery</H2>
              <P>
                Open it from the menu tray or General settings. A resizable native window with a
                left sidebar, larger thumbnails, screenshot/video and Local/Cloud filters, search,
                and newest/oldest sorting. Each card offers Edit, Reveal, and cloud link actions.
              </P>
              <P>
                Local deletion moves files to Trash while preserving cloud share links. Cloud
                deletion removes the shared copy from R2 while preserving local files. Both require
                confirmation. Errors stay beside the action for retry instead of flashing and
                disappearing.
              </P>

              <H2 id="onboarding">Three-step onboarding</H2>
              <P>
                Welcome, Permissions, First Capture. That is the entire setup. Optional silent
                six-second demo videos show how screenshots and recordings work. Screen access is
                marked required; microphone, camera, accessibility, and input monitoring are
                optional. Finish by opening the capture bar or editing a practice image. No
                autoplay, no looping, no network dependency.
              </P>

              <H2 id="capture-and-recording">Capture and recording improvements</H2>
              <List
                items={[
                  "Capture on mouse release: a Settings > Capture toggle takes the screenshot the moment you release the mouse, matching the classic draw-and-release gesture.",
                  "Auto-save recordings: finished recordings save to your folder automatically. Manual Save on deck cards writes recordings too.",
                  "One shared capture and recording bar: Area, Fullscreen, Window, OCR, Color, Timer, and Recording in one compact glass bar.",
                  "Adjustable recording areas with drag, resize, Return/double-click confirmation, and Escape to cancel.",
                  "Cmd+S in the image editor updates the previously exported file on disk, not just internal history.",
                ]}
              />

              <H2 id="everything-else">Settings, installer, and polish</H2>
              <List
                items={[
                  "Overlay settings: Standard, Sharing, and Minimal presets. Click any of six positions in the layout preview to move, swap, or hide tools.",
                  "Startup controls: Launch at Login, Show in Dock, Show in Menu Bar.",
                  "DMG installer: Retina-ready lavender background, clover volume icon, aligned drag-to-Applications layout.",
                  "Button contrast fixed in both light and dark appearances.",
                  "Editor shortcuts use configured bindings instead of parallel hard-coded keys.",
                  "Failed saves retain captures with retry guidance instead of discarding them.",
                  "SF Symbols for all action icons. No third-party icon packs.",
                ]}
              />

              <H2 id="community">Six community PRs</H2>
              <P>
                Every one of these started as a GitHub issue filed by a user, then a pull request
                from a contributor. Reviewed, tested, and merged.
              </P>
              <div className="my-8 overflow-x-auto rounded-2xl border border-zinc-200">
                <table className="w-full min-w-[520px] border-collapse text-[14px]">
                  <thead>
                    <tr className="bg-zinc-50">
                      <th className={th}>Fix</th>
                      <th className={th}>Issue</th>
                      <th className={th}>PR</th>
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
                        <td className={`${td} font-medium`}>{fix}</td>
                        <td className={`${td} text-zinc-600`}>
                          <a
                            href={`https://github.com/KartikLabhshetwar/better-shot/issues/${issue.slice(1)}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-brand-700 underline underline-offset-2 hover:text-brand"
                          >
                            {issue}
                          </a>
                        </td>
                        <td className={`${td} text-zinc-600`}>
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
                for all six. And thanks to{" "}
                <a
                  href="https://github.com/BradleyAllanDavis"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-700 underline underline-offset-2 hover:text-brand"
                >
                  @BradleyAllanDavis
                </a>{" "}
                for the preview sizing and placement work that shipped in 0.5.0.
              </P>

              <H2 id="upgrading">Get it</H2>
              <P>
                Existing users: check for updates in the app, or
                run <Code>brew upgrade --cask bettershot</Code>. New
                users: <Code>brew install --cask bettershot</Code> or download the DMG
                from{" "}
                <a
                  href="https://github.com/KartikLabhshetwar/better-shot/releases"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-700 underline underline-offset-2 hover:text-brand"
                >
                  GitHub Releases
                </a>
                . All preferences and shortcuts are preserved on upgrade. New shortcut
                actions start unassigned.
              </P>
              <P>
                The full changelog for{" "}
                <a
                  href="/changelog#v0-5-0"
                  className="text-brand-700 underline underline-offset-2 hover:text-brand"
                >
                  0.5.0
                </a>
                ,{" "}
                <a
                  href="/changelog#v0-5-1"
                  className="text-brand-700 underline underline-offset-2 hover:text-brand"
                >
                  0.5.1
                </a>
                , and{" "}
                <a
                  href="/changelog#v0-5-2"
                  className="text-brand-700 underline underline-offset-2 hover:text-brand"
                >
                  0.5.2
                </a>{" "}
                is on the changelog page.
              </P>

              <div className="mt-14 rounded-2xl border border-zinc-200 p-8">
                <h2 className="text-[28px] leading-[34px] tracking-tight">
                  Try BetterShot 0.5
                </h2>
                <p className="mb-7 mt-4 max-w-[46ch] text-[16px] leading-[28px] text-zinc-600">
                  Free, open source, macOS 26.0+. Screenshots, recording, and editing in one
                  native app. No account, no subscription.
                </p>
                <div className="flex flex-col items-stretch gap-3 sm:flex-row sm:items-center">
                  <DownloadDropdown release={release} source="cta" className="w-full sm:w-auto" />
                  <Link
                    href="/#compare"
                    className="inline-flex items-center justify-center rounded-xl border border-zinc-200 px-5 py-3 text-[15px] font-semibold text-zinc-700 outline-none transition-colors duration-150 hover:border-zinc-400 hover:bg-zinc-50"
                  >
                    See how it compares
                  </Link>
                </div>
              </div>

              <div className="mt-12 border-t border-zinc-200 pt-6">
                <p className="mb-3 text-[13px] font-semibold uppercase tracking-widest text-zinc-400">
                  Links
                </p>
                <ul className="space-y-2">
                  {[
                    ["Full changelog", "https://bettershot.site/changelog"],
                    ["GitHub repository", "https://github.com/KartikLabhshetwar/better-shot"],
                    ["Feature comparison", "https://bettershot.site/#compare"],
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
