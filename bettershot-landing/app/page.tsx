import Image from "next/image"
import Link from "next/link"
import { ArrowUpRight } from "lucide-react"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { getChangelog } from "@/lib/changelog"
import { StarCount } from "@/components/star-count"
import { EditorPreview } from "@/components/editor-demo"

export default async function Home() {
  const release = await getLatestRelease()
  const changelog = getChangelog()

  return (
    <div className="min-h-screen w-full bg-[#fafaf9] text-[#111] selection:bg-[#e78a53]/20">
      {/* Nav */}
      <nav className="fixed top-0 inset-x-0 z-50 h-14 backdrop-blur-xl bg-[#fafaf9]/80">
        <div className="max-w-[960px] mx-auto h-full px-6 flex items-center justify-between">
          <a href="/" className="flex items-center gap-2.5">
            <Image src="/logo.png" alt="" width={22} height={22} className="rounded-[5px]" />
            <span className="text-[13px] font-medium tracking-[-0.01em] text-[#111]/50">
              Better Shot
            </span>
          </a>
          <div className="flex items-center gap-5">
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[12px] text-[#111]/25 hover:text-[#111]/50 transition-colors"
            >
              <StarCount />
            </a>
            <DownloadDropdown release={release} source="navbar" size="sm" showLabel={false} />
          </div>
        </div>
      </nav>

      {/* Hero */}
      <main className="pt-14">
        <section className="flex flex-col items-center px-6 pt-28 pb-20">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-[#111]/[0.06] bg-[#111]/[0.02] mb-8">
            <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
            <span className="text-[11px] font-medium text-[#111]/35 tracking-wide uppercase">
              Free &amp; open source
            </span>
          </div>

          <h1 className="text-center text-[clamp(36px,6.5vw,64px)] leading-[1.05] font-semibold tracking-[-0.035em] text-[#111] max-w-[680px] text-balance">
            Screenshots that look like you tried
          </h1>

          <p className="text-center text-[15px] leading-[1.7] text-[#111]/40 mt-5 max-w-[400px] text-pretty">
            Capture, record, annotate, beautify. A local-first screenshot &amp; recording tool for macOS — no account, no cloud, no tracking.
          </p>

          <div className="flex items-center gap-3 mt-10">
            <DownloadDropdown release={release} source="hero" />
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 px-4 h-10 text-[13px] font-medium text-[#111]/30 hover:text-[#111]/55 border border-[#111]/[0.08] hover:border-[#111]/[0.15] rounded-lg transition-all"
            >
              Source
              <ArrowUpRight className="h-3.5 w-3.5" />
            </a>
          </div>

          <div className="flex items-center gap-6 mt-8 text-[11px] text-[#111]/20">
            <span>macOS 14+</span>
            <span className="h-3 w-px bg-[#111]/8" />
            <span>Apple Silicon &amp; Intel</span>
            <span className="h-3 w-px bg-[#111]/8" />
            <span>Homebrew</span>
          </div>
        </section>

        {/* Screenshot preview */}
        <section className="max-w-[880px] mx-auto px-6 pb-24">
          <div className="rounded-xl border border-[#111]/[0.06] bg-[#111]/[0.02] p-2 overflow-hidden">
            <EditorPreview />
          </div>
        </section>

        {/* Features — linear list */}
        <section className="max-w-[960px] mx-auto px-6 pb-28">
          <div className="border-t border-[#111]/[0.06]" />

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-0 divide-y md:divide-y-0 md:divide-x divide-[#111]/[0.06]">
            <Feature
              title="Capture"
              items={[
                "Region, fullscreen, window",
                "OCR text + QR/barcode scanning",
                "Color picker (hex to clipboard)",
                "Self-timer countdown (3s/5s/10s)",
                "Customizable keyboard shortcuts",
              ]}
            />
            <Feature
              title="Record"
              items={[
                "Full screen or single window",
                "Hover-and-click window picker",
                "Pause, resume, discard controls",
                "Configurable FPS (24/30/60)",
                "Optional cursor & audio capture",
              ]}
            />
            <Feature
              title="Annotate"
              items={[
                "Arrows, shapes, freehand drawing",
                "Text with font, size, bold, italic",
                "Pixelate & blur redaction",
                "Numbered callout badges",
                "Spotlight to highlight regions",
              ]}
            />
            <Feature
              title="Beautify"
              items={[
                "Works on screenshots & recordings",
                "Backgrounds, padding, shadow, radius",
                "Bundled macOS wallpapers",
                "Video editor with trim timeline",
                "Export as PNG, JPEG, or MOV",
              ]}
            />
          </div>
        </section>

        {/* Workflow extras */}
        <section className="max-w-[960px] mx-auto px-6 pb-20">
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-6">
            {[
              { label: "Click-to-edit", desc: "Floating preview opens the editor" },
              { label: "Pin screenshots", desc: "Always-on-top floating windows" },
              { label: "Drag-to-app", desc: "Drag from preview into Figma, Slack, etc." },
              { label: "Video editor", desc: "Trim, beautify, and export recordings" },
              { label: "Capture history", desc: "Separate tabs for screenshots & videos" },
              { label: "In-app updates", desc: "Download and install without leaving the app" },
            ].map((item) => (
              <div key={item.label} className="text-center">
                <p className="text-[13px] font-medium text-[#111]/50">{item.label}</p>
                <p className="text-[11px] text-[#111]/25 mt-1 leading-[1.5]">{item.desc}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Shortcuts */}
        <section className="max-w-[480px] mx-auto px-6 pb-28">
          <h2 className="text-[13px] font-medium text-[#111]/20 tracking-wide uppercase text-center mb-8">
            Keyboard shortcuts
          </h2>
          <div className="space-y-0 divide-y divide-[#111]/[0.06] border-y border-[#111]/[0.06] rounded-lg overflow-hidden bg-[#111]/[0.015]">
            <Shortcut label="Capture region" keys={["⌘", "⇧", "4"]} />
            <Shortcut label="Capture screen" keys={["⌘", "⇧", "3"]} />
            <Shortcut label="Capture window" keys={["⌘", "⇧", "5"]} />
            <Shortcut label="Record screen" keys={["⌘", "⇧", "2"]} />
            <Shortcut label="OCR + QR scan" keys={["⌘", "⇧", "O"]} />
            <Shortcut label="Color picker" keys={["⌘", "⇧", "C"]} />
          </div>
        </section>

        {/* Changelog */}
        <section className="max-w-[640px] mx-auto px-6 pb-28">
          <h2 className="text-[13px] font-medium text-[#111]/20 tracking-wide uppercase text-center mb-8">
            Changelog
          </h2>
          <div className="space-y-10">
            {changelog.map((ver) => (
              <div key={ver.version}>
                <div className="flex items-baseline justify-between mb-4 pb-3 border-b border-[#111]/[0.06]">
                  <span className="text-[13px] font-semibold text-[#111]/60 tracking-[-0.01em]">
                    v{ver.version}
                  </span>
                  <span className="text-[11px] text-[#111]/25 font-mono">{ver.date}</span>
                </div>
                <div className="space-y-5">
                  {ver.sections.map((section) => (
                    <div key={section.label}>
                      <p className="text-[11px] font-medium text-[#111]/30 uppercase tracking-wide mb-2">
                        {section.label}
                      </p>
                      <ul className="space-y-1.5">
                        {section.items.map((item, i) => (
                          <li key={i} className="flex items-start gap-2.5">
                            <span className="mt-[7px] h-1 w-1 rounded-full bg-[#111]/15 shrink-0" />
                            <span className="text-[13px] leading-[1.6] text-[#111]/35">{item}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* CTA */}
        <section className="border-t border-[#111]/[0.06] py-20">
          <div className="text-center px-6">
            <p className="text-[15px] text-[#111]/30 mb-6 text-pretty">
              No account. No subscription. Just a better screenshot tool.
            </p>
            <div className="flex flex-col items-center gap-4">
              <DownloadDropdown release={release} source="cta" />
              <p className="text-[12px] text-[#111]/20 font-mono">
                brew install --cask bettershot
              </p>
            </div>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-[#111]/[0.04]">
        <div className="max-w-[960px] mx-auto px-6 py-6 flex items-center justify-between">
          <p className="text-[11px] text-[#111]/15">
            &copy; {new Date().getFullYear()} Better Shot
          </p>
          <nav className="flex items-center gap-5">
            <a
              href="https://x.com/code_kartik"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[11px] text-[#111]/15 hover:text-[#111]/40 transition-colors"
            >
              Twitter
            </a>
            <Link
              href="/privacy"
              className="text-[11px] text-[#111]/15 hover:text-[#111]/40 transition-colors"
            >
              Privacy
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  )
}

function Feature({ title, items }: { title: string; items: string[] }) {
  return (
    <div className="py-10 md:px-8 first:md:pl-0 last:md:pr-0">
      <h3 className="text-[13px] font-semibold text-[#111]/60 tracking-[-0.01em] mb-4">{title}</h3>
      <ul className="space-y-2.5">
        {items.map((item) => (
          <li key={item} className="flex items-start gap-2.5">
            <span className="mt-[7px] h-1 w-1 rounded-full bg-[#111]/15 shrink-0" />
            <span className="text-[13px] leading-[1.6] text-[#111]/35">{item}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Shortcut({ label, keys }: { label: string; keys: string[] }) {
  return (
    <div className="flex items-center justify-between px-4 py-3">
      <span className="text-[13px] text-[#111]/40">{label}</span>
      <div className="flex items-center gap-1">
        {keys.map((k, i) => (
          <kbd
            key={i}
            className="inline-flex items-center justify-center h-6 min-w-[24px] px-1.5 text-[11px] font-medium text-[#111]/50 bg-white border border-[#111]/[0.08] rounded shadow-[0_1px_0_rgba(0,0,0,0.04)]"
          >
            {k}
          </kbd>
        ))}
      </div>
    </div>
  )
}
