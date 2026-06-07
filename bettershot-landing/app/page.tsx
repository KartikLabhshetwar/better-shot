import Image from "next/image"
import Link from "next/link"
import { ArrowUpRight } from "lucide-react"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { StarCount } from "@/components/star-count"
import { EditorPreview } from "@/components/editor-demo"

export default async function Home() {
  const release = await getLatestRelease()
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

        {/* What it does — concise vertical blocks */}
        <section className="max-w-[600px] mx-auto px-6 pb-28">
          <div className="border-t border-[#111]/[0.06]" />

          <div className="space-y-16 pt-16">
            <FeatureBlock
              title="Capture everything"
              description="Region, fullscreen, or window screenshots. Screen recording with pause and resume. OCR text extraction and color picker. All from the menu bar or a keyboard shortcut."
            />
            <FeatureBlock
              title="Make it look good"
              description="Add padding, corner radius, and shadows. Pick from solid colors, gradients, or macOS wallpapers as backgrounds. Crop with draggable handles. Works on both screenshots and recordings."
            />
            <FeatureBlock
              title="Annotate with purpose"
              description="Arrows, shapes, text, numbered badges, blur, and spotlight. Each tool has a single-key shortcut. Text supports font selection, bold, italic, and alignment."
            />
            <FeatureBlock
              title="Stay in flow"
              description="Floating preview after every capture. Click to edit, drag into any app. Pin screenshots as always-on-top windows. Auto-apply your default effects on every capture."
            />
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
            <Shortcut label="OCR text scan" keys={["⌘", "⇧", "O"]} />
            <Shortcut label="Color picker" keys={["⌘", "⇧", "C"]} />
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
            <Link
              href="/changelog"
              className="text-[11px] text-[#111]/15 hover:text-[#111]/40 transition-colors"
            >
              Changelog
            </Link>
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

function FeatureBlock({ title, description }: { title: string; description: string }) {
  return (
    <div>
      <h3 className="text-[15px] font-semibold text-[#111]/70 tracking-[-0.01em] mb-2">{title}</h3>
      <p className="text-[14px] leading-[1.7] text-[#111]/35">{description}</p>
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
