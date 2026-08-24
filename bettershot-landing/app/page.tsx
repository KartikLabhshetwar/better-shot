import Link from "next/link"
import { ArrowUpRight, Github, Shield, Sparkles, Zap } from "lucide-react"
import { DownloadDropdown } from "@/components/download-dropdown"
import { getLatestRelease } from "@/lib/downloads"
import { StarCount } from "@/components/star-count"
import { EditorPreview } from "@/components/editor-demo"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { Comparison } from "@/components/home/comparison"
import { FaqSection, SectionLabel, faqs } from "@/components/home/faq"

const faqJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faqs.map((faq) => ({
    "@type": "Question",
    name: faq.q,
    acceptedAnswer: { "@type": "Answer", text: faq.a },
  })),
}

export default async function Home() {
  const release = await getLatestRelease()

  return (
    <div className="min-h-screen w-full bg-canvas text-ink selection:bg-brand/20">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(faqJsonLd) }}
      />
      <SiteNav />

      <main className="pt-14">
        {/* ─── HERO ─── */}
        <section className="flex flex-col items-center px-5 sm:px-6 pt-20 pb-14 sm:pt-28 sm:pb-16">
          <Link
            href="/changelog"
            className="group inline-flex items-center gap-2 h-7 pl-1.5 pr-3 rounded-full bg-white border border-ink/[0.08] shadow-[0_1px_2px_rgba(0,0,0,0.03)] mb-8 hover:border-ink/[0.16] transition-colors"
          >
            <span className="inline-flex items-center h-[18px] px-2 rounded-full bg-brand/15 text-[10px] font-semibold text-brand tracking-wide">
              v{release.version}
            </span>
            <span className="text-[12px] text-ink/50 group-hover:text-ink/75 transition-colors">
              Auto-zoom, face cam &amp; share links
            </span>
            <ArrowUpRight className="h-3 w-3 text-ink/25 group-hover:text-ink/50 transition-colors" />
          </Link>

          <h1 className="text-center text-[clamp(34px,6.5vw,66px)] leading-[1.04] font-bold tracking-[-0.04em] text-ink max-w-[780px] text-balance">
            Beautiful screenshots and screen recordings,{" "}
            <span className="text-ink/30">without&nbsp;the&nbsp;subscription</span>
          </h1>

          <p className="text-center text-[16px] sm:text-[17px] leading-[1.65] text-ink/45 mt-6 max-w-[540px] text-pretty">
            One native macOS app for capture, annotation, cursor auto-zoom recording, and video
            editing. Everything stays on your Mac. Free and open source.
          </p>

          <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3 mt-9 w-full max-w-[340px] sm:max-w-none">
            <DownloadDropdown release={release} source="hero" className="w-full sm:w-auto" />
            <a
              href="https://github.com/KartikLabhshetwar/better-shot"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 px-5 h-12 text-[14px] font-medium text-ink/55 hover:text-ink bg-white border border-ink/[0.1] hover:border-ink/[0.18] rounded-xl transition-all"
            >
              <Github className="h-4 w-4" />
              View source
            </a>
          </div>

          <div className="flex flex-wrap justify-center items-center gap-x-5 gap-y-2 mt-7 text-[12px] text-ink/35">
            <TrustItem>Free forever</TrustItem>
            <TrustItem>No account</TrustItem>
            <TrustItem>macOS 14+</TrustItem>
            <TrustItem>Apple Silicon &amp; Intel</TrustItem>
          </div>
        </section>

        {/* ─── PRODUCT SHOT ─── */}
        <section className="max-w-[1000px] mx-auto px-5 sm:px-6 pb-14">
          <div className="rounded-2xl border border-ink/[0.07] bg-ink/[0.02] p-1.5 sm:p-2 shadow-[0_16px_60px_rgba(0,0,0,0.07)] overflow-hidden">
            <EditorPreview />
          </div>
        </section>

        {/* ─── SOCIAL PROOF ─── */}
        <section className="border-y border-ink/[0.06] bg-white/60">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6 py-8">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-6 sm:gap-8">
              <Stat
                value={
                  <a
                    href="https://github.com/KartikLabhshetwar/better-shot"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="hover:text-brand transition-colors"
                  >
                    <StarCount />
                  </a>
                }
                label="on GitHub"
              />
              <Stat value="$0" label="forever, no tiers" />
              <Stat value="0 KB" label="uploaded by default" />
              <Stat value="BSD-3" label="licensed, auditable" />
            </div>
          </div>
        </section>

        {/* ─── PROBLEM ─── */}
        <section className="py-20 sm:py-28">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6">
            <div className="max-w-[620px]">
              <SectionLabel>The problem</SectionLabel>
              <h2 className="text-[28px] sm:text-[38px] font-bold tracking-[-0.03em] text-ink leading-[1.15] mb-5">
                Sharing your screen should not cost three subscriptions
              </h2>
              <p className="text-[16px] leading-[1.75] text-ink/45">
                One app takes the screenshot. Another records the walkthrough. A third trims it.
                Each one wants an account, a monthly fee, and a copy of your screen on its servers.
                Then the free tier caps your recording at five minutes, right in the middle of the
                explanation.
              </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-5 mt-12">
              <PainCard
                title="Subscription creep"
                body="A screenshot tool, a recorder, and an editor add up to more per year than the Mac you run them on."
              />
              <PainCard
                title="Your screen, their servers"
                body="Client work, dashboards, and internal tools get uploaded to a vendor's cloud just to produce a link."
              />
              <PainCard
                title="Limits at the worst time"
                body="Five-minute caps, video quotas, watermarks, and export throttles land mid-demo, not before it."
              />
            </div>
          </div>
        </section>

        {/* ─── FEATURE 1: CAPTURE ─── */}
        <section id="features" className="border-t border-ink/[0.06] py-20 sm:py-28 scroll-mt-14">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6">
            <div className="flex flex-col md:flex-row md:items-center gap-12 md:gap-20">
              <div className="flex-1 min-w-0">
                <SectionLabel>Capture</SectionLabel>
                <h2 className="text-[26px] sm:text-[34px] font-bold tracking-[-0.03em] text-ink mb-5 leading-[1.15]">
                  Every kind of capture, one shortcut away
                </h2>
                <p className="text-[15px] leading-[1.8] text-ink/45 max-w-[420px] mb-8">
                  Region, fullscreen, or window. A floating preview appears after every shot, so you
                  can edit, copy, pin it on top of everything, or drag it straight into Figma, Slack,
                  or Finder.
                </p>
                <div className="flex flex-wrap gap-x-6 gap-y-3">
                  <FeatureBullet label="Region capture" />
                  <FeatureBullet label="Window capture" />
                  <FeatureBullet label="Fullscreen" />
                  <FeatureBullet label="Floating preview" />
                  <FeatureBullet label="OCR text extraction" />
                  <FeatureBullet label="Color picker" />
                  <FeatureBullet label="Pin on top" />
                  <FeatureBullet label="Capture history" />
                </div>
              </div>
              <div className="flex-1 flex justify-center">
                <MockScreenshotPreview />
              </div>
            </div>
          </div>
        </section>

        {/* ─── FEATURE 2: RECORDING ─── */}
        <section className="border-t border-ink/[0.06] bg-ink/[0.015] py-20 sm:py-28">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6">
            <div className="flex flex-col md:flex-row-reverse md:items-center gap-12 md:gap-20">
              <div className="flex-1 min-w-0">
                <SectionLabel>Record</SectionLabel>
                <h2 className="text-[26px] sm:text-[34px] font-bold tracking-[-0.03em] text-ink mb-5 leading-[1.15]">
                  Recordings that follow your cursor
                </h2>
                <p className="text-[15px] leading-[1.8] text-ink/45 max-w-[420px] mb-8">
                  Pick a display, a window, or an area, then record. Better Shot samples your pointer
                  at 30 Hz and turns clicks into smooth zoom moves, the way a screencast editor would,
                  so a 4K screen stays readable in a small video player.
                </p>
                <div className="flex flex-wrap gap-x-6 gap-y-3">
                  <FeatureBullet label="Cursor auto-zoom" />
                  <FeatureBullet label="Face cam bubble" />
                  <FeatureBullet label="Microphone & system audio" />
                  <FeatureBullet label="Single-window recording" />
                  <FeatureBullet label="24 / 30 / 60 fps" />
                  <FeatureBullet label="Pause & resume" />
                  <FeatureBullet label="Multi-display" />
                  <FeatureBullet label="Crash-resilient MP4" />
                </div>
              </div>
              <div className="flex-1 flex justify-center">
                <MockRecordingPill />
              </div>
            </div>
          </div>
        </section>

        {/* ─── FEATURE 3: EDIT & BEAUTIFY ─── */}
        <section className="border-t border-ink/[0.06] py-20 sm:py-28">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6">
            <div className="flex flex-col md:flex-row md:items-center gap-12 md:gap-20">
              <div className="flex-1 min-w-0">
                <SectionLabel>Edit</SectionLabel>
                <h2 className="text-[26px] sm:text-[34px] font-bold tracking-[-0.03em] text-ink mb-5 leading-[1.15]">
                  Cut it down, then make it look good
                </h2>
                <p className="text-[15px] leading-[1.8] text-ink/45 max-w-[420px] mb-8">
                  Split at the playhead, drag a clip edge to trim, speed a slow section up to 4x, and
                  delete what you do not want. Then drop the whole thing on a gradient with padding,
                  a corner radius, and a shadow, and export MP4.
                </p>
                <div className="flex flex-wrap gap-x-6 gap-y-3">
                  <FeatureBullet label="Multi-clip timeline" />
                  <FeatureBullet label="Per-clip speed 0.25–4x" />
                  <FeatureBullet label="Trim & split" />
                  <FeatureBullet label="Undo / redo" />
                  <FeatureBullet label="Gradients & wallpapers" />
                  <FeatureBullet label="Padding & shadows" />
                  <FeatureBullet label="Custom backgrounds" />
                  <FeatureBullet label="Zoom cue editing" />
                </div>
              </div>
              <div className="flex-1 flex justify-center">
                <MockEffectsPanel />
              </div>
            </div>
          </div>
        </section>

        {/* ─── SECONDARY FEATURES ─── */}
        <section className="border-t border-ink/[0.06] bg-ink/[0.015] py-20 sm:py-24">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-16 gap-y-14">
              <TextFeature
                title="Annotate with purpose"
                description="Arrows, shapes, text, numbered badges, blur, and spotlight. Each tool has a single-key shortcut, so you never leave the keyboard."
                features={[
                  "Arrows",
                  "Rectangles & circles",
                  "Text with fonts",
                  "Numbered badges",
                  "Blur regions",
                  "Spotlight",
                ]}
              />
              <TextFeature
                title="Share on your own storage"
                description="Connect a Cloudflare R2 bucket and the Share button uploads your edited recording straight from the app, then copies the public link. No proxy, no vendor in the middle."
                features={["Your own bucket", "Keychain-stored keys", "Direct SigV4 upload", "Edits baked in"]}
              />
              <TextFeature
                title="Crop with precision"
                description="Draggable corner and edge handles with a rule-of-thirds grid. Works on screenshots and recordings, and applies on export, so your annotations stay editable."
                features={["Corner & edge handles", "Rule-of-thirds grid", "Non-destructive", "Works on video"]}
              />
              <TextFeature
                title="Stay in flow"
                description="Drag the floating preview into any app, pin a reference screenshot above your work, and let your default background and padding apply to every capture automatically."
                features={["Drag into any app", "Pin to screen", "Always-on-top", "Auto-apply defaults"]}
              />
            </div>
          </div>
        </section>

        {/* ─── HOW IT WORKS ─── */}
        <section className="border-t border-ink/[0.06] py-20 sm:py-28">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6">
            <div className="max-w-[560px] mb-12">
              <SectionLabel>How it works</SectionLabel>
              <h2 className="text-[28px] sm:text-[36px] font-bold tracking-[-0.03em] text-ink leading-[1.15]">
                Installed and capturing in under a minute
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-10 sm:gap-8">
              <Step
                index="01"
                title="Install"
                body="brew install --cask bettershot, or grab the DMG. No sign-up screen, no license key, no onboarding tour."
              />
              <Step
                index="02"
                title="Hit a shortcut"
                body="⌘⇧4 for a region, ⌘⇧2 to record. Grant screen recording permission once and macOS never asks again."
              />
              <Step
                index="03"
                title="Edit and send"
                body="Annotate, trim, add a background, then copy, drag, export, or share a link from your own bucket."
              />
            </div>
          </div>
        </section>

        {/* ─── COMPARISON ─── */}
        <Comparison />

        {/* ─── VALUES ─── */}
        <section className="border-t border-ink/[0.06] py-20 sm:py-24">
          <div className="max-w-[960px] mx-auto px-5 sm:px-6">
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-10 sm:gap-12">
              <ValueProp
                icon={<Shield className="h-5 w-5" />}
                title="Local-first"
                description="Capture, edit, and export never leave your Mac. No accounts, no telemetry, no analytics inside the app."
              />
              <ValueProp
                icon={<Zap className="h-5 w-5" />}
                title="Native and fast"
                description="Swift 6 and SwiftUI, no Electron and no web views. Launches instantly, captures in milliseconds."
              />
              <ValueProp
                icon={<Sparkles className="h-5 w-5" />}
                title="Open source"
                description="BSD 3-Clause licensed. Read the code, file an issue, fork it, or ship a pull request."
              />
            </div>
          </div>
        </section>

        {/* ─── SHORTCUTS ─── */}
        <section className="border-t border-ink/[0.06] py-20 sm:py-24">
          <div className="max-w-[560px] mx-auto px-5 sm:px-6">
            <h2 className="text-[13px] font-semibold text-ink/30 tracking-[0.12em] uppercase text-center mb-8">
              Keyboard shortcuts
            </h2>
            <div className="divide-y divide-ink/[0.06] border border-ink/[0.07] rounded-2xl overflow-hidden bg-white">
              <Shortcut label="Capture region" keys={["⌘", "⇧", "4"]} />
              <Shortcut label="Capture screen" keys={["⌘", "⇧", "3"]} />
              <Shortcut label="Capture window" keys={["⌘", "⇧", "5"]} />
              <Shortcut label="Record screen" keys={["⌘", "⇧", "2"]} />
              <Shortcut label="OCR text scan" keys={["⌘", "⇧", "O"]} />
              <Shortcut label="Color picker" keys={["⌘", "⇧", "C"]} />
            </div>
            <p className="text-[12px] text-ink/30 text-center mt-4">
              All six are remappable in Settings.
            </p>
          </div>
        </section>

        {/* ─── FAQ ─── */}
        <FaqSection />

        {/* ─── FINAL CTA ─── */}
        <section className="border-t border-ink/[0.06] bg-ink/[0.015] py-24">
          <div className="text-center px-5 sm:px-6">
            <h2 className="text-[28px] sm:text-[36px] font-bold tracking-[-0.03em] text-ink mb-4">
              Stop paying to share your screen
            </h2>
            <p className="text-[16px] leading-[1.7] text-ink/45 mb-9 max-w-[420px] mx-auto text-pretty">
              Free, open source, and yours in about thirty seconds. No account, no card, no trial
              countdown.
            </p>
            <div className="flex flex-col items-center gap-5">
              <DownloadDropdown
                release={release}
                source="cta"
                className="w-full max-w-[300px] sm:w-auto"
              />
              <div className="flex items-center gap-2 text-[12.5px] text-ink/40 font-mono bg-white border border-ink/[0.07] px-4 py-2.5 rounded-lg">
                <span className="text-ink/25">$</span>
                brew install --cask bettershot
              </div>
            </div>
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  )
}

/* ─── Hero and proof ─── */

function TrustItem({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="h-1 w-1 rounded-full bg-ink/20" />
      {children}
    </span>
  )
}

function Stat({ value, label }: { value: React.ReactNode; label: string }) {
  return (
    <div className="text-center">
      <div className="text-[19px] sm:text-[22px] font-bold tracking-[-0.02em] text-ink/80 tabular-nums">
        {value}
      </div>
      <div className="text-[12px] text-ink/35 mt-0.5">{label}</div>
    </div>
  )
}

function PainCard({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-2xl border border-ink/[0.07] bg-white p-6">
      <h3 className="text-[15px] font-semibold text-ink/85 mb-2">{title}</h3>
      <p className="text-[13.5px] leading-[1.7] text-ink/45">{body}</p>
    </div>
  )
}

function Step({ index, title, body }: { index: string; title: string; body: string }) {
  return (
    <div>
      <div className="text-[12px] font-mono font-semibold text-brand mb-3">{index}</div>
      <h3 className="text-[17px] font-bold tracking-[-0.02em] text-ink mb-2">{title}</h3>
      <p className="text-[14px] leading-[1.75] text-ink/45">{body}</p>
    </div>
  )
}

/* ─── Primary feature mocks ─── */

function MockScreenshotPreview() {
  return (
    <div className="w-full max-w-[360px]">
      <div className="rounded-xl bg-white border border-ink/[0.08] shadow-[0_8px_30px_rgba(0,0,0,0.07)] overflow-hidden">
        <div className="h-8 bg-[#fafafa] border-b border-ink/[0.06] flex items-center px-3 gap-[6px]">
          <span className="w-2.5 h-2.5 rounded-full bg-[#ff5f57]" />
          <span className="w-2.5 h-2.5 rounded-full bg-[#febc2e]" />
          <span className="w-2.5 h-2.5 rounded-full bg-[#28c840]" />
          <span className="flex-1 text-center text-[10px] text-ink/30">Preview</span>
        </div>
        <div className="p-4">
          <div
            className="aspect-[16/10] rounded-md overflow-hidden flex items-center justify-center"
            style={{
              background: "linear-gradient(135deg, #ec4899, #8b5cf6, #3b82f6)",
              padding: "10%",
            }}
          >
            <div className="w-full h-full rounded bg-[#1a1a2e] flex items-center justify-center">
              <div className="text-center">
                <div className="text-[20px] mb-1">⌘</div>
                <div className="text-[10px] text-white/50">screenshot.png</div>
              </div>
            </div>
          </div>
        </div>
        <div className="px-4 pb-3.5 flex gap-2">
          <span className="text-[10px] text-ink/40 bg-ink/[0.04] px-2.5 py-1 rounded">Edit</span>
          <span className="text-[10px] text-ink/40 bg-ink/[0.04] px-2.5 py-1 rounded">Copy</span>
          <span className="text-[10px] text-ink/40 bg-ink/[0.04] px-2.5 py-1 rounded">Pin</span>
          <span className="text-[10px] text-ink/40 bg-ink/[0.04] px-2.5 py-1 rounded">Drag out</span>
        </div>
      </div>
    </div>
  )
}

function MockRecordingPill() {
  return (
    <div className="flex flex-col items-center gap-5 w-full max-w-[360px]">
      <div className="inline-flex items-center gap-3 bg-[#1a1a1a] rounded-full px-5 py-3 shadow-[0_12px_40px_rgba(0,0,0,0.28)]">
        <div className="flex items-center gap-2">
          <span className="relative flex h-2.5 w-2.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-red-400 opacity-75" />
            <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-red-500" />
          </span>
          <span className="text-[13px] font-mono text-white/80 tabular-nums">02:34</span>
        </div>
        <span className="h-4 w-px bg-white/10" />
        <div className="flex items-center gap-1.5">
          {["⏸", "■", "↻", "✕"].map((icon) => (
            <span
              key={icon}
              className="h-7 w-7 rounded-full bg-white/10 flex items-center justify-center text-[11px] text-white/60"
            >
              {icon}
            </span>
          ))}
        </div>
      </div>

      <div className="w-full rounded-xl border border-ink/[0.07] bg-white p-4 shadow-[0_8px_30px_rgba(0,0,0,0.05)]">
        <div className="flex items-center justify-between mb-3">
          <span className="text-[10px] font-semibold text-ink/30 tracking-widest uppercase">
            Zoom cues
          </span>
          <span className="text-[10px] text-ink/30 font-mono">1.8x</span>
        </div>
        <div className="h-9 rounded-md bg-ink/[0.04] flex items-center gap-1 px-1.5 overflow-hidden">
          {[18, 34, 26, 44, 30, 38, 22, 30, 40, 24].map((height, i) => (
            <span
              key={i}
              className="flex-1 rounded-sm bg-ink/10"
              style={{ height: `${height}%` }}
            />
          ))}
        </div>
        <div className="relative h-6 mt-1.5">
          <span className="absolute left-[18%] top-1 h-4 px-1.5 rounded bg-brand/15 text-[9px] font-medium text-brand flex items-center">
            zoom
          </span>
          <span className="absolute left-[58%] top-1 h-4 px-1.5 rounded bg-brand/15 text-[9px] font-medium text-brand flex items-center">
            zoom
          </span>
        </div>
      </div>
    </div>
  )
}

function MockEffectsPanel() {
  const gradients = [
    "linear-gradient(135deg, #a8edea, #fed6e3)",
    "linear-gradient(135deg, #3b82f6, #8b5cf6)",
    "linear-gradient(135deg, #f97316, #ec4899)",
    "linear-gradient(135deg, #ec4899, #8b5cf6, #3b82f6)",
    "linear-gradient(135deg, #22c55e, #06b6d4)",
    "linear-gradient(135deg, #eab308, #f97316)",
  ]
  return (
    <div className="w-full max-w-[280px]">
      <div className="rounded-xl bg-white border border-ink/[0.08] shadow-[0_8px_30px_rgba(0,0,0,0.06)] p-5">
        <div className="text-[10px] font-semibold text-ink/30 tracking-widest uppercase mb-4">
          Effects
        </div>
        <SliderMock label="Padding" value="8%" progress={40} />
        <SliderMock label="Corner Radius" value="18" progress={45} />
        <SliderMock label="Shadow" value="36%" progress={55} />
        <SliderMock label="Speed" value="1.5x" progress={62} />
        <div className="mt-5">
          <div className="text-[10px] font-semibold text-ink/30 tracking-widest uppercase mb-3">
            Background
          </div>
          <div className="grid grid-cols-6 gap-1.5">
            {gradients.map((gradient, i) => (
              <div
                key={i}
                className="aspect-square rounded"
                style={{
                  background: gradient,
                  border: i === 3 ? "2px solid #3b82f6" : "1px solid rgba(0,0,0,0.06)",
                  boxShadow: i === 3 ? "0 0 0 2px rgba(59,130,246,0.2)" : "none",
                }}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

function SliderMock({ label, value, progress }: { label: string; value: string; progress: number }) {
  return (
    <div className="mb-3">
      <div className="flex justify-between mb-1.5">
        <span className="text-[11px] text-ink/40">{label}</span>
        <span className="text-[11px] text-ink/55 font-medium">{value}</span>
      </div>
      <div className="h-1 bg-ink/[0.06] rounded-full overflow-hidden">
        <div className="h-full bg-blue-500 rounded-full" style={{ width: `${progress}%` }} />
      </div>
    </div>
  )
}

/* ─── Secondary features ─── */

function TextFeature({
  title,
  description,
  features,
}: {
  title: string
  description: string
  features: string[]
}) {
  return (
    <div>
      <h3 className="text-[19px] font-bold tracking-[-0.02em] text-ink mb-2.5">{title}</h3>
      <p className="text-[14px] leading-[1.75] text-ink/45 mb-5">{description}</p>
      <div className="flex flex-wrap gap-x-5 gap-y-2">
        {features.map((feature) => (
          <FeatureBullet key={feature} label={feature} />
        ))}
      </div>
    </div>
  )
}

/* ─── Shared ─── */

function FeatureBullet({ label }: { label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-[13px] text-ink/50">
      <span className="h-1 w-1 rounded-full bg-brand" />
      {label}
    </span>
  )
}

function ValueProp({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode
  title: string
  description: string
}) {
  return (
    <div>
      <div className="h-10 w-10 rounded-xl bg-white border border-ink/[0.07] flex items-center justify-center text-ink/45 mb-4">
        {icon}
      </div>
      <h3 className="text-[15px] font-semibold text-ink/85 mb-2">{title}</h3>
      <p className="text-[13.5px] leading-[1.7] text-ink/45">{description}</p>
    </div>
  )
}

function Shortcut({ label, keys }: { label: string; keys: string[] }) {
  return (
    <div className="flex items-center justify-between px-5 py-3.5">
      <span className="text-[13.5px] text-ink/55">{label}</span>
      <div className="flex items-center gap-1">
        {keys.map((key, i) => (
          <kbd
            key={i}
            className="inline-flex items-center justify-center h-6 min-w-[24px] px-1.5 text-[11px] font-medium text-ink/55 bg-canvas border border-ink/[0.08] rounded-md shadow-[0_1px_0_rgba(0,0,0,0.04)]"
          >
            {key}
          </kbd>
        ))}
      </div>
    </div>
  )
}
