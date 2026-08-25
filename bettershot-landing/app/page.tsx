import Link from "next/link"
import { ArrowUpRightIcon, GithubLogoIcon } from "@phosphor-icons/react/dist/ssr"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { Reveal } from "@/components/reveal"
import { SectionLabel } from "@/components/section"
import { CopyCommand } from "@/components/copy-command"
import { Comparison } from "@/components/home/comparison"
import { FaqSection, faqs } from "@/components/home/faq"

const faqJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faqs.map((faq) => ({
    "@type": "Question",
    name: faq.q,
    acceptedAnswer: { "@type": "Answer", text: faq.a },
  })),
}

const stats = [
  { value: "$0", label: "Forever. No tiers, no trial" },
  { value: "0 KB", label: "Uploaded by default" },
  { value: "30 Hz", label: "Pointer sampled while recording" },
  { value: "BSD 3", label: "Clause licensed, auditable" },
]

const features = [
  {
    n: "01",
    title: "Capture",
    tags: ["Region", "Window", "Fullscreen", "OCR", "Color picker", "Pin on top"],
    body: "Region, window, or fullscreen from one shortcut. A floating preview appears after every shot, so you can edit it, copy it, pin it above your work, or drag the file straight into Figma, Slack, or Finder.",
  },
  {
    n: "02",
    title: "Record",
    tags: ["Cursor auto-zoom", "Face cam", "Microphone", "24/30/60 fps", "Pause and resume"],
    body: "Pick a display, a window, or an area. The pointer is sampled at 30 Hz and clicks become smooth zoom moves, so a 4K screen stays readable in a small player. Recordings are written as fragmented MP4 and survive a crash mid-take.",
  },
  {
    n: "03",
    title: "Edit",
    tags: ["Multi-clip timeline", "0.25x to 4x", "Transitions", "3D tilt", "Color grading"],
    body: "Split at the playhead, drag an edge to trim, speed a slow stretch up to 4x, cross into the next clip. Then tilt the card, grade the color, set it on a background, and export MP4.",
  },
  {
    n: "04",
    title: "Overlay",
    tags: ["Captions", "Keystrokes", "Blur and pixelate", "Spotlight", "Canvas text"],
    body: "Captions, keystrokes, masks, and text are timeline lanes you drag and retime next to your zoom cues. Transcription runs on device. A hide mask destroys its pixels in the export, so the password on screen never ships.",
  },
  {
    n: "05",
    title: "Annotate",
    tags: ["Arrows", "Shapes", "Numbered badges", "Crop", "Rule of thirds"],
    body: "Arrows, shapes, text, and numbered badges, each with its key printed in the corner of its button. Backgrounds, padding, shadow, and corner radius make the result presentable without a second app.",
  },
  {
    n: "06",
    title: "Share",
    tags: ["Your own R2 bucket", "Keychain keys", "Direct SigV4", "Edits baked in"],
    body: "Connect a Cloudflare R2 bucket and Share uploads the edited recording straight from the app, then copies the link. No proxy, no vendor in the middle, no viewer limit.",
  },
]

const shortcuts = [
  { label: "Capture region", keys: "⌘ ⇧ 4" },
  { label: "Capture screen", keys: "⌘ ⇧ 3" },
  { label: "Capture window", keys: "⌘ ⇧ 5" },
  { label: "Record screen", keys: "⌘ ⇧ 2" },
  { label: "OCR text scan", keys: "⌘ ⇧ O" },
  { label: "Color picker", keys: "⌘ ⇧ C" },
]

const chip =
  "inline-flex items-center bg-[#f8f4f4] px-2.5 py-[3px] text-[11px] tracking-[0.02em] text-[#444141]"
const chipOutline =
  "inline-flex items-center border border-brand-700 px-2.5 py-[3px] text-[11px] tracking-[0.02em] text-brand-700"
const shell = "mx-auto max-w-[1240px] px-6"
const featureRow =
  "grid gap-6 py-10 sm:py-[42px] lg:grid-cols-[88px_minmax(0,360px)_minmax(0,1fr)] lg:gap-x-[clamp(24px,4vw,72px)]"

export default async function Home() {
  const release = await getLatestRelease()

  return (
    <div className="min-h-screen w-full bg-canvas text-ink">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(faqJsonLd) }}
      />
      <SiteNav />

      <main id="main">
        <Reveal as="section" className={`${shell} pb-14 pt-16 sm:pt-20`}>
          <Link
            href="/changelog"
            className="micro group inline-flex flex-wrap items-baseline gap-x-3 gap-y-1 border border-rule px-3 py-[7px] text-[13px] uppercase text-brand-700 outline-none transition-colors duration-150 hover:border-ink"
          >
            <span className="font-semibold">v{release.version}</span>
            <span className="text-ink/70">Auto-zoom, face cam, share links you own</span>
            <ArrowUpRightIcon size={11} weight="bold" aria-hidden className="text-ink/55" />
          </Link>

          <h1 className="display mt-8 -ml-[0.058em] text-[clamp(42px,6.4vw,88px)]">
            <span className="block">One app for the whole screen.</span>
            <span className="block text-brand">No subscription. No uploads.</span>
          </h1>

          <p className="mt-7 max-w-[60ch] text-[18px] leading-[30px] text-ink/80">
            Better Shot takes the screenshot, records the walkthrough with cursor-tracked zoom,
            captions it on device, and edits it down to the file you send. Native macOS, free, and
            open source. Nothing leaves your Mac unless you say so.
          </p>

          <div className="mt-7 flex flex-wrap items-center gap-3">
            <DownloadDropdown release={release} source="hero" />
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 border-2 border-rule px-6 py-3.5 text-[15px] font-semibold text-ink outline-none transition-colors duration-150 hover:border-ink"
            >
              <GithubLogoIcon size={16} weight="bold" />
              View source
            </a>
          </div>

          <ul className="micro mt-7 flex flex-wrap gap-x-7 gap-y-2 text-[13px] uppercase text-ink/70">
            <li>Free forever</li>
            <li>No account</li>
            <li>macOS 14 and later</li>
            <li>Apple Silicon and Intel</li>
          </ul>
        </Reveal>

        <section className={`${shell} border-t-2 border-rule py-14`} aria-label="Better Shot in numbers">
          <Reveal className="grid grid-cols-2 gap-x-6 gap-y-8 md:grid-cols-4">
            {stats.map((stat) => (
              <div key={stat.value}>
                <p className="-ml-[0.045em] text-[clamp(34px,3.6vw,50px)] font-extrabold leading-[1.05] text-brand">
                  {stat.value}
                </p>
                <p className="micro mt-3.5 text-[13px] uppercase leading-[18px] text-ink/70">
                  {stat.label}
                </p>
              </div>
            ))}
          </Reveal>
        </section>

        <section id="features" className={`${shell} scroll-mt-20 border-t-2 border-rule pb-7 pt-14`}>
          <Reveal>
            <SectionLabel className="mb-3.5">Everything in the box</SectionLabel>
            <h2 className="display -ml-[0.04em] max-w-[24ch] text-[clamp(30px,3.4vw,44px)]">
              One app instead of four subscriptions.
            </h2>
          </Reveal>

          <div className="mt-10 sm:mt-14">
            {features.map((feature, index) => (
              <Reveal
                key={feature.n}
                className={index === 0 ? featureRow : `${featureRow} border-t-2 border-rule`}
              >
                <p className="text-[15px] font-extrabold leading-6 tabular-nums">{feature.n}</p>
                <div>
                  <h3 className="text-[24px] leading-7 tracking-[-0.01em]">{feature.title}</h3>
                  <ul className="mt-4 flex flex-wrap gap-1.5">
                    {feature.tags.map((tag) => (
                      <li key={tag} className={chip}>
                        {tag}
                      </li>
                    ))}
                  </ul>
                </div>
                <p className="max-w-[52ch] text-[16px] leading-[28px] text-ink/80">{feature.body}</p>
              </Reveal>
            ))}
          </div>
        </section>

        <Reveal as="section" className={`${shell} border-t-2 border-rule py-14`}>
          <SectionLabel className="mb-3.5">On device</SectionLabel>
          <h2 className="display-sm text-[32px] leading-[38px]">
            The parts that used to need After Effects
          </h2>
          <p className="mt-6 max-w-[60ch] text-[16px] leading-[28px] text-ink/80">
            The editor transcribes the recording&rsquo;s own audio, collapses typing into words, and
            draws its own pointer from the path you actually moved, so a shaky hand glides. The
            preview draws exactly what the exporter writes.
          </p>
          <ul className="mt-6 flex flex-wrap gap-1.5">
            {["Captions", "Keystroke overlay", "Cursor smoothing", "Scenes and split screen"].map(
              (tag) => (
                <li key={tag} className={chipOutline}>
                  {tag}
                </li>
              ),
            )}
          </ul>
        </Reveal>

        <Comparison />

        <Reveal as="section" className={`${shell} border-t-2 border-rule py-14`}>
          <SectionLabel className="mb-3.5">Shortcuts</SectionLabel>
          <h2 className="display-sm mb-8 text-[32px] leading-[38px]">Six keys, all remappable</h2>
          <ul className="grid gap-0.5 bg-rule sm:grid-cols-2 lg:grid-cols-3">
            {shortcuts.map((shortcut) => (
              <li
                key={shortcut.label}
                className="flex items-baseline justify-between gap-4 bg-canvas px-[18px] py-5"
              >
                <span className="text-[15px] leading-6">{shortcut.label}</span>
                <kbd className="whitespace-nowrap font-sans text-[14px] font-semibold tracking-[0.06em] text-brand-700">
                  {shortcut.keys}
                </kbd>
              </li>
            ))}
          </ul>
        </Reveal>

        <FaqSection />

        <Reveal as="section" className="bg-brand text-canvas">
          <div className={`${shell} py-20 sm:py-[84px]`}>
            <h2 className="display -ml-[0.058em] text-[clamp(34px,4.4vw,60px)]">
              Stop paying to share your screen.
            </h2>
            <p className="mt-6 max-w-[46ch] text-[18px] leading-[30px]">
              Free, open source, and installed in about thirty seconds. No account, no card, no trial
              countdown.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Link
                href="/download"
                className="inline-flex items-center border border-canvas px-5 py-3 text-[15px] font-semibold text-canvas outline-none transition-colors duration-150 hover:bg-canvas hover:text-brand"
              >
                Download for macOS
              </Link>
              <CopyCommand
                command="brew install --cask bettershot"
                className="border border-canvas/55 bg-transparent px-4 py-3 text-[15px] text-canvas hover:border-canvas hover:text-canvas"
              />
            </div>
          </div>
        </Reveal>
      </main>

      <SiteFooter />
    </div>
  )
}
